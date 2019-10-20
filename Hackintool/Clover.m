//
//  Clover.m
//  Hackintool
//
//  Created by Ben Baker on 1/29/19.
//  Copyright © 2019 Ben Baker. All rights reserved.
//

#include "Clover.h"
#include "Config.h"
#include "IORegTools.h"
#include "MiscTools.h"
#include "IORegTools.h"
#include "DiskUtilities.h"
#include "Disk.h"
#include <CoreFoundation/CoreFoundation.h>

#define GetLocalizedString(key) \
[[NSBundle mainBundle] localizedStringForKey:(key) value:@"" table:nil]

@implementation Clover

+ (NSArray *)getMountedVolumes
{
	NSMutableArray *list = [NSMutableArray array];
	NSArray *urls = [[NSFileManager defaultManager] mountedVolumeURLsIncludingResourceValuesForKeys:[NSArray arrayWithObject:NSURLVolumeURLKey] options:0];
	
	for (NSURL *url in urls)
	{
		NSError *error;
		NSURL *volumeURL = nil;
		
		[url getResourceValue:&volumeURL forKey:NSURLVolumeURLKey error:&error];
		
		if (volumeURL)
			[list addObject:volumeURL];
	}
	
	return list;
}

+ (NSArray *)getPathsCollection
{
	NSMutableArray *list = [NSMutableArray array];
	NSArray *urls = [Clover getMountedVolumes];
	
	for (NSURL *volume in urls)
	{
		NSString *path = [[volume path] stringByAppendingPathComponent:@"EFI/CLOVER"];
		
		NSLog(@"%@", path);
		
		if ([[NSFileManager defaultManager] fileExistsAtPath:[path stringByAppendingPathComponent:@"config.plist"]])
		{
			NSString *name = [NSString stringWithFormat:@"Clover on %@", [volume.pathComponents objectAtIndex:volume.pathComponents.count - 1]];

			[list addObject:name];
			NSLog(@"%@", name);
		}
	}
	
	return list;
}

+ (NSUInteger)getVersion:(NSString *)string
{
	if ([string hasPrefix:@"Clover_"])
	{
		NSArray *components = [string componentsSeparatedByString:@"r"];
		
		NSString *revision = [components lastObject];
		
		return [revision intValue];
	}
	
	return 0;
}

+ (bool)tryGetVersionInfo:(NSString **)bootedVersion installedVersion:(NSString **)installedVersion
{
	bool result = false;
	*bootedVersion = @"0";
	*installedVersion = @"0";
	
	CFTypeRef property = nil;
	
	if (getIORegProperty(@"IODeviceTree:/efi/platform", @"clovergui-revision", &property))
	{
		NSData *valueData = (__bridge NSData *)property;
		*bootedVersion = [NSString stringWithFormat:@"%u", *((uint32_t *)valueData.bytes)];
		
		CFRelease(property);
		
		result = true;
	}
	
	// Initialize revision fields
	NSArray *searchPaths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSLocalDomainMask, YES);
	NSString *preferenceFolder = [[searchPaths objectAtIndex:0] stringByAppendingPathComponent:@"Preferences"];
	NSString *cloverInstallerPlist = [[preferenceFolder stringByAppendingPathComponent:@"com.projectosx.clover.installer"] stringByAppendingPathExtension:@"plist"];
	
	if (![[NSFileManager defaultManager] fileExistsAtPath:cloverInstallerPlist])
		return result;
	
	NSDictionary *propertyDictionary = [NSDictionary dictionaryWithContentsOfFile:cloverInstallerPlist];
	NSNumber *cloverVersion = [propertyDictionary objectForKey:@"CloverRevision"];

	if (cloverVersion)
		*installedVersion = [cloverVersion stringValue];
	
	return result;
}

