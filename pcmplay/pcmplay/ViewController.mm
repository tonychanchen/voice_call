//
//  ViewController.m
//  pcmplay
//
//  Created by zz on 2020/5/16.
//  Copyright © 2020 zz. All rights reserved.
//

#import "ViewController.h"

#include <functional>

#import <AVFoundation/AVFoundation.h>

#import "doublesky_pcmplay.h"
#import "doublesky_pcmrecord.h"
#import "doublesky_connector.hpp"

@interface ViewController ()
{
    doublesky_pcmplay *pcm;
    doublesky_pcmrecord *record;
    doublesky_connector client, server;
}

@property (weak, nonatomic) IBOutlet UIButton *client_btn;
@property (weak, nonatomic) IBOutlet UIButton *server_btn;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    UIWebView *a = [[UIWebView alloc] init];
    [a loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"www.baidu.com"]]];
    
    BOOL ret = [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker error:nil];
    [[AVAudioSession sharedInstance] setActive:YES error:nil];
    assert(ret);
    
    pcm = [[doublesky_pcmplay alloc] init];
    assert(pcm);
    
    record = [[doublesky_pcmrecord alloc] init];
    [record set_record_callback:record_callback user:(__bridge void * _Nonnull)(self)];
    assert(record);
    
//    [record start_record];
    [self set_callback];
    [self ui];
}

- (void)viewDidAppear:(BOOL)animated
{
    return;
    FILE *fp = fopen([[[NSBundle mainBundle] pathForResource:@"test.pcm" ofType:nil] UTF8String], "rb");
    if (!fp) return;
    char buffer[doublesky_pcmsize];
    memset(buffer, 0, doublesky_pcmsize);
    unsigned long size = 0;
    while((size = fread(buffer, 1, doublesky_pcmsize, fp)) > 0)
    {
        char *tmp = (char*)calloc(1, size);
        if (!tmp) break;
        
        memcpy(tmp, buffer, size);
        [pcm push:tmp size:size];
    }
    fclose(fp);
}

#pragma mark - record_callback
static void record_callback(char *buffer, int size, void *user)
{
    ViewController *vc = (__bridge ViewController *)(user);
//    [vc->pcm push:buffer size:size];
//
//    return;
    if (vc->client.state == doublesky_state_connected)
        vc->client.push_audio(buffer, size);
    
    if (vc->server.state == doublesky_state_connected)
        vc->server.push_audio(buffer, size);
}

- (void)client_btn_click
{
    if (client.state == doublesky_state_idle)
    {
        [self set_btn:self.server_btn state:doublesky_state_forbid str:@""];
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            self->client.start_client();
        });
    }
    else if (client.state == doublesky_state_connected)
    {
        client.stop_recv();
        [record stop_record];
    }
    else if (client.state == doublesky_state_connecting)
    {
        [self show_str:@"正在连接,请确认另外一台手机在同一个局域网下且开启了服务端"];
    }
}

- (void)server_btn_click
{
    [self set_btn:self.client_btn state:doublesky_state_forbid str:@""];
    if (server.state == doublesky_state_idle)
    {
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            self->server.start_service();
        });
    }
    else if (server.state == doublesky_state_connected)
    {
        server.stop_recv();
        [record stop_record];
    }
    else if (server.state == doublesky_state_connecting)
    {
        [self show_str:@"正在连接,请确认另外一台手机在同一个局域网下且开启了客户端"];
    }
}

- (void)set_btn:(UIButton *)btn state:(doublesky_state)state str:(NSString *)str
{
    switch (state)
    {
        case doublesky_state_idle:
            [btn setTitle:[NSString stringWithFormat:@"%@开启", str] forState:UIControlStateNormal];
            [btn setTitleColor:[UIColor blueColor] forState:UIControlStateNormal];
            break;
        case doublesky_state_connecting:
            [btn setTitle:[NSString stringWithFormat:@"%@连接中", str] forState:UIControlStateNormal];
            [btn setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
            break;
        case doublesky_state_connected:
            [btn setTitle:[NSString stringWithFormat:@"对讲中"] forState:UIControlStateNormal];
            [btn setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
            break;
        case doublesky_state_forbid:
            [btn setTitle:[NSString stringWithFormat:@"不可用"] forState:UIControlStateNormal];
            [btn setTitleColor:[UIColor grayColor] forState:UIControlStateNormal];
            break;
        default:
            break;
    }
    
    btn.enabled = (state == doublesky_state_forbid) ? NO : YES;
}

- (void)ui
{
    [self.client_btn addTarget:self action:@selector(client_btn_click) forControlEvents:UIControlEventTouchUpInside];
    [self.server_btn addTarget:self action:@selector(server_btn_click) forControlEvents:UIControlEventTouchUpInside];
}

- (void)set_callback
{
    client.set_connect_callback(std::bind([self](int state)
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (state == doublesky_state_connected)
                [self->record start_record];
            
            [self set_btn:self.client_btn state:(doublesky_state)state str:@"客户端"];
            if (state == doublesky_state_cannotreach)
            {
                [self show_str:@"对方已关闭连接"];
                [self->record stop_record];
            }
            else if (state == doublesky_state_connect_failed)
            {
                [self show_str:@"连接失败"];
            }
        });
    }, std::placeholders::_1));
    
    server.set_connect_callback(std::bind([self](int state)
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (state == doublesky_state_connected)
                [self->record start_record];
            
            [self set_btn:self.server_btn state:(doublesky_state)state str:@"服务端"];
            if (state == doublesky_state_cannotreach)
            {
                [self show_str:@"对方已关闭连接"];
                [self->record stop_record];
            }
            else if (state == doublesky_state_connect_failed)
            {
                [self show_str:@"连接失败"];
            }
        });
    }, std::placeholders::_1));
    
    client.set_recv_callback(std::bind([self](char *b, int size)
    {
        if (!b || size < 1)
            return;
        
        [self->pcm push:b size:size];
    }, std::placeholders::_1, std::placeholders::_2));
    
    server.set_recv_callback(std::bind([self](char *b, int size)
    {
        if (!b || size < 1)
            return;
        
        [self->pcm push:b size:size];
    }, std::placeholders::_1, std::placeholders::_2));
}

- (void)show_str:(NSString *)str
{
    UIAlertController *vc = [UIAlertController alertControllerWithTitle:str message:nil preferredStyle:UIAlertControllerStyleAlert];
    [vc addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:vc animated:YES completion:nil];
}
@end
