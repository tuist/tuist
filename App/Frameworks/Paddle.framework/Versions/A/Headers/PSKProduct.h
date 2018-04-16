//
//  PSKProduct.h
//  Paddle
//
//  Created by Louis Harwood on 25/11/2014.
//  Copyright (c) 2014 Paddle. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface PSKProduct : NSObject {
    NSString *productId;
    NSString *name;
    NSString *currency;
    NSString *price;
    NSString *type;
    NSString *productDescription;
    NSString *icon;
}

@property (nonnull, copy) NSString *productId;
@property (nonnull, copy) NSString *name;
@property (nonnull, copy) NSString *currency;
@property (nonnull, copy) NSString *price;
@property (nullable, copy) NSString *type;
@property (nullable, copy) NSString *productDescription;
@property (nullable, copy) NSString *icon;

@end