+ (NSMutableDictionary *)getDevicesPropertiesDictionaryWith:(NSMutableDictionary *)configDictionary
{
	NSDictionary *devicesDictionary = [configDictionary objectForKey:@"Devices"];
	NSMutableDictionary *devicesMutableDictionary = (devicesDictionary == nil  ? [NSMutableDictionary dictionary] : [[devicesDictionary mutableCopy] autorelease]);

	[configDictionary setValue:devicesMutableDictionary forKey:@"Devices"];
	
	NSDictionary *devicesPropertiesDictionary = [devicesMutableDictionary objectForKey:@"Properties"];
	NSMutableDictionary *devicesPropertiesMutableDictionary = (devicesPropertiesDictionary == nil ? [NSMutableDictionary dictionary] : [[devicesPropertiesDictionary mutableCopy] autorelease]);
	
	[devicesMutableDictionary setValue:devicesPropertiesMutableDictionary forKey:@"Properties"];
	
	return devicesPropertiesMutableDictionary;
}

+ (NSMutableArray *)getKernelAndKextPatchArrayWith:(NSMutableDictionary *)configDictionary kernelAndKextName:(NSString *)kernelAndKextName
{
	NSDictionary *kernelAndKextPatchesDictionary = [configDictionary objectForKey:@"KernelAndKextPatches"];
	NSMutableDictionary *kernelAndKextPatchesMutableDictionary = (kernelAndKextPatchesDictionary == nil ? [NSMutableDictionary dictionary] : [[kernelAndKextPatchesDictionary mutableCopy] autorelease]);
	
	[configDictionary setValue:kernelAndKextPatchesMutableDictionary forKey:@"KernelAndKextPatches"];
	
	NSArray *kextsToPatchArray = [kernelAndKextPatchesMutableDictionary objectForKey:kernelAndKextName];
	NSMutableArray *kextsToPatchMutableArray = (kextsToPatchArray == nil ? [NSMutableArray array] : [[kextsToPatchArray mutableCopy] autorelease]);
	
	[kernelAndKextPatchesMutableDictionary setValue:kextsToPatchMutableArray forKey:kernelAndKextName];
	
	return kextsToPatchMutableArray;
}

+ (void)applyKextsToPatchWith:(NSMutableDictionary *)destConfigDictionary name:(NSString *)name inDirectory:(NSString *)subpath
{
	NSBundle *mainBundle = [NSBundle mainBundle];
	NSString *filePath = nil;
	
	if (!(filePath = [mainBundle pathForResource:name ofType:@"plist" inDirectory:subpath]))
		return;
	
	NSMutableDictionary *srcConfigDictionary = [NSMutableDictionary dictionaryWithContentsOfFile:filePath];
	NSMutableArray *srcKextsToPatchArray = [Clover getKernelAndKextPatchArrayWith:srcConfigDictionary kernelAndKextName:@"KextsToPatch"];
	
	for (NSMutableDictionary *srcKextsToPatchEntryDictionary in srcKextsToPatchArray)
	{
		NSString *srcName = [srcKextsToPatchEntryDictionary objectForKey:@"Name"];
		NSString *srcComment = [srcKextsToPatchEntryDictionary objectForKey:@"Comment"];
		NSString *srcMatchOS = [srcKextsToPatchEntryDictionary objectForKey:@"MatchOS"];
		
		if (![Clover doesMatchOS:srcMatchOS])
			continue;
		
		bool kextToPatchFound = false;
		
		NSMutableArray *destKextsToPatchArray = [Clover getKernelAndKextPatchArrayWith:destConfigDictionary kernelAndKextName:@"KextsToPatch"];
		
		for (NSMutableDictionary *dstKextsToPatchEntryDictionary in destKextsToPatchArray)
		{
			if (dstKextsToPatchEntryDictionary == nil || ![dstKextsToPatchEntryDictionary isKindOfClass:[NSMutableDictionary class]])
				continue;
			
			NSString *dstName = [dstKextsToPatchEntryDictionary objectForKey:@"Name"];
			NSString *dstComment = [dstKextsToPatchEntryDictionary objectForKey:@"Comment"];
			NSString *dstMatchOS = [dstKextsToPatchEntryDictionary objectForKey:@"MatchOS"];
			
			if ([srcName isEqualToString:dstName] && [srcComment isEqualToString:dstComment] && [srcMatchOS isEqualToString:dstMatchOS])
			{
				kextToPatchFound = true;
				
				break;
			}
		}
		
		if (kextToPatchFound)
			continue;
		
		[destKextsToPatchArray addObject:srcKextsToPatchEntryDictionary];
	}
}

