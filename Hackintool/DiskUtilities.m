//
//  DiskUtilities.m
//  Hackintool
//
//  Created by Ben Baker on 1/26/19.
//  Copyright © 2019 Ben Baker. All rights reserved.
//

#include "DiskUtilities.h"
#include "Disk.h"
#include "Authorization.h"
#include "MiscTools.h"
#include "IORegTools.h"
#include <sys/attr.h>
#include <sys/dirent.h>
#include <sys/mount.h>
#include <sys/wait.h>
#include <stdio.h>
#include <unistd.h>
#include <CoreFoundation/CoreFoundation.h>
#include <DiskArbitration/DiskArbitration.h>
#include <Security/Security.h>

char const *daReturnStr(DAReturn v)
{
	if (unix_err(err_get_code(v)) == v)
		return strerror(err_get_code(v));
	
	switch (v)
	{
		case kDAReturnError:
			return "Error";
		case kDAReturnBusy:
			return "Busy";
		case kDAReturnBadArgument:
			return "Bad Argument";
		case kDAReturnExclusiveAccess:
			return "Exclusive Access";
		case kDAReturnNoResources:
			return "No Resources";
		case kDAReturnNotFound:
			return "Not Found";
		case kDAReturnNotMounted:
			return "Not Mounted";
		case kDAReturnNotPermitted:
			return "Not Permitted";
		case kDAReturnNotPrivileged:
			return "Not Privileged";
		case kDAReturnNotReady:
			return "Not Ready";
		case kDAReturnNotWritable:
			return "Not Writable";
		case kDAReturnUnsupported:
			return "Unsupported";
		default:
			return "Unknown";
	}
}

int getDASessionAndDisk(NSString *bsdName, DASessionRef *pSession, DADiskRef *pDisk)
{
	DASessionRef session = DASessionCreate(kCFAllocatorDefault);
	
	if (!session)
	{
		NSLog(@"DASessionCreate Returned NULL");
		
		return -1;
	}
	
	DADiskRef disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, [bsdName UTF8String]);
	
	if (!disk)
	{
		CFRelease(session);
		NSLog(@"DADiskCreateFromBSDName(%s) Returned NULL", [bsdName UTF8String]);
		
		return -1;
	}
	
	if (pDisk)
		*pDisk = disk;
	else
		CFRelease(disk);
	
	if (pSession)
		*pSession = session;
	else
		CFRelease(session);
	
	return 0;
}

void unmountDiskCallback(DADiskRef disk __unused, DADissenterRef dissenter, void *context)
{
	if (context && dissenter != NULL)
	{
		*(int*) context = -1;
		NSLog(@"Unmount Unsuccessful, Status %s", daReturnStr(DADissenterGetStatus(dissenter)));
	}
	
	CFRunLoopStop(CFRunLoopGetCurrent());
}

DADissenterRef unmountApprovalCallback(DADiskRef disk, void *context)
{
	DADissenterRef dissenter = DADissenterCreate(kCFAllocatorDefault, kDAReturnNotPermitted, CFSTR("mount disallowed"));
	
	NSLog(@"Unmount Unsuccessful, Status %s", daReturnStr(DADissenterGetStatus(dissenter)));
	
	return dissenter;
}

void mountDiskCallback(DADiskRef disk __unused, DADissenterRef dissenter, void *context)
{
	if (context && dissenter != NULL)
	{
		*(int*) context = -1;
		NSLog(@"Mount Unsuccessful, Status %s", daReturnStr(DADissenterGetStatus(dissenter)));
	}
	
	CFRunLoopStop(CFRunLoopGetCurrent());
}

DADissenterRef mountApprovalCallback(DADiskRef disk, void *context)
{
	DADissenterRef dissenter = DADissenterCreate(kCFAllocatorDefault, kDAReturnSuccess, CFSTR("mount disallowed"));
	
	NSLog(@"Mount Unsuccessful, Status %s", daReturnStr(DADissenterGetStatus(dissenter)));
	
	return dissenter;
}

