//
//  NSPinCell.m
//  PinConfigurator
//
//  Created by Ben Baker on 8/8/18.
//  Copyright © 2018 Ben Baker. All rights reserved.
//

#import "NSPinCellView.h"

@implementation NSPinCellView

@synthesize item = _item;
@synthesize isSelected = _isSelected;

- (id)initWithCoder:(NSCoder *)decoder {
	self = [super initWithCoder:decoder];
	
	if (self) {
	}
	
	return self;
}

- (void)dealloc {
	[_item release];
    _item = nil;
	
	[super dealloc];
}

- (void)setItem:(AudioNode *)device isSelected:(BOOL)isSelected
{
	self.item = device;
	_isSelected = isSelected;
}

- (void)drawRect:(NSRect)dirtyRect {
	if (!_item)
		return;
	
	[[NSGraphicsContext currentContext] saveGraphicsState];
	
    NSRect bounds = self.bounds;
    CGFloat d = 10.0;
    NSRect rect = NSMakeRect(3.0, floor((NSHeight(bounds) - d) * 0.5), d, d);
    NSColor *jackColor = [_item jackColor];
    [jackColor set];
	
	if ([_item hasJack])
	{
		NSBezierPath *bezierPath = [NSBezierPath bezierPathWithOvalInRect:rect];
		[bezierPath setLineWidth:3];
		
		if ([jackColor isEqual:[NSColor whiteColor]] && ![self isSelected])
			[[NSColor lightGrayColor] set];
		
		[bezierPath stroke];
	}
	else
	{
		NSRectFill(rect);
	}
	
	[[NSGraphicsContext currentContext] restoreGraphicsState];
}

@end
