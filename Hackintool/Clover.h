//
//  Clover.h
//  Hackintool
//
//  Created by Ben Baker on 1/29/19.
//  Copyright © 2019 Ben Baker. All rights reserved.
//

#ifndef Clover_h
#define Clover_h

#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"
#include <stdio.h>

//
//  Definitions.h
//  CloverPrefs
//
//  Created by Kozlek on 07/06/13.
//  Copyright (c) 2013 Kozlek. All rights reserved.
//

#define kCloverLatestReleaseURL			@"https://api.github.com/repos/CloverHackyColor/CloverBootloader/releases/latest"
#define kCloverFileNamePrefix			@"Clover_"
#define kCloverFileNameSuffix			@".pkg"

#define kCloverLastVersionDownloaded    @"CloverLastVersionDownloaded"
#define kCloverLastDownloadWarned       @"CloverLastDownloadWarned"

#define kCloverLastCheckTimestamp       @"CloverLastCheckTimestamp"
#define kCloverScheduledCheckInterval   @"CloverScheduledCheckInterval"

#define kCloverThemeName                @"Clover.Theme"
#define kCloverLogLineCount             @"Clover.LogLineCount"
#define kCloverLogEveryBoot             @"Clover.LogEveryBoot"
#define kCloverBackupDirOnDestVol       @"Clover.BackupDirOnDestVol"
#define kCloverKeepBackupLimit          @"Clover.KeepBackupLimit"
#define kCloverMountEFI                 @"Clover.MountEFI"
#define kCloverNVRamDisk                @"Clover.NVRamDisk"

@interface Clover : NSObject
{
}

+ (NSArray *)getMountedVolumes;
+ (NSArray *)getPathsCollection;
+ (NSUInteger)getVersion:(NSString *)string;
+ (bool)tryGetVersionInfo:(NSString **)bootedVersion installedVersion:(NSString **)installedVersion;
+ (NSMutableDictionary *)getDevicesPropertiesDictionaryWith:(NSMutableDictionary *)configDictionary;
+ (NSMutableArray *)getKernelAndKextPatchArrayWith:(NSMutableDictionary *)configDictionary kernelAndKextName:(NSString *)kernelAndKextName;
+ (void)applyKextsToPatchWith:(NSMutableDictionary *)destConfigDictionary name:(NSString *)name inDirectory:(NSString *)subpath;
+ (NSMutableArray *)getACPIDSDTPatchesArrayWith:(NSMutableDictionary *)configDictionary;
+ (void)addKernelAndKextPatchWith:(NSMutableDictionary *)configDictionary kernelAndKextName:(NSString *)kernelAndKextName patchDictionary:(NSMutableDictionary *)patchDictionary;
+ (void)addACPIDSDTPatchWith:(NSMutableDictionary *)configDictionary patchDictionary:(NSMutableDictionary *)patchDictionary;
+ (NSMutableDictionary *)createACPIDSDTDictionaryWithFind:(NSString *)find replace:(NSString *)replace;

@end

#endif /* Clover_h */