void updateDiskList(NSMutableArray *disksArray, NSString *efiBootDeviceUUID)
{
	for (Disk *disk in disksArray)
		disk.isBootableEFI = false;
	
	for (Disk *disk in disksArray)
	{
		if (![disk.mediaUUID isEqualToString:efiBootDeviceUUID])
			continue;
		
		if (disk.isEFI)
		{
			disk.isBootableEFI = true;
			
			break;
		}
		
		for (Disk *efiDisk in disksArray)
		{
			if (!efiDisk.isEFI || ![efiDisk.disk isEqualToString:disk.disk])
				continue;
			
			efiDisk.isBootableEFI = true;
			
			break;
		}
	}
	
	for (Disk *disk in disksArray)
	{
		if (![disk isAPFSContainer])
			continue;
		
		NSString *bsdName = nil;
		
		if (!getAPFSPhysicalStoreBSDName(disk.mediaUUID, &bsdName))
			continue;
		
		disk.apfsBSDNameLink = bsdName;
		
		for (Disk *apfsPhysicalDisk in disksArray)
		{
			if (![apfsPhysicalDisk.mediaBSDName isEqualToString:bsdName])
				continue;
			
			apfsPhysicalDisk.apfsBSDNameLink = disk.mediaBSDName;
		}
	}
}