+ (NSMutableArray *)getACPIDSDTPatchesArrayWith:(NSMutableDictionary *)configDictionary
{
	NSDictionary *acpiDictionary = [configDictionary objectForKey:@"ACPI"];
	NSMutableDictionary *acpiMutableDictionary = (acpiDictionary == nil ? [NSMutableDictionary dictionary] : [[acpiDictionary mutableCopy] autorelease]);
	
	[configDictionary setValue:acpiMutableDictionary forKey:@"ACPI"];
	
	NSDictionary *acpiDSDTDictionary = [acpiMutableDictionary objectForKey:@"DSDT"];
	NSDictionary *acpiDSDTMutableDictionary = (acpiDSDTDictionary == nil ? [NSMutableDictionary dictionary] : [[acpiDSDTDictionary mutableCopy] autorelease]);
	
	[acpiMutableDictionary setValue:acpiDSDTMutableDictionary forKey:@"DSDT"];
	
	NSArray *patchesArray = [acpiDSDTMutableDictionary objectForKey:@"Patches"];
	NSMutableArray *patchesMutableArray = (patchesArray == nil ? [NSMutableArray array] : [[patchesArray mutableCopy] autorelease]);
	
	[acpiDSDTMutableDictionary setValue:patchesMutableArray forKey:@"Patches"];
	
	return patchesMutableArray;
}

+ (void)addKernelAndKextPatchWith:(NSMutableDictionary *)configDictionary kernelAndKextName:(NSString *)kernelAndKextName patchDictionary:(NSMutableDictionary *)patchDictionary
{
	// <key>KernelAndKextPatches</key>
	// <dict>
	// 	<key>KernelToPatch</key>
	// 	<array>
	// 		<dict>
	// 			<key>Comment</key>
	// 			<string>Disable panic kext logging on 10.13 debug kernel (credit vit9696)</string>
	// 			<key>MatchOS</key>
	// 			<string>10.13.x</string>
	// 			<key>Find</key>
	// 			<data>sABMi1Xw</data>
	// 			<key>Replace</key>
	// 			<data>SIPEQF3D</data>
	// 		</dict>
	// 	</array>
	// 	<key>KextsToPatch</key>
	// 	<array>
	// 		<dict>
	// 			<key>Comment</key>
	// 			<string>change F%uT%04x to F%uTxxxx in AppleBacklightInjector.kext (credit RehabMan)</string>
	// 			<key>Name</key>
	// 			<string>com.apple.driver.AppleBacklight</string>
	// 			<key>Find</key>
	// 			<data>RiV1VCUwNHgA</data>
	// 			<key>Replace</key>
	// 			<data>RiV1VHh4eHgA</data>
	// 		</dict>
	// 	</array>
	// </dict>
	
	NSData *findData = [patchDictionary objectForKey:@"Find"];
	NSData *replaceData = [patchDictionary objectForKey:@"Replace"];
	NSString *name = [patchDictionary objectForKey:@"Name"];
	NSString *matchOS = [patchDictionary objectForKey:@"MatchOS"];
	
	NSMutableArray *patchesArray = [Clover getKernelAndKextPatchArrayWith:configDictionary kernelAndKextName:kernelAndKextName];
	
	for (NSMutableDictionary *existingPatchDictionary in patchesArray)
	{
		NSData *existingFindData = [existingPatchDictionary objectForKey:@"Find"];
		NSData *existingReplaceData = [existingPatchDictionary objectForKey:@"Replace"];
		NSString *existingName = [existingPatchDictionary objectForKey:@"Name"];
		NSString *existingMatchOS = [existingPatchDictionary objectForKey:@"MatchOS"];
		
		if ([existingFindData isEqual:findData] && [existingReplaceData isEqualToData:replaceData] && [name isEqualToString:existingName] && [matchOS isEqualToString:existingMatchOS])
		{
			[existingPatchDictionary setValue:@NO forKey:@"Disabled"];
			
			return;
		}
	}
	
	[patchesArray addObject:patchDictionary];
}

