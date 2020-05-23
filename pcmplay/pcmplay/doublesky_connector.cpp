//
//  doublesky_connector.cpp
//  audio
//
//  Created by zz on 2020/5/16.
//  Copyright © 2020 zz. All rights reserved.
//

#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#include <iostream>

#include "doublesky_connector.hpp"

#define doublesky_udp_max 1472

void doublesky_connector::start_client()
{
    state = doublesky_state_connecting;
    connect_callback(state);
    int ret = -1;
    int reuse = 1;
    struct sockaddr_in dst = {0};
    char buffer[8], recv_buffer[8];
    memset(buffer, 0, sizeof(buffer));
    memset(recv_buffer, 0, sizeof(recv_buffer));
    memcpy(buffer, "connect", 8);
    
    sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (sock < 0)
        goto end;
    
    if (setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse)) < 0)
        goto end;
    
    reuse = 1;
    if (setsockopt(sock, SOL_SOCKET, SO_REUSEPORT, &reuse, sizeof(reuse)) < 0)
        goto end;
    
    reuse = 1;
    if (setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &reuse, sizeof(reuse)) < 0)
        goto end;
    
    dst.sin_family = AF_INET;
    dst.sin_addr.s_addr = INADDR_BROADCAST;
    dst.sin_port = htons(8888);
    
    for (int i = 0; i < 15; ++i)
    {
        if (!can_read_write(sock, sock_write, 1000))
            continue;
        
        // 未获取网络权限的情况下 sendto会失败
        if (sendto(sock, (void*)buffer, sizeof(buffer), 0, (const struct sockaddr*)&dst, sizeof(dst)) < 0)
            continue;
        
        if (!can_read_write(sock, sock_read, 1000))
            continue;
        
        // 此处有个小坑 recvfrom的recv_length一定不能传0 传0会导致获取不到对方ip地址
        struct sockaddr_in recv_addr;
        socklen_t recv_length;
        memset(&recv_addr, 0, sizeof(struct sockaddr_in));
        if (recvfrom(sock, recv_buffer, sizeof(recv_buffer), 0, (struct sockaddr*)&recv_addr, &recv_length) < 0)
            continue;
        
//        short port = ntohs(recv_addr.sin_port);
//        char *ip = inet_ntoa(recv_addr.sin_addr);
        if (memcmp(recv_buffer, "connect", 7) != 0)
            continue;
        
        if ((ret = connect(sock, (struct sockaddr*)&recv_addr, recv_length)) == 0)
            break;
    }
    
end:
    if (ret != 0)
    {
        close(sock);
        state = doublesky_state_connect_failed;
        connect_callback(state);
        
        state = doublesky_state_idle;
    }
    else
    {
        recv_stop = false;
        state = doublesky_state_connected;
        start_recv();
    }
    connect_callback(state);
}

void doublesky_connector::start_service()
{
    state = doublesky_state_connecting;
    connect_callback(state);
    int ret = -1;
    int reuse = 1;
    struct sockaddr_in addr;
    addr.sin_family = AF_INET;
    addr.sin_port = htons(8888);
    addr.sin_addr.s_addr = INADDR_ANY;
    if ((sock = socket(AF_INET, SOCK_DGRAM, 0)) < 0)
        goto end;
    
    if (setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse)) < 0)
        goto end;
    
    reuse = 1;
    if (setsockopt(sock, SOL_SOCKET, SO_REUSEPORT, &reuse, sizeof(reuse)) < 0)
        goto end;
    
    if (bind(sock, (struct sockaddr*)&addr, sizeof(struct sockaddr)) < 0)
        goto end;
    
    for (int i = 0; i < 15; ++i)
    {
        if (!can_read_write(sock, sock_read, 1000))
            continue;
        
        struct sockaddr_in recv_addr;
        socklen_t recv_length;
        memset(&recv_addr, 0, sizeof(struct sockaddr_in));
        char buffer[8];
        memset(buffer, 0, 8);
        if (recvfrom(sock, buffer, sizeof(buffer), 0, (struct sockaddr*)&recv_addr, &recv_length) < 0)
            continue;
        
        if (memcmp(buffer, "connect", 7) != 0)
            continue;
        
        if (!can_read_write(sock, sock_write, 1000))
            continue;
            
        if (sendto(sock, "connect", 8, 0, (struct sockaddr*)&recv_addr, recv_length) < 0)
            continue;
        
        if (connect(sock, (struct sockaddr*)&recv_addr, recv_length) == 0)
        {
            ret = 0;
            break;
        }
    }
    