bool getDiskInfo(CFDictionaryRef descriptionDictionary, Disk **disk)
{
	NSString *mediaName = (__bridge NSString *)CFDictionaryGetValue(descriptionDictionary, kDADiskDescriptionMediaNameKey);
	NSString *mediaBSDName = (__bridge NSString *)CFDictionaryGetValue(descriptionDictionary, kDADiskDescriptionMediaBSDNameKey);
	CFUUIDRef mediaUUID =   (CFUUIDRef)CFDictionaryGetValue(descriptionDictionary, kDADiskDescriptionMediaUUIDKey);
	NSString *volumeKind =  (__bridge NSString *)CFDictionaryGetValue(descriptionDictionary, kDADiskDescriptionVolumeKindKey);
	NSString *volumeName =  (__bridge NSString *)CFDictionaryGetValue(descriptionDictionary, kDADiskDescriptionVolumeNameKey);
	NSURL *volumePath = (__bridge NSURL *)CFDictionaryGetValue(descriptionDictionary, kDADiskDescriptionVolumePathKey);
	NSString *volumeType = (__bridge NSString *)CFDictionaryGetValue(descriptionDictionary, kDADiskDescriptionVolumeTypeKey);
	CFUUIDRef volumeUUID =  (CFUUIDRef)CFDictionaryGetValue(descriptionDictionary, kDADiskDescriptionVolumeUUIDKey);
	NSString *busName = (__bridge NSString *)CFDictionaryGetValue(descriptionDictionary, kDADiskDescriptionBusNameKey);
	NSDictionary *mediaIcon = (__bridge NSDictionary *)CFDictionaryGetValue(descriptionDictionary, kDADiskDescriptionMediaIconKey);
	NSString *mediaContent = (__bridge NSString *)CFDictionaryGetValue(descriptionDictionary, kDADiskDescriptionMediaContentKey);
	NSNumber *mediaSize = (__bridge NSNumber *)CFDictionaryGetValue(descriptionDictionary, kDADiskDescriptionMediaSizeKey);
	NSNumber *volumeMountable = (__bridge NSNumber *)CFDictionaryGetValue(descriptionDictionary, kDADiskDescriptionVolumeMountableKey);
	NSNumber *volumeNetwork = (__bridge NSNumber *)CFDictionaryGetValue(descriptionDictionary, kDADiskDescriptionVolumeNetworkKey);
	NSNumber *mediaWhole = (__bridge NSNumber *)CFDictionaryGetValue(descriptionDictionary, kDADiskDescriptionMediaWholeKey);
	NSNumber *mediaLeaf = (__bridge NSNumber *)CFDictionaryGetValue(descriptionDictionary, kDADiskDescriptionMediaLeafKey);
	NSNumber *mediaWritable = (__bridge NSNumber *)CFDictionaryGetValue(descriptionDictionary, kDADiskDescriptionMediaWritableKey);
	NSNumber *mediaEjectable = (__bridge NSNumber *)CFDictionaryGetValue(descriptionDictionary, kDADiskDescriptionMediaEjectableKey);
	NSNumber *mediaRemovable = (__bridge NSNumber *)CFDictionaryGetValue(descriptionDictionary, kDADiskDescriptionMediaRemovableKey);
	NSNumber *deviceInternal = (__bridge NSNumber *)CFDictionaryGetValue(descriptionDictionary, kDADiskDescriptionDeviceInternalKey);
	NSString *deviceModel = (__bridge NSString *)CFDictionaryGetValue(descriptionDictionary, kDADiskDescriptionDeviceModelKey);
	
	if (mediaBSDName == nil)
		return false;
	
	NSString *mediaUUIDString = (mediaUUID != nil ? CFBridgingRelease(CFUUIDCreateString(kCFAllocatorDefault, mediaUUID)) : nil);
	NSString *volumeUUIDString = (volumeUUID != nil ? CFBridgingRelease(CFUUIDCreateString(kCFAllocatorDefault, volumeUUID)) : nil);
	
	int diskAttributes = kDiskAttribNone;
	
	if (volumeMountable != nil ? [volumeMountable boolValue] : false)
		diskAttributes |= kDiskAttribVolumeMountable;
	
	if (volumeNetwork != nil ? [volumeNetwork boolValue] : false)
		diskAttributes |= kDiskAttribVolumeNetworkKey;
	
	if (mediaWhole != nil ? [mediaWhole boolValue] : false)
		diskAttributes |= kDiskAttribMediaWholeKey;
	
	if (mediaLeaf != nil ? [mediaLeaf boolValue]: false)
		diskAttributes |= kDiskAttribMediaLeafKey;
	
	if (mediaWritable != nil ? [mediaWritable boolValue] : false)
		diskAttributes |= kDiskAttribMediaWritableKey;
	
	if (mediaEjectable != nil ? [mediaEjectable boolValue]: false)
		diskAttributes |= kDiskAttribMediaEjectableKey;
	
	if (mediaRemovable != nil ? [mediaRemovable boolValue] : false)
		diskAttributes |= kDiskAttribMediaRemovableKey;
	
	if (deviceInternal != nil ? [deviceInternal boolValue]: false)
		diskAttributes |= kDiskAttribDeviceInternalKey;
	
	if (!*disk)
		*disk = [[Disk alloc] initWithMediaName:mediaName mediaBSDName:mediaBSDName mediaUUID:mediaUUIDString volumeKind:volumeKind volumeName:volumeName volumePath:volumePath volumeType:volumeType volumeUUID:volumeUUIDString busName:busName mediaIcon:mediaIcon mediaContent:mediaContent mediaSize:mediaSize deviceModel:deviceModel diskAttributes:diskAttributes];
	else
	{
		(*disk).mediaName = mediaName;
		(*disk).mediaBSDName = mediaBSDName;
		(*disk).mediaUUID = mediaUUIDString;
		(*disk).volumeKind = volumeKind;
		(*disk).volumeName = volumeName;
		(*disk).volumePath = volumePath;
		(*disk).volumeType = volumeType;
		(*disk).volumeUUID = volumeUUIDString;
		(*disk).busName = busName;
		(*disk).mediaContent = mediaContent;
		(*disk).mediaSize = mediaSize;
		(*disk).deviceModel = deviceModel;
		(*disk).diskAttributes = diskAttributes;
	}
	
	return true;
}

bool tryUpdateDiskInfo(Disk *disk)
{
	bool result = false;
	DASessionRef session = DASessionCreate(kCFAllocatorDefault);
	
	if (!session)
		return false;
	
	DADiskRef daDisk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, [disk.mediaBSDName UTF8String]);
	
	if (daDisk)
	{
		CFDictionaryRef descriptionDictionary = DADiskCopyDescription(daDisk);
		
		if (descriptionDictionary != nil)
		{
			result = getDiskInfo(descriptionDictionary, &disk);
			
			CFRelease(descriptionDictionary);
		}
		
		CFRelease(daDisk);
	}
	
	CFRelease(session);
	
	return result;
}

NSInteger diskSort(id a, id b, void *context)
{
	//return [((Disk *)a).mediaBSDName compare:((Disk *)b).mediaBSDName];
	return [((Disk *)a).bsdNumber compare:((Disk *)b).bsdNumber];
}

