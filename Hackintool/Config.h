//
//  Config.h
//  Hackintool
//
//  Created by Ben Baker on 1/29/19.
//  Copyright © 2019 Ben Baker. All rights reserved.
//

#ifndef Config_h
#define Config_h

#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"
#include <stdio.h>

@interface Config : NSObject
{
}

+ (bool)mountBootEFI:(AppDelegate *)appDelegate efiVolumeURL:(NSURL **)efiVolumeURL;
+ (bool)openConfig:(AppDelegate *)appDelegate configDictionary:(NSMutableDictionary **)configDictionary configPath:(NSString **)configPath;
+ (BOOL)doesMatchOS:(NSString *)matchOS;

@end

#endif /* Config_h */
