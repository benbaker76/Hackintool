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

#define kCloverLatestInstallerURL       @"http://sourceforge.net/projects/cloverefiboot/files/latest/download"

#define kCloverLastVersionDownloaded    @"LastVersionDownloaded"
#define kCloverLastDownloadWarned       @"LastDownloadWarned"

#define kCloverLastCheckTimestamp       @"LastCheckTimestamp"
#define kCloverScheduledCheckInterval   @"ScheduledCheckInterval"

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
+ (bool)tryGetVersionInfo:(NSString **)bootedRevision installedRevision:(NSString **)installedRevision;
+ (NSMutableDictionary *)getDevicesPropertiesDictionaryWith:(NSMutableDictionary *)configDictionary;
+ (NSMutableArray *)getKernelAndKextPatchArrayWith:(NSMutableDictionary *)configDictionary kernelAndKextName:(NSString *)kernelAndKextName;
+ (void)applyKextsToPatchWith:(NSMutableDictionary *)destConfigDictionary name:(NSString *)name inDirectory:(NSString *)subpath;
+ (NSMutableArray *)getACPIDSDTPatchesArrayWith:(NSMutableDictionary *)configDictionary;
+ (void)addKernelAndKextPatchWith:(NSMutableDictionary *)configDictionary kernelAndKextName:(NSString *)kernelAndKextName patchDictionary:(NSMutableDictionary *)patchDictionary;
+ (void)addACPIDSDTPatchWith:(NSMutableDictionary *)configDictionary patchDictionary:(NSMutableDictionary *)patchDictionary;
+ (NSMutableDictionary *)createACPIDSDTDictionaryWithFind:(NSString *)find replace:(NSString *)replace;

@end

#endif /* Clover_h */