+ (void)addACPIDSDTPatchWith:(NSMutableDictionary *)configDictionary patchDictionary:(NSMutableDictionary *)patchDictionary
{
	// <key>ACPI</key>
	// <dict>
	// 	<key>DSDT</key>
	// 	<dict>
	// 		<key>Patches</key>
	// 		<array>
	// 			<dict>
	// 				<key>Comment</key>
	// 				<string>Rename HDAS to HDEF</string>
	// 				<key>Disabled</key>
	// 				<false/>
	// 				<key>Find</key>
	// 				<data>
	// 				SERBUw==
	// 				</data>
	// 				<key>Replace</key>
	// 				<data>
	// 				SERFRg==
	// 				</data>
	// 			</dict>
	// 		<array>
	// 	</dict>
	// </dict>
	
	NSData *findData = [patchDictionary objectForKey:@"Find"];
	NSData *replaceData = [patchDictionary objectForKey:@"Replace"];

	NSMutableArray *patchesArray = [Clover getACPIDSDTPatchesArrayWith:configDictionary];

	for (NSMutableDictionary *existingPatchDictionary in patchesArray)
	{
		NSData *existingFindData = [existingPatchDictionary objectForKey:@"Find"];
		NSData *existingReplaceData = [existingPatchDictionary objectForKey:@"Replace"];
		
		if ([existingFindData isEqual:findData] && [existingReplaceData isEqualToData:replaceData])
		{
			[existingPatchDictionary setValue:@NO forKey:@"Disabled"];
			
			return;
		}
	}

	[patchesArray addObject:patchDictionary];
}

+ (NSMutableDictionary *)createACPIDSDTDictionaryWithFind:(NSString *)find replace:(NSString *)replace
{
	NSMutableDictionary *acpiDSDTDictionary = [NSMutableDictionary dictionary];
	
	NSData *findData = [find dataUsingEncoding:NSUTF8StringEncoding];
	NSData *replaceData = [replace dataUsingEncoding:NSUTF8StringEncoding];
	
	[acpiDSDTDictionary setValue:[NSString stringWithFormat:@"Rename %@ to %@", find, replace] forKey:@"Comment"];
	[acpiDSDTDictionary setValue:@NO forKey:@"Disabled"];
	[acpiDSDTDictionary setValue:findData forKey:@"Find"];
	[acpiDSDTDictionary setValue:replaceData forKey:@"Replace"];
	
	return acpiDSDTDictionary;
}

+ (BOOL)doesMatchOS:(NSString *)matchOS
{
	if (matchOS == nil)
		return YES;
	
	NSOperatingSystemVersion osVersion = [[NSProcessInfo processInfo] operatingSystemVersion];
	
	NSString *majorMinorPatchVersion = [NSString stringWithFormat:@"%ld.%ld.%ld", osVersion.majorVersion, osVersion.minorVersion, osVersion.patchVersion];
	NSString *majorMinorVersion = [NSString stringWithFormat:@"%ld.%ld.x", osVersion.majorVersion, osVersion.minorVersion];
	NSString *majorVersion = [NSString stringWithFormat:@"%ld.x.x", osVersion.majorVersion];
	
	if ([matchOS containsString:majorMinorPatchVersion])
		return YES;
	
	if ([matchOS containsString:majorMinorVersion])
		return YES;
	
	if ([matchOS containsString:majorVersion])
		return YES;
	
	return NO;
}

@end
