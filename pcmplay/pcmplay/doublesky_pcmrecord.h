//
//  doublesky_pcmrecord.h
//  pcmplay
//
//  Created by zz on 2020/5/16.
//  Copyright © 2020 zz. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef void(*doublesky_record_callback)(char * _Nullable buffer, int size, void *u);

NS_ASSUME_NONNULL_BEGIN

@interface doublesky_pcmrecord : NSObject

- (void)set_record_callback:(doublesky_record_callback)c user:(void *)u;
- (void)start_record;
- (void)stop_record;
@end

NS_ASSUME_NONNULL_END
