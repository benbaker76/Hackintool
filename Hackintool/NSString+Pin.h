//
//  NSString+Pin.h
//  PinConfigurator
//
//  Created by Ben Baker on 2/7/19.
//  Copyright © 2019 Ben Baker. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSString (Pin)

+ (NSString *)pinDirection:(uint8_t)value;
+ (NSString *)pinColor:(uint8_t)value;
+ (NSString *)pinMisc:(uint8_t)value;
+ (NSString *)pinDefaultDevice:(uint8_t)value;
+ (NSString *)pinConnector:(uint8_t)value;
+ (NSString *)pinPort:(uint8_t)value;
+ (NSString *)pinGrossLocation:(uint8_t)value;
+ (NSString *)pinLocation:(uint8_t)grossLocation geometricLocation:(uint8_t)geometricLocation;
+ (NSString *)pinEAPD:(uint8_t)value;;
+ (NSString *)pinConfigDescription:(uint8_t *)value;
+ (NSString *)pinDefaultDescription:(uint8_t *)value;

@end

NS_ASSUME_NONNULL_END
