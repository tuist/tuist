//
//  SentryEvent.h
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

@class SentryThread, SentryException, SentryStacktrace, SentryUser, SentryDebugMeta, SentryContext;

NS_SWIFT_NAME(Event)
@interface SentryEvent : NSObject <SentrySerializable>
SENTRY_NO_INIT

/**
 * This will be set by the initializer. Should be an UUID with the "-".
 */
@property(nonatomic, copy) NSString *eventId;

/**
 * Message of the event
 */
@property(nonatomic, copy) NSString *message;

/**
 * NSDate of when the event occured
 */
@property(nonatomic, strong) NSDate *timestamp;

/**
 * SentrySeverity of the event
 */
@property(nonatomic) enum SentrySeverity level;

/**
 * Platform this will be used for symbolicating on the server should be "cocoa"
 */
@property(nonatomic, copy) NSString *platform;

/**
 * Define the logger name
 */
@property(nonatomic, copy) NSString *_Nullable logger;

/**
 * Define the server name
 */
@property(nonatomic, copy) NSString *_Nullable serverName;

/**
 * This property will be filled before the event is sent. Do not change it otherwise you know what you are doing.
 */
@property(nonatomic, copy) NSString *_Nullable releaseName;

/**
 * This property will be filled before the event is sent. Do not change it otherwise you know what you are doing.
 */
@property(nonatomic, copy) NSString *_Nullable dist;

/**
 * The environment used for this event
 */
@property(nonatomic, copy) NSString *_Nullable environment;

/**
 * The current transaction (state) on the crash
 */
@property(nonatomic, copy) NSString *_Nullable transaction;

/**
 * Arbitrary key:value (string:string ) data that will be shown with the event
 */
@property(nonatomic, strong) NSDictionary<NSString *, NSString *> *_Nullable tags;

/**
 * Arbitrary additional information that will be sent with the event
 */
@property(nonatomic, strong) NSDictionary<NSString *, id> *_Nullable extra;

/**
 * Information about the sdk can be something like this. This will be set for you
 * Don't touch it if you not know what you are doing.
 *
 * {
 *  version: "3.3.3",
 *  name: "sentry-cocoa",
 *  integrations: [
 *      "react-native"
 *  ]
 * }
 */
@property(nonatomic, strong) NSDictionary<NSString *, id> *_Nullable sdk;

/**
 * Modules of the event
 */
@property(nonatomic, strong) NSDictionary<NSString *, NSString *> *_Nullable modules;

/**
 * Set the fingerprint of an event to determine the grouping
 */
@property(nonatomic, strong) NSArray<NSString *> *_Nullable fingerprint;

/**
 * Set the SentryUser for the event
 */
@property(nonatomic, strong) SentryUser *_Nullable user;

/**
 * This object contains meta information, will be set automatically overwrite only if you know what you are doing
 */
@property(nonatomic, strong) SentryContext *_Nullable context;

/**
 * Contains SentryThread if an crash occurred of it's an user reported exception
 */
@property(nonatomic, strong) NSArray<SentryThread *> *_Nullable threads;

/**
 * General information about the SentryException, usually there is only one exception in the array
 */
@property(nonatomic, strong) NSArray<SentryException *> *_Nullable exceptions;

/**
 * Separate SentryStacktrace that can be sent with the event, besides threads
 */
@property(nonatomic, strong) SentryStacktrace *_Nullable stacktrace;

/**
 * Containing images loaded during runtime
 */
@property(nonatomic, strong) NSArray<SentryDebugMeta *> *_Nullable debugMeta;

/**
 * This contains all breadcrumbs available at the time when the event occurred/will be sent
 */
@property(nonatomic, strong) NSDictionary<NSString *, id> *_Nullable breadcrumbsSerialized;

/**
 * This property is there for setting main bundle of the app
 */
@property(nonatomic, strong) NSDictionary *infoDict;

/**
 * JSON baggage, that will only be filled if initWithJSON is called.
 */
@property(nonatomic, strong) NSData *json;

/**
 * Init an SentryEvent will set all needed fields by default
 * @param level SentrySeverity
 * @return SentryEvent
 */
- (instancetype)initWithLevel:(enum SentrySeverity)level;

/**
 * Init an SentryEvent with a JSON blob that completly bypasses all other attributes in the event.
 * Instead only the JSON will be sent, this is used in react-native for example where we consider the event
 * from JS as the source of truth.
 * @param json NSData
 * @return SentryEvent
 */
- (instancetype)initWithJSON:(NSData *)json;

@end

NS_ASSUME_NONNULL_END
