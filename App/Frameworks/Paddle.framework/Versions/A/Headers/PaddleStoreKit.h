//
//  PaddleStoreKit.h
//  PaddleIAPDemo
//
//  Created by Louis Harwood on 10/05/2014.
//  Copyright (c) 2014 Paddle. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "PSKReceipt.h"

typedef enum productTypes
{
    PSKConsumableProduct,
    PSKNonConsumableProduct
} ProductType;

@protocol PaddleStoreKitDelegate <NSObject>

- (void)PSKProductPurchased:(nonnull PSKReceipt *)transactionReceipt;
- (void)PSKDidFailWithError:(nonnull NSError *)error;
- (void)PSKDidCancel;

@optional
- (void)PSKProductsReceived:(nonnull NSArray *)products;

@end

@class PSKPurchaseWindowController;
@class PSKStoreWindowController;
@class PSKProductWindowController;
@class PSKProductController;

@interface PaddleStoreKit : NSObject {
    id <PaddleStoreKitDelegate> __unsafe_unretained delegate;
    PSKPurchaseWindowController *purchaseWindow;
    PSKStoreWindowController *storeWindow;
    PSKProductWindowController *productWindow;
    PSKProductController *productController;
}

@property (nonnull, assign) id <PaddleStoreKitDelegate> delegate;
@property (nullable, nonatomic, retain) PSKPurchaseWindowController *purchaseWindow;
@property (nullable, nonatomic, retain) PSKStoreWindowController *storeWindow;
@property (nullable, nonatomic, retain) PSKProductWindowController *productWindow;
@property (nullable, nonatomic, retain) PSKProductController *productController;

+ (nonnull PaddleStoreKit *)sharedInstance;

//Store
- (void)showStoreView;
- (void)showStoreViewForProductType:(ProductType)productType;
- (void)showStoreViewForProductIds:(nonnull NSArray *)productIds;


//Product
- (void)showProduct:(nonnull NSString *)productId;
- (void)allProducts;

//Purchase
- (void)purchaseProduct:(nonnull NSString *)productId;
- (void)recoverPurchases;

//Receipts
- (nullable NSArray *)validReceipts;
- (nullable PSKReceipt *)receiptForProductId:(nonnull NSString *)productId;



@end
