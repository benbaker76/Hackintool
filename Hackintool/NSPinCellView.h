//
//  NSPinCell.h
//  PinConfigurator
//
//  Created by Ben Baker on 8/8/18.
//  Copyright © 2018 Ben Baker. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "AudioNode.h"

@interface NSPinCellView : NSTableCellView
{
}

@property (retain) AudioNode *item;
@property BOOL isSelected;

- (void)setItem:(AudioNode *)device isSelected:(BOOL)isSelected;

@end
