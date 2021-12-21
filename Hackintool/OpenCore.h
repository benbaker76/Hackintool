//
//  OpenCore.h
//  Hackintool
//
//  Created by Ben Baker on 1/29/19.
//  Copyright © 2019 Ben Baker. All rights reserved.
//

#ifndef OpenCore_h
#define OpenCore_h

#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"
#include <stdio.h>

#define kOpenCoreProjectURL				@"https://github.com/acidanthera/OpenCorePkg"
#define kOpenCoreProjectFileURL			@"https://github.com/acidanthera/OpenCorePkg/raw/master/OpenCorePkg.xcodeproj"
#define kOpenCoreLatestReleaseURL		@"https://api.github.com/repos/acidanthera/OpenCorePkg/releases/latest"
#define kOpenCoreFileNamePrefix			@"OpenCore-"
#define kOpenCoreFileNameSuffix			@"RELEASE.zip"

#define kOpenCoreLastVersionDownloaded	@"OpenCoreLastVersionDownloaded"
#define kOpenCoreLastDownloadWarned		@"OpenCoreLastDownloadWarned"

#define kOpenCoreLastCheckTimestamp		@"OpenCoreLastCheckTimestamp"
#define kOpenCoreScheduledCheckInterval	@"OpenCoreScheduledCheckInterval"

@interface OpenCore : NSObject
{
}

+ (NSArray *)getMountedVolumes;
+ (NSArray *)getPathsCollection;
+ (NSUInteger)getVersion:(NSString *)string;
+ (bool)tryGetVersionInfo:(NSString **)bootedVersion;
+ (NSMutableDictionary *)getDevicePropertiesDictionaryWith:(NSMutableDictionary *)configDictionary typeName:(NSString *)typeName;
+ (NSMutableArray *)getKernelPatchArrayWith:(NSMutableDictionary *)configDictionary typeName:(NSString *)typeName;
+ (void)applyKextsToPatchWith:(NSMutableDictionary *)destConfigDictionary name:(NSString *)name inDirectory:(NSString *)subpath;
+ (NSMutableArray *)getACPIPatchArrayWith:(NSMutableDictionary *)configDictionary;
+ (void)addKernelPatchWith:(NSMutableDictionary *)configDictionary typeName:(NSString *)typeName patchDictionary:(NSMutableDictionary *)patchDictionary;
+ (void)addACPIDSDTPatchWith:(NSMutableDictionary *)configDictionary patchDictionary:(NSMutableDictionary *)patchDictionary;
+ (NSMutableDictionary *)createACPIDSDTDictionaryWithFind:(NSString *)find replace:(NSString *)replace;

@end

#endif /* OpenCore_h */
