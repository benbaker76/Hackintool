//
//  OpenCore.m
//  Hackintool
//
//  Created by Ben Baker on 1/29/19.
//  Copyright © 2019 Ben Baker. All rights reserved.
//

#include "OpenCore.h"
#include "Config.h"
#include "Clover.h"
#include "IORegTools.h"
#include "MiscTools.h"
#include "IORegTools.h"
#include "DiskUtilities.h"
#include "Disk.h"
#include <CoreFoundation/CoreFoundation.h>

#define GetLocalizedString(key) \
[[NSBundle mainBundle] localizedStringForKey:(key) value:@"" table:nil]

@implementation OpenCore

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
	NSArray *urls = [OpenCore getMountedVolumes];
	
	for (NSURL *volume in urls)
	{
		NSString *path = [[volume path] stringByAppendingPathComponent:@"EFI/OC"];
		
		NSLog(@"%@", path);
		
		if ([[NSFileManager defaultManager] fileExistsAtPath:[path stringByAppendingPathComponent:@"config.plist"]])
		{
			NSString *name = [NSString stringWithFormat:@"OpenCore on %@", [volume.pathComponents objectAtIndex:volume.pathComponents.count - 1]];

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

+ (bool)tryGetVersionInfo:(NSString **)bootedVersion
{
	bool result = false;
	*bootedVersion = @"0.0.0";
	
	CFTypeRef property = nil;
	
	// NPT-001-2019-05-03
	if (!getIORegProperty(@"IODeviceTree:/options", @"4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:opencore-version", &property))
		return false;
	
	NSData *valueData = (__bridge NSData *)property;
	
	if (valueData.length >= 18)
	{
		NSString *valueString = [[[NSString alloc] initWithData:valueData encoding:NSASCIIStringEncoding] autorelease];
		
		NSString *openCoreTarget = [valueString substringWithRange:NSMakeRange(0, 3)];
		NSString *openCoreVersion = [valueString substringWithRange:NSMakeRange(4, 3)];
		NSString *openCoreYear = [valueString substringWithRange:NSMakeRange(8, 4)];
		NSString *openCoreMonth = [valueString substringWithRange:NSMakeRange(13, 2)];
		NSString *openCoreDay = [valueString substringWithRange:NSMakeRange(16, 2)];
		
		*bootedVersion = [NSString stringWithFormat:@"%@.%@.%@", [openCoreVersion substringWithRange:NSMakeRange(0, 1)], [openCoreVersion substringWithRange:NSMakeRange(1, 1)], [openCoreVersion substringWithRange:NSMakeRange(2, 1)]];
		
		if ([openCoreTarget isEqualToString:@"UNK"] &&
			[openCoreVersion isEqualToString:@"000"] &&
			[openCoreYear isEqualToString:@"0000"] &&
			[openCoreMonth isEqualToString:@"00"] &&
			[openCoreDay isEqualToString:@"00"])
		{
			// Clover injects UNK-000-0000-00-00
			result = false;
		}
		else
		{
			result = true;
		}
	}
		
	CFRelease(property);
	
	return result;
}

+ (NSMutableDictionary *)getDevicePropertiesDictionaryWith:(NSMutableDictionary *)configDictionary typeName:(NSString *)typeName
{
	NSDictionary *devicePropertiesDictionary = [configDictionary objectForKey:@"DeviceProperties"];
	NSMutableDictionary *devicePropertiesMutableDictionary = (devicePropertiesDictionary == nil  ? [NSMutableDictionary dictionary] : [[devicePropertiesDictionary mutableCopy] autorelease]);
	
	[configDictionary setValue:devicePropertiesMutableDictionary forKey:@"DeviceProperties"];
	
	NSDictionary *addDictionary = [devicePropertiesMutableDictionary objectForKey:typeName];
	NSMutableDictionary *addMutableDictionary = (addDictionary == nil ? [NSMutableDictionary dictionary] : [[addDictionary mutableCopy] autorelease]);
	
	[devicePropertiesMutableDictionary setValue:addMutableDictionary forKey:typeName];
	
	return addMutableDictionary;
}

+ (NSMutableArray *)getKernelPatchArrayWith:(NSMutableDictionary *)configDictionary typeName:(NSString *)typeName
{
	NSDictionary *kernelDictionary = [configDictionary objectForKey:@"Kernel"];
	NSMutableDictionary *kernelMutableDictionary = (kernelDictionary == nil ? [NSMutableDictionary dictionary] : [[kernelDictionary mutableCopy] autorelease]);
	
	[configDictionary setValue:kernelMutableDictionary forKey:@"Kernel"];
	
	NSArray *patchArray = [kernelMutableDictionary objectForKey:typeName];
	NSMutableArray *patchMutableArray = (patchArray == nil ? [NSMutableArray array] : [[patchArray mutableCopy] autorelease]);
	
	[kernelMutableDictionary setValue:patchMutableArray forKey:typeName];
	
	return patchMutableArray;
}

+ (void)applyKextsToPatchWith:(NSMutableDictionary *)destConfigDictionary name:(NSString *)name inDirectory:(NSString *)subpath
{
	NSBundle *mainBundle = [NSBundle mainBundle];
	NSString *filePath = nil;
	
	if (!(filePath = [mainBundle pathForResource:name ofType:@"plist" inDirectory:subpath]))
		return;
	
	NSMutableDictionary *srcConfigDictionary = [NSMutableDictionary dictionaryWithContentsOfFile:filePath];
	NSMutableArray *srcKextsToPatchArray = [Clover getKernelAndKextPatchArrayWith:srcConfigDictionary kernelAndKextName:@"KextsToPatch"];
	//NSMutableArray *srcKextsToPatchArray = [OpenCore getKernelPatchArrayWith:srcConfigDictionary typeName:@"Add"];
	
	for (NSMutableDictionary *srcKextsToPatchEntryDictionary in srcKextsToPatchArray)
	{
		NSString *srcName = [srcKextsToPatchEntryDictionary objectForKey:@"Name"];
		NSString *srcComment = [srcKextsToPatchEntryDictionary objectForKey:@"Comment"];
		NSString *srcMatchOS = [srcKextsToPatchEntryDictionary objectForKey:@"MatchOS"];
		
		if (![Config doesMatchOS:srcMatchOS])
			continue;
		
		bool kextToPatchFound = false;
		
		NSMutableArray *destKextsToPatchArray = [OpenCore getKernelPatchArrayWith:destConfigDictionary typeName:@"Patch"];
		
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

+ (NSMutableArray *)getACPIPatchArrayWith:(NSMutableDictionary *)configDictionary
{
	NSDictionary *acpiDictionary = [configDictionary objectForKey:@"ACPI"];
	NSMutableDictionary *acpiMutableDictionary = (acpiDictionary == nil ? [NSMutableDictionary dictionary] : [[acpiDictionary mutableCopy] autorelease]);
	
	[configDictionary setValue:acpiMutableDictionary forKey:@"ACPI"];
	
	NSArray *patchArray = [acpiMutableDictionary objectForKey:@"Patch"];
	NSMutableArray *patchMutableArray = (patchArray == nil ? [NSMutableArray array] : [[patchArray mutableCopy] autorelease]);
	
	[acpiMutableDictionary setValue:patchMutableArray forKey:@"Patch"];
	
	return patchMutableArray;
}

+ (void)addKernelPatchWith:(NSMutableDictionary *)configDictionary typeName:(NSString *)typeName patchDictionary:(NSMutableDictionary *)patchDictionary
{
	NSString *identifier = [patchDictionary objectForKey:@"Identifier"];
	NSData *findData = [patchDictionary objectForKey:@"Find"];
	NSData *replaceData = [patchDictionary objectForKey:@"Replace"];
	NSString *matchKernel = [patchDictionary objectForKey:@"MatchKernel"];
	
	NSMutableArray *patchesArray = [OpenCore getKernelPatchArrayWith:configDictionary typeName:typeName];
	
	for (NSMutableDictionary *existingPatchDictionary in patchesArray)
	{
		NSData *existingFindData = [existingPatchDictionary objectForKey:@"Find"];
		NSData *existingReplaceData = [existingPatchDictionary objectForKey:@"Replace"];
		NSString *existingIdentifier = [existingPatchDictionary objectForKey:@"Identifier"];
		NSString *existingMatchKernel = [existingPatchDictionary objectForKey:@"MatchKernel"];
		
		if ([existingFindData isEqual:findData] && [existingReplaceData isEqualToData:replaceData] && [identifier isEqualToString:existingIdentifier] && [matchKernel isEqualToString:existingMatchKernel])
		{
			[existingPatchDictionary setValue:@YES forKey:@"Enabled"];
			
			return;
		}
	}
	
	[patchesArray addObject:patchDictionary];
}

+ (void)addACPIDSDTPatchWith:(NSMutableDictionary *)configDictionary patchDictionary:(NSMutableDictionary *)patchDictionary
{
	NSData *findData = [patchDictionary objectForKey:@"Find"];
	NSData *replaceData = [patchDictionary objectForKey:@"Replace"];

	NSMutableArray *patchesArray = [OpenCore getACPIPatchArrayWith:configDictionary];

	for (NSMutableDictionary *existingPatchDictionary in patchesArray)
	{
		NSData *existingFindData = [existingPatchDictionary objectForKey:@"Find"];
		NSData *existingReplaceData = [existingPatchDictionary objectForKey:@"Replace"];
		
		if ([existingFindData isEqual:findData] && [existingReplaceData isEqualToData:replaceData])
		{
			[existingPatchDictionary setValue:@YES forKey:@"Enabled"];
			
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
	NSData *dsdtData = [@"DSDT" dataUsingEncoding:NSUTF8StringEncoding];
	
	[acpiDSDTDictionary setValue:[NSString stringWithFormat:@"Rename %@ to %@", find, replace] forKey:@"Comment"];
	[acpiDSDTDictionary setValue:@YES forKey:@"Enabled"];
	[acpiDSDTDictionary setValue:findData forKey:@"Find"];
	[acpiDSDTDictionary setValue:replaceData forKey:@"Replace"];
	[acpiDSDTDictionary setValue:[NSData data] forKey:@"OemTableId"];
	[acpiDSDTDictionary setValue:[NSData data] forKey:@"Mask"];
	[acpiDSDTDictionary setValue:[NSData data] forKey:@"ReplaceMask"];
	[acpiDSDTDictionary setValue:@(0) forKey:@"Count"];
	[acpiDSDTDictionary setValue:@(0) forKey:@"Limit"];
	[acpiDSDTDictionary setValue:@(0) forKey:@"Skip"];
	[acpiDSDTDictionary setValue:@(0) forKey:@"TableLength"];
	[acpiDSDTDictionary setValue:dsdtData forKey:@"TableSignature"];
	
	return acpiDSDTDictionary;
}

@end