void diskAppearedCallback(DADiskRef disk, void *context)
{
	AppDelegate *appDelegate = (AppDelegate *)context;
	CFDictionaryRef descriptionDictionary = DADiskCopyDescription(disk);
	
	Disk *foundDisk = nil;
	
	bool result = getDiskInfo(descriptionDictionary, &foundDisk);
	
	CFRelease(descriptionDictionary);
	
	if (!result)
		return;
	
	[appDelegate.disksArray addObject:foundDisk];
	
	[foundDisk release];
	
	[appDelegate.disksArray sortUsingFunction:diskSort context:nil];
	
	updateDiskList(appDelegate.disksArray, appDelegate.efiBootDeviceUUID);
	
	[appDelegate refreshDisks];
}

void diskDisappearedCallback(DADiskRef disk, void *context)
{
	AppDelegate *appDelegate = (AppDelegate *)context;
	CFDictionaryRef descriptionDictionary = DADiskCopyDescription(disk);
	
	CFStringRef mediaBSDNameKey = (CFStringRef)CFDictionaryGetValue(descriptionDictionary, kDADiskDescriptionMediaBSDNameKey);
	NSString *mediaBSDName = (__bridge NSString *)mediaBSDNameKey;
	
	for (Disk *foundDisk in appDelegate.disksArray)
	{
		if ([mediaBSDName isEqualToString:foundDisk.mediaBSDName])
		{
			[appDelegate.disksArray removeObject:foundDisk];
			
			break;
		}
	}
	
	updateDiskList(appDelegate.disksArray, appDelegate.efiBootDeviceUUID);
	
	CFRelease(descriptionDictionary);
	
	[appDelegate refreshDisks];
}

void diskDescriptionChangedCallback(DADiskRef disk, CFArrayRef keys, void *context)
{
	AppDelegate *appDelegate = (AppDelegate *)context;
	CFDictionaryRef descriptionDictionary = DADiskCopyDescription(disk);
	
	CFStringRef mediaBSDNameKey = (CFStringRef)CFDictionaryGetValue(descriptionDictionary, kDADiskDescriptionMediaBSDNameKey);
	NSString *mediaBSDName = (__bridge NSString *)mediaBSDNameKey;
	
	for (Disk *foundDisk in appDelegate.disksArray)
	{
		if ([mediaBSDName isEqualToString:foundDisk.mediaBSDName])
			getDiskInfo(descriptionDictionary, &foundDisk);
	}
	
	[appDelegate.disksArray sortUsingFunction:diskSort context:nil];
	
	updateDiskList(appDelegate.disksArray, appDelegate.efiBootDeviceUUID);
	
	CFRelease(descriptionDictionary);
	
	[appDelegate refreshDisks];
}

bool tryGetEFIBootDisk(NSMutableArray *disksArray, Disk **foundDisk)
{
	for (Disk *disk in disksArray)
	{
		if (!disk.isBootableEFI)
			continue;
		
		*foundDisk = disk;
		
		return true;
	}
	
	return false;
}

NSMutableArray *getEfiPartitionsArray(NSMutableArray *disksArray)
{
	NSMutableArray *efiPartitionsArray = [NSMutableArray array];

	for (Disk *disk in disksArray)
	{
		if (!disk.isEFI)
			continue;
		
		[efiPartitionsArray addObject:disk];
	}
	
	return efiPartitionsArray;
}

void registerDiskCallbacks(void *context)
{
	DASessionRef session = DASessionCreate(kCFAllocatorDefault);
	
	// kDADiskDescriptionMatchVolumeMountable
	DARegisterDiskAppearedCallback(session, NULL, diskAppearedCallback, context);
	DARegisterDiskDisappearedCallback(session, NULL, diskDisappearedCallback, context);
	DARegisterDiskDescriptionChangedCallback(session, NULL, NULL, diskDescriptionChangedCallback, context);
	DASessionScheduleWithRunLoop(session, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
}

NSString *getDeviceName(NSMutableArray *disksArray, NSString *mediaBSDName)
{
	for (Disk *disk in disksArray)
	{
		if ([disk.mediaBSDName isEqualToString:mediaBSDName])
		{
			if (disk.mediaName != nil)
				return disk.mediaName;
			else if (disk.deviceModel != nil)
				return disk.deviceModel;
		}
	}
	
	return @"";
}
