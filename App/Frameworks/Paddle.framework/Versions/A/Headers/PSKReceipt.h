//
//  PSKReceipt.h
//  PaddleIAPDemo
//
//  Created by Louis Harwood on 15/05/2014.
//  Copyright (c) 2014 Louis Harwood. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol PSKReceiptDelegate <NSObject>

- (void)verificationSuccess:(nonnull id)receipt;
- (void)verificationFail:(nonnull id)receipt;

@end

@interface PSKReceipt : NSObject {
    NSMutableData *receivedData;
    NSString *productId;
    NSString *token;
    NSString *userId;
    NSString *receiptId;
    NSDate *lastActivated;
    NSString *userEmail;
}

@property (nullable, assign) id <PSKReceiptDelegate> delegate;
@property (nullable, nonatomic, retain) NSMutableData *receivedData;

@property (nonnull, copy) NSString *productId;
@property (nullable, copy) NSString *token;
@property (nullable, copy) NSString *userId;
@property (nonnull, copy) NSString *receiptId;
@property (nullable, nonatomic, retain) NSDate *lastActivated;
@property (nullable, copy) NSString *userEmail;

- (void)verify;
- (void)store;

@end
