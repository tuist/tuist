//
//  PADProduct.h
//  PaddleSample
//
//  Created by Louis Harwood on 27/04/2013.
//  Copyright (c) 2014 Avalore. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol PADProductDelegate <NSObject>

- (void)productInfoReceived;
- (void)productInfoError:(nonnull NSString *)errorCode withMessage:(nullable NSString *)errorMessage;

@end

@interface PADProduct : NSObject <NSURLConnectionDelegate> {
    NSMutableData *receivedData;
    NSString *aProductId;
}

@property (nullable, assign) id delegate;
@property (nullable, copy) NSString *aProductId;

- (void)productInfo:(nonnull NSString *)productId apiKey:(nonnull NSString *)apiKey vendorId:(nonnull NSString *)vendorId;

@end
