//
//  doublesky_connector.hpp
//  audio
//
//  Created by zz on 2020/5/16.
//  Copyright © 2020 zz. All rights reserved.
//

#ifndef doublesky_connector_hpp
#define doublesky_connector_hpp

#include <stdio.h>

#include <thread>
#include <queue>
#include <memory>

typedef enum doublesky_state
{
    doublesky_state_idle = 0,
    doublesky_state_connecting,
    doublesky_state_connected,
    doublesky_state_forbid,
    doublesky_state_cannotreach,
    doublesky_state_connect_failed,
} doublesky_state;

class doublesky_connector
{
    typedef enum sock_readwrite {
        sock_read = 1 << 0,
        sock_write = 1 << 1,
    } sock_readwrite;
    
public:
    doublesky_connector();
    ~doublesky_connector();
    void start_client();
    void start_service();
    void push_audio(char *b, int size);
    void start_recv();
    doublesky_state state;
    void set_connect_callback(std::function<void(int)> &&f)
    {
        connect_callback = f;
    };
    
    void set_recv_callback(std::function<void(char*, int)> &&f)
    {
        recv_callback = f;
    }
    
    void stop_recv()
    {
        recv_stop = false;
        close(sock);
        sock = 0;
        state = doublesky_state_idle;
        connect_callback(state);
    }
    
private:
    int sock;
    std::thread send_thread, recv_thread;
    bool send_stop, recv_stop;
    std::queue<std::pair<std::shared_ptr<char>, unsigned int>> send_queue;
    std::mutex send_mutex;
    std::condition_variable send_cond;
    std::function<void(int)> connect_callback;
    std::function<void(char*, int)> recv_callback;
    
    bool can_read_write(int s, int rw, int time_out);
};
#endif /* doublesky_connector_hpp */
