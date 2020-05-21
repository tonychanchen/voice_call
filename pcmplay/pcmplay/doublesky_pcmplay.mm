//
//  doublesky_pcmplay.m
//  pcmplay
//
//  Created by zz on 2020/5/16.
//  Copyright © 2020 zz. All rights reserved.
//

#include <queue>
#include <thread>

#import <AudioToolbox/AudioQueue.h>

#import "doublesky_pcmplay.h"


#define bufferCount 3

@interface doublesky_pcmplay()
{
    AudioStreamBasicDescription des;
    AudioQueueRef audioQueue;
    AudioQueueBufferRef buffer[bufferCount];
    std::queue<std::pair<std::shared_ptr<char>, int>> queue;
    std::mutex mutex;
}
@end

@implementation doublesky_pcmplay
- (instancetype)init
{
    self = [super init];
    if (!self) return nil;

    des.mSampleRate = 44100;
    des.mFormatID = kAudioFormatLinearPCM;
    des.mFormatFlags = kAudioFormatFlagIsSignedInteger;
    des.mFramesPerPacket = 1;
    des.mChannelsPerFrame = 1;
    des.mBitsPerChannel = 16;
    des.mBytesPerPacket = 2;
    des.mBytesPerFrame = 2;
    OSStatus ret = -1;
    
    ret = AudioQueueNewOutput(&des, &playcallback, (__bridge void * _Nullable)(self), NULL, NULL, 0, &audioQueue);
    if (ret != noErr)
        return nil;

    for (int i = 0; i < bufferCount; ++i)
    {
        ret = AudioQueueAllocateBuffer(audioQueue, doublesky_pcmsize, &buffer[i]);
        buffer[i]->mAudioDataByteSize = doublesky_pcmsize;
        memset(buffer[i]->mAudioData, 0, doublesky_pcmsize);
        ret = AudioQueueEnqueueBuffer(audioQueue, buffer[i], 0, NULL);
    }

    ret = AudioQueueStart(audioQueue, NULL);

    return self;
}

static void playcallback(void * __nullable inUserData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer)
{
    doublesky_pcmplay *player = (__bridge doublesky_pcmplay*)(inUserData);

    std::unique_lock<std::mutex> lock(player->mutex);
    if (player->queue.empty())
    {
        inBuffer->mAudioDataByteSize = doublesky_pcmsize;
        memset(inBuffer->mAudioData, 0, inBuffer->mAudioDataByteSize);
        AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, NULL);
    }
    else
    {
        auto &tmp = player->queue.front();
        inBuffer->mAudioDataByteSize = tmp.second;
        memcpy(inBuffer->mAudioData, tmp.first.get(), inBuffer->mAudioDataByteSize);
        int ret = AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, NULL);
        player->queue.pop();
    }
}

- (void)push:(char *)buffer size:(int)size
{
    std::unique_lock<std::mutex> lock;
    queue.emplace(buffer, size);
}
@end
