//
//  doublesky_pcmrecord.m
//  pcmplay
//
//  Created by zz on 2020/5/16.
//  Copyright © 2020 zz. All rights reserved.
//

#import "doublesky_pcmrecord.h"

#include <thread>
#include <queue>
#include <memory>

#import <AudioUnit/AudioUnit.h>

@interface doublesky_pcmrecord()
{
    AudioUnit audioUnit;
    std::queue<std::pair<std::shared_ptr<char>, int>> queue;
    std::mutex mutex;
    doublesky_record_callback callback;
    void *user;
}

@end
@implementation doublesky_pcmrecord
- (instancetype)init
{
    self = [super init];
    if (!self) return nil;
    
    AudioComponentDescription des;
    des.componentFlags = 0;
    des.componentFlagsMask = 0;
    des.componentManufacturer = kAudioUnitManufacturer_Apple;
    des.componentType = kAudioUnitType_Output;
    des.componentSubType = kAudioUnitSubType_VoiceProcessingIO;
//    des.componentSubType = kAudioUnitSubType_RemoteIO;
    
    AudioComponent audioComponent;
    audioComponent = AudioComponentFindNext(NULL, &des);
    OSStatus ret = AudioComponentInstanceNew(audioComponent, &audioUnit);
    if (ret != noErr)
        return nil;
    
    AudioStreamBasicDescription outStreamDes;
    outStreamDes.mSampleRate = 44100;
    outStreamDes.mFormatID = kAudioFormatLinearPCM;
    outStreamDes.mFormatFlags = kAudioFormatFlagIsSignedInteger;
    outStreamDes.mFramesPerPacket = 1;
    outStreamDes.mChannelsPerFrame = 1;
    outStreamDes.mBitsPerChannel = 16;
    outStreamDes.mBytesPerFrame = 2;
    outStreamDes.mBytesPerPacket = 2;
    outStreamDes.mReserved = 0;
    
    UInt32 flags = 1;
    ret = AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &flags, sizeof(flags));
    if (ret != noErr)
        return nil;
    
    ret = AudioUnitSetProperty(audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &outStreamDes, sizeof(outStreamDes));
    if (ret != noErr)
        return nil;
    
    AURenderCallbackStruct callback;
    callback.inputProc = record_callback;
    callback.inputProcRefCon = (__bridge void * _Nullable)(self);
    ret = AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 1, &callback, sizeof(callback));
    if (ret != noErr)
        return nil;

    return self;
}

static OSStatus record_callback(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrame, AudioBufferList *__nullable ioData)
{
    doublesky_pcmrecord *r = (__bridge doublesky_pcmrecord *)(inRefCon);
    // 这里被坑惨了AudioBufferList如果自己初始化并且分配mData内存 在AVAudioSessionCategoryPlayAndRecord模式并且使用扬声器播放时 AudioUnitRender时会返回-50 kAudioOutputUnitProperty_SetInputCallback有说明 Note that the inputProc will always receive a NULL AudioBufferList in ioData
    AudioBufferList tmp;
    tmp.mNumberBuffers = 1;
    tmp.mBuffers[0].mData = NULL;
    tmp.mBuffers[0].mDataByteSize = 0;
    tmp.mBuffers[0].mNumberChannels = 1;
    
    OSStatus error = AudioUnitRender(r->audioUnit, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrame, &tmp);
    static FILE *fp = NULL;
    if (!fp)
        fp = fopen([[NSHomeDirectory() stringByAppendingFormat:@"/Documents/io.pcm"] UTF8String], "wb");
//    if (error == noErr)
//        fwrite(tmp.mBuffers[0].mData, 1, tmp.mBuffers[0].mDataByteSize, fp);
    
    if (error != noErr)
        NSLog(@"record_callback error : %d", error);
    
    int size = tmp.mBuffers[0].mDataByteSize;
    char *src = (char*)tmp.mBuffers[0].mData;
    if (size > 0 && src)
    {
        char *dst = (char*)calloc(1, size);
        memcpy(dst, src, size);
        if (r->callback)
            r->callback(dst, size, r->user);
    }
    
    
    return error;
}

- (void)start_record
{
    AudioOutputUnitStart(audioUnit);
}

- (void)stop_record
{
    AudioOutputUnitStop(audioUnit);
    std::unique_lock<std::mutex> lock(mutex);
    decltype(queue) empty;
    std::swap(empty, queue);
}

- (void)set_record_callback:(doublesky_record_callback)c user:(nonnull void *)u
{
    callback = c;
    user = u;
}

- (void)dealloc
{
    callback = NULL;
    user = NULL;
}
@end
