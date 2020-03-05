//
//  NSColor+Pin.h
//  PinConfigurator
//
//  Created by Ben Baker on 2/7/19.
//  Copyright © 2019 Ben Baker. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSColor (Pin)

+ (NSColor *)pinColor:(uint8_t)value;

@end

NS_ASSUME_NONNULL_END
