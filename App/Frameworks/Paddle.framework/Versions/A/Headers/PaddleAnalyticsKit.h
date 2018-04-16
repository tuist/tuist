//
//  PaddleAnalyticsKit.h
//  PaddleAnalytics
//
//  Created by Louis Harwood on 26/08/2014.
//  Copyright (c) 2014 Paddle. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef enum appStores
{
    PAKPaddle,
    PAKiOS,
    PAKMacAppStore,
    PAKOther
} Store;

@interface PaddleAnalyticsKit : NSObject

+ (void)startTracking;
+ (void)track:(nonnull NSString *)action properties:(nullable NSDictionary *)properties;
+ (void)trackInstant:(nonnull NSString *)action properties:(nullable NSDictionary *)properties;
+ (void)identify:(nonnull NSString *)identifier;
+ (void)payment:(nonnull NSNumber *)amount currency:(nonnull NSString *)currency product:(nonnull NSString *)product store:(Store)store;

+ (void)disableTracking;
+ (void)enableTracking;

+ (void)enableOptin;
+ (BOOL)isOptedIn;
+ (void)presentOptinDialog;




@end
