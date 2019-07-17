//
//  SentryThread.h
//  Sentry
//
//  Created by Daniel Griesser on 05/05/2017.
//  Copyright © 2017 Sentry. All rights reserved.
//

#import <Foundation/Foundation.h>

#if __has_include(<Sentry/Sentry.h>)
#import <Sentry/SentryDefines.h>
#import <Sentry/SentrySerializable.h>
#else
#import "SentryDefines.h"
#import "SentrySerializable.h"
#endif

NS_ASSUME_NONNULL_BEGIN

@class SentryStacktrace;

NS_SWIFT_NAME(Thread)
@interface SentryThread : NSObject <SentrySerializable>
SENTRY_NO_INIT

/**
 * Number of the thread
 */
@property(nonatomic, copy) NSNumber *threadId;

/**
 * Name (if available) of the thread
 */
@property(nonatomic, copy) NSString *_Nullable name;

/**
 * SentryStacktrace of the SentryThread
 */
@property(nonatomic, strong) SentryStacktrace *_Nullable stacktrace;

/**
 * Did this thread crash?
 */
@property(nonatomic, copy) NSNumber *_Nullable crashed;

/**
 * Was it the current thread.
 */
@property(nonatomic, copy) NSNumber *_Nullable current;

/**
 * Initializes a SentryThread with its id
 * @param threadId NSNumber
 * @return SentryThread
 */
- (instancetype)initWithThreadId:(NSNumber *)threadId;

@end

NS_ASSUME_NONNULL_END
