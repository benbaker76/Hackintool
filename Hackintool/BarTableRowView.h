//
//  BarTableRowView.h
//  Hackintool
//
//  Created by Ben Baker on 3/23/19.
//  Copyright © 2019 Ben Baker. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface BarTableRowView : NSTableRowView
{
}

-(id) initWithPercent:(double)percent column:(NSInteger)column color:(NSColor *)color inset:(NSSize)inset radius:(NSInteger)radius stroke:(Boolean)stroke;

@property double percent;
@property NSInteger column;
@property (nonatomic, retain) NSColor *color;
@property NSSize inset;
@property NSInteger radius;
@property Boolean stroke;

@end
