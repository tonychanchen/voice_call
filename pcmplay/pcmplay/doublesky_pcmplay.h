//
//  doublesky_pcmplay.h
//  pcmplay
//
//  Created by zz on 2020/5/16.
//  Copyright © 2020 zz. All rights reserved.
//

#define doublesky_pcmsize 2048
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface doublesky_pcmplay : NSObject
- (void)push:(char *)buffer size:(int)size;
@end

NS_ASSUME_NONNULL_END