end:
    if (ret < 0)
    {
        state = doublesky_state_connect_failed;
        connect_callback(state);
        
        state = doublesky_state_idle;
        close(ret);
    }
    else
    {
        recv_stop = false;
        state = doublesky_state_connected;
        start_recv();
    }
    
    connect_callback(state);
}

bool doublesky_connector::can_read_write(int s, int rw, int time_out)
{
    fd_set set;
    FD_ZERO(&set);
    FD_SET(s, &set);
    struct timeval time;
    time.tv_sec = time_out/1000;
    time.tv_usec = time_out%1000;
    if (select(s+1, (rw & sock_read) ? &set : NULL, (rw & sock_write) ? &set : NULL, NULL, &time) < 0)
        return false;
    
    if (FD_ISSET(s, &set) == 0)
        return false;
    
    return true;
}

void doublesky_connector::start_recv()
{
    // 如果当前对象可被joinable,则会调用terminate()报错
    // https://www.runoob.com/w3cnote/cpp-std-thread.html C++ std::thread
    recv_thread = std::thread([this]
    {
        while(!recv_stop)
        {
            if (!can_read_write(sock, sock_read, 1000))
                continue;
            
            ssize_t size = 0;
            char buffer[doublesky_udp_max];
            memset(buffer, 0, doublesky_udp_max);
            if ((size = recv(sock, buffer, sizeof(buffer), 0)) < 0)
            {
                if (errno == EINTR)
                    continue;
                
                // 这里以为可连接的udp会返回ICMP的EHOSTUNREACH 结果是ECONNREFUSED
                if (errno == ECONNREFUSED)
                {
                    state = doublesky_state_cannotreach;
                    connect_callback(state);
                    break;
                }
                
//                std::cout << errno <<std::endl;
            }
            else
            {
                char *pcm = (char*)calloc(1, size);
                memcpy(pcm, buffer, size);
                recv_callback(pcm, (int)size);
            }
        }
        state = doublesky_state_idle;
        connect_callback(state);
    });
    recv_thread.detach();
}

void doublesky_connector::push_audio(char *b, int size)
{
    std::unique_lock<std::mutex> lock(send_mutex, std::defer_lock);
    lock.lock();
    send_queue.emplace(b, size);
    lock.unlock();
    send_cond.notify_one();
}

doublesky_connector::doublesky_connector()
{
    send_thread = std::thread([this]
    {
        std::unique_lock<std::mutex> lock(send_mutex, std::defer_lock);
        while(!send_stop)
        {
            lock.lock();
            send_cond.wait(lock, [this]{return send_stop || !send_queue.empty();});
            if (send_stop)
                continue;
            
            char *tmp = send_queue.front().first.get();
            unsigned int size = send_queue.front().second, offset = 0;
            while(size > 0)
            {
                if (size >= doublesky_udp_max)
                {
                    send(sock, tmp+offset, doublesky_udp_max, 0);
                    offset += doublesky_udp_max;
                    size -= doublesky_udp_max;
                }
                else
                {
                    send(sock, tmp+offset, size, 0);
                    size = 0;
                }
            }
            
            send_queue.pop();
            lock.unlock();
        }
    });
}

doublesky_connector::~doublesky_connector()
{
    send_stop = true;
    recv_stop = true;
    send_cond.notify_one();
    send_thread.join();
    recv_thread.join();
}
