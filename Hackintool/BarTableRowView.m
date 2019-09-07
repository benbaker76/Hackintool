//
//  BarTableRowView.m
//  Hackintool
//
//  Created by Ben Baker on 3/23/19.
//  Copyright © 2019 Ben Baker. All rights reserved.
//

#import "BarTableRowView.h"

@implementation BarTableRowView

-(id) initWithPercent:(double)percent column:(NSInteger)column color:(NSColor *)color inset:(NSSize)inset radius:(NSInteger)radius stroke:(Boolean)stroke
{
	if (self = [super init])
	{
		self.percent = percent;
		self.column = column;
		self.color = color;
		self.inset = inset;
		self.radius = radius;
		self.stroke = stroke;
	}
	
	return self;
}

- (void)dealloc
{
	[_color release];
	
	[super dealloc];
}

- (void)drawBackgroundInRect:(NSRect)dirtyRect
{
	[super drawBackgroundInRect:dirtyRect];
	
	NSString *osxMode = [[NSUserDefaults standardUserDefaults] stringForKey:@"AppleInterfaceStyle"];
	
	NSView *columnView = [self viewAtColumn:self.column];
	NSRect barRect = NSInsetRect(columnView.frame, self.inset.width, self.inset.height);
	if ([osxMode isEqualToString:@"Dark"])
		[[NSColor colorWithCalibratedRed:0.0 green:0.0 blue:0.0 alpha:self.color.alphaComponent] setFill];
	else
		[[NSColor colorWithCalibratedRed:1.0 green:1.0 blue:1.0 alpha:self.color.alphaComponent] setFill];
	NSBezierPath *backProgressPath = [NSBezierPath bezierPathWithRoundedRect:barRect xRadius:self.radius yRadius:self.radius];
	[backProgressPath fill];
	
	CGFloat barWidth = floor(barRect.size.width * self.percent);
	barRect.size.width = barWidth;
	if (self.stroke)
		[self.color setStroke];
	[self.color setFill];
	NSBezierPath *roundedProgressPath = [NSBezierPath bezierPathWithRoundedRect:barRect xRadius:self.radius yRadius:self.radius];
	[roundedProgressPath fill];
	if (self.stroke)
		[roundedProgressPath stroke];
}

@end
