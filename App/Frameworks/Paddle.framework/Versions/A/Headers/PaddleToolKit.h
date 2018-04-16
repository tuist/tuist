//
//  PaddleToolKit.h
//  Paddle
//
//  Created by Louis Harwood on 12/06/2015.
//  Copyright (c) 2015 Paddle. All rights reserved.
//

#import <Foundation/Foundation.h>

@class PTKHappiness;
@class PTKRate;
@class PTKFeedback;
@class PTKEmail;
@class PTKThanks;

@protocol PaddleToolkitDelegate <NSObject>
- (void)PTKToolSubmitted:(nonnull NSString *)tool withValue:(nullable id)value;
@end

@interface PaddleToolKit : NSObject {
    PTKHappiness *happinessView;
    PTKRate *rateView;
    PTKFeedback *feedbackView;
    PTKEmail *emailView;
    PTKThanks *thanksView;
}

@property (nullable, assign) id delegate;
@property (nullable, nonatomic, strong) PTKHappiness *happinessView;
@property (nullable, nonatomic, strong) PTKRate *rateView;
@property (nullable, nonatomic, strong) PTKFeedback *feedbackView;
@property (nullable, nonatomic, strong) PTKEmail *emailView;
@property (nullable, nonatomic, strong) PTKThanks *thanksView;

+ (nonnull PaddleToolKit *)sharedInstance;
- (void)presentHappinessViewWithSchedule:(nullable NSString *)schedule message:(nullable NSString *)message __deprecated;
- (void)presentEmailSubscribePromptWithSchedule:(nullable NSString *)schedule message:(nullable NSString *)message;
- (void)sendEmailSubscribe:(nonnull NSString *)email;
- (void)presentFeedbackViewWithSchedule:(nullable NSString *)schedule message:(nullable NSString *)message label:(nullable NSString *)label;
- (void)sendFeedback:(nonnull NSString *)feedback name:(nonnull NSString *)name email:(nonnull NSString *)email label:(nullable NSString *)label;
- (void)presentRatingViewWithSchedule:(nullable NSString *)schedule message:(nullable NSString *)message __deprecated;

- (void)presentAppStoreRatingWithSchedule:(nullable NSString *)schedule appId:(nonnull NSString *)appId __deprecated;

@end
