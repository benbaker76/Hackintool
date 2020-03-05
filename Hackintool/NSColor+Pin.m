//
//  NSColor+Pin.m
//  PinConfigurator
//
//  Created by Ben Baker on 2/7/19.
//  Copyright © 2019 Ben Baker. All rights reserved.
//

#import "NSColor+Pin.h"

@implementation NSColor (Pin)

+ (NSColor *)pinColor:(uint8_t)value
{
	NSArray *colorArray = @[[NSColor blackColor], [NSColor blackColor], [NSColor grayColor], [NSColor blueColor], [NSColor greenColor], [NSColor redColor], [NSColor orangeColor], [NSColor yellowColor], [NSColor purpleColor], [NSColor magentaColor], [NSColor blackColor], [NSColor blackColor], [NSColor blackColor], [NSColor blackColor], [NSColor whiteColor], [NSColor blackColor]];

	return colorArray[value & 0xF];
}

@end
