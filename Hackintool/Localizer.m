//
//  Localizer.m
//  Hackintool
//
//  Created by kozlek on 20.03.13.
//  Copyright (c) 2013 kozlek. All rights reserved.
//

//  The MIT License (MIT)
//
//  Copyright (c) 2013 Natan Zalkin <natan.zalkin@me.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE

#import "Localizer.h"

#define GetLocalizedString(key) \
[_bundle localizedStringForKey:(key) value:@"" table:nil]

@implementation Localizer

+ (Localizer *)localizerWithBundle:(NSBundle *)bundle
{
    Localizer *localizer = [[Localizer alloc] initWithBundle:bundle];
	[localizer autorelease];
    
    return localizer;
}

+(void)localizeView:(id)view
{
    Localizer *localizer = [Localizer localizerWithBundle:[NSBundle mainBundle]];
    [localizer localizeView:view];
}

+(void)localizeView:(id)view withBunde:(NSBundle *)bundle
{
    Localizer *localizer = [Localizer localizerWithBundle:bundle];
    [localizer localizeView:view];
}

-(id)init
{
    self = [super init];
    
    if (self) {
        _bundle = [NSBundle mainBundle];
    }
    
    return self;
}

-(Localizer *)initWithBundle:(NSBundle *)bundle
{
    self = [super init];
    
    if (self) {
        _bundle = bundle;
    }
    
    return self;
}

- (void)localizeView:(id)view
{
    if (!view) {
        return;
    }
	
	if ([view respondsToSelector:@selector(setToolTip:)])
	{
		if ([view toolTip] == nil && ![[view identifier] hasPrefix:@"_NS"])
		{
			NSString *toolTipString = [NSString stringWithFormat:@"TT_%@", [view identifier]];
			NSString *localizedToolTipString = GetLocalizedString(toolTipString);
			
			if (![toolTipString isEqualToString:localizedToolTipString])
				[view setToolTip:localizedToolTipString];
		}
	}
    
    if ([view isKindOfClass:[NSWindow class]]) {
        [self localizeView:[view contentView]];
    }
    else if ([view isKindOfClass:[NSTextField class]]) {
        NSTextField *textField = (NSTextField *)view;
        
        NSString *title = [textField stringValue];
        
        [textField setStringValue:GetLocalizedString(title)];
    }
    else if ([view isKindOfClass:[NSButton class]]) {
        NSButton *button = (NSButton *)view;
        NSString *title = [button title];
        
        [button setTitle:GetLocalizedString(title)];
        [button setAlternateTitle:GetLocalizedString([button alternateTitle])];
        
        [self localizeView:button.menu];
    }
    else if ([view isKindOfClass:[NSMatrix class]]) {
        NSMatrix *matrix = (NSMatrix *)view;
        
        NSUInteger row, column;
        
        for (row = 0 ; row < [matrix numberOfRows]; row++) {
            for (column = 0; column < [matrix numberOfColumns] ; column++) {
                NSButtonCell* cell = [matrix cellAtRow:row column:column];
                
                NSString *title = [cell title];
                
                [cell setTitle:GetLocalizedString(title)];
            }
        }
    }
	else if ([view isKindOfClass:[NSTableView class]]) {
		NSTableView *table = (NSTableView *)view;
		
		NSUInteger column;
		
		for (column = 0; column < [table numberOfColumns] ; column++) {
			NSTableColumn *cell = table.tableColumns[column];
			
			NSString *title = [cell title];
			
			[cell setTitle:GetLocalizedString(title)];
		}
	}
    else if ([view isKindOfClass:[NSMenu class]]) {
        NSMenu *menu = (NSMenu *)view;
        
        [menu setTitle:GetLocalizedString([menu title])];
        
        for (id subItem in [menu itemArray]) {
            if ([subItem isKindOfClass:[NSMenuItem class]]) {
                NSMenuItem* menuItem = subItem;
                
                [menuItem setTitle:GetLocalizedString([menuItem title])];
                
                if ([menuItem hasSubmenu])
                    [self localizeView:[menuItem submenu]];
            }
        }
    }
    else if ([view isKindOfClass:[NSTabView class]]) {
        for (NSTabViewItem *item in [(NSTabView *)view tabViewItems]) {
            [item setLabel:GetLocalizedString([item label])];
            [self localizeView:[item view]];
        }
    }
    else if ([view isKindOfClass:[NSToolbar class]]) {
        for (NSToolbarItem *item in [(NSToolbar *)view items]) {
            [item setLabel:GetLocalizedString([item label])];
            [self localizeView:[item view]];
        }
    }
    else if ([view isKindOfClass:[NSBox class]]) {
		NSString *title = [(id)view title];
        [view setTitle:GetLocalizedString(title)];
        for(NSView *subView in [view subviews]) {
            [self localizeView:subView];
        }
    }
    
    // Must be at the end to allow other checks to pass because almost all controls are derived from NSView
    else if ([view isKindOfClass:[NSView class]] ) {
        for(NSView *subView in [view subviews]) {
            [self localizeView:subView];
        }
    }
    else {
        if ([view respondsToSelector:@selector(setTitle:)]) {
            NSString *title = [(id)view title];
            [view setTitle:GetLocalizedString(title)];
        }
        else if ([view respondsToSelector:@selector(setStringValue:)]) {
            NSString *title = [(id)view stringValue];
            [view setStringValue:GetLocalizedString(title)];
        }
        
        if ([view respondsToSelector:@selector(setAlternateTitle:)]) {
            NSString *title = [(id)view alternateTitle];
            [view setAlternateTitle:GetLocalizedString(title)];
        }
    }
    
    if ([view respondsToSelector:@selector(setToolTip:)]) {
        NSString *tooltip = [view toolTip];
        [view setToolTip:GetLocalizedString(tooltip)];
    }
}


@end
