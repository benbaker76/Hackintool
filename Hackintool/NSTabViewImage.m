//
//  NSTabViewImage.m
//  Hackintool
//
//  Created by Ben Baker on 8/8/18.
//  Copyright © 2018 Ben Baker. All rights reserved.
//

#import "NSTabViewImage.h"

#define GetLocalizedString(key) \
[[NSBundle mainBundle] localizedStringForKey:(key) value:@"" table:nil]

@implementation NSTabViewImage

- (id)initWithCoder:(NSCoder *)decoder {
	self = [super initWithCoder:decoder];
	
	if (self) {
		[self setToolTip:GetLocalizedString([self label])];
		[self setLabel:@" "];
	}
		
	return self;
}

- (NSSize)sizeOfLabel:(BOOL)computeMin {
	return NSMakeSize(16, 18);
}

- (void)drawLabel:(BOOL)shouldTruncateLabel inRect:(NSRect)tabRect {
	NSImage *image = [self image];
	
	NSRect destRect = NSMakeRect(tabRect.origin.x, tabRect.origin.y + 2, 16, 16);
	
	[[NSGraphicsContext currentContext] saveGraphicsState];
	NSAffineTransform *affineTransform = [NSAffineTransform transform];
	[affineTransform translateXBy:NSMaxX(destRect) yBy:NSMinY(destRect)];
	[affineTransform scaleXBy:1.0 yBy:-1.0];
	[affineTransform concat];
	
	if(image) {
		[image drawInRect:NSMakeRect(-NSWidth(destRect), -NSHeight(destRect), 16, 16) fromRect:NSZeroRect
		 		operation:NSCompositeSourceOver
				 fraction:1.0f];
	}
	
	[[NSGraphicsContext currentContext] restoreGraphicsState];
	[super drawLabel:shouldTruncateLabel inRect:tabRect];
}

@end
