//
//  Disk.m
//  Hackintool
//
//  Created by Ben Baker on 2/12/19.
//  Copyright © 2019 Ben Baker. All rights reserved.
//

#import "Disk.h"
#include "DiskUtilities.h"
#include "MiscTools.h"
#include "IORegTools.h"
#include "DMManager.h"
#include "MiscTools.h"
#include <IOKit/kext/KextManager.h>
#include <sys/param.h>
#include <sys/mount.h>

struct FileType _fileTypeArray[] =
{
	{ @"HFS+",					DISKMEDIA_HFS_PLUS,			[NSColor systemRedColor] },
	{ @"FileVault",				DISKMEDIA_FILEVAULT,		[NSColor systemPinkColor] },
	{ @"Apple_APFS",			DISKMEDIA_APPLE_APFS,		[NSColor systemOrangeColor] },
	{ @"APFS Volume",			DISKMEDIA_APFS_VOLUME,		[NSColor systemOrangeColor] },
	{ @"ZFS",					DISKMEDIA_ZFS,				[NSColor systemYellowColor] },
	{ @"APFS Container",		DISKMEDIA_APFS_CONTAINER_1,	[NSColor systemOrangeColor] },
	{ @"APFS Container",		DISKMEDIA_APFS_CONTAINER_2,	[NSColor systemOrangeColor] },
	{ @"EFI", 					DISKMEDIA_EFI,				[NSColor systemBrownColor] },
	{ @"Windows Recovery",		DISKMEDIA_WINDOWS_RECOVERY,	[NSColor systemPurpleColor] },
	{ @"Apple Recovery",		DISKMEDIA_APPLE_RECOVERY,	[NSColor systemPurpleColor] },
	{ @"Microsoft Reserved",	DISKMEDIA_MS_RESERVED,		[NSColor systemPurpleColor] },
	{ @"Microsoft Basic Data",	DISKMEDIA_MS_BASIC_DATA,	[NSColor systemGrayColor] },
	{ nil, nil, nil }
};

NSString *const kVolumeIconFileName = @".VolumeIcon.icns";

@implementation Disk

-(id) initWithMediaName:(NSString *)mediaName mediaBSDName:(NSString *)mediaBSDName mediaUUID:(NSString *)mediaUUID volumeKind:(NSString *)volumeKind volumeName:(NSString *)volumeName volumePath:(NSURL *)volumePath volumeType:(NSString *)volumeType volumeUUID:(NSString *)volumeUUID busName:(NSString *)busName mediaIcon:(NSDictionary *)mediaIcon mediaContent:(NSString *)mediaContent mediaSize:(NSNumber *)mediaSize deviceModel:(NSString *)deviceModel diskAttributes:(uint32_t)diskAttributes
{
	if (self = [super init])
	{
		self.mediaName = mediaName;
		self.mediaBSDName = mediaBSDName;
		self.mediaUUID = mediaUUID;
		self.volumeKind = volumeKind;
		self.volumeName = volumeName;
		self.volumePath = volumePath;
		self.volumeType = volumeType;
		self.volumeUUID = volumeUUID;
		self.busName = busName;
		self.mediaIcon = mediaIcon;
		self.mediaContent = mediaContent;
		self.mediaSize = mediaSize;
		self.deviceModel = deviceModel;
		self.diskAttributes = diskAttributes;
		self.isBootableEFI = false;
		self.apfsBSDNameLink = nil;
	}
	
	return self;
}

- (void)dealloc
{
	[_mediaName release];
	[_mediaBSDName release];
	[_mediaUUID release];
	[_volumeKind release];
	[_volumeName release];
	[_volumePath release];
	[_volumeType release];
	[_volumeUUID release];
	[_busName release];
	[_mediaIcon release];
	[_mediaContent release];
	[_mediaSize release];
	[_deviceModel release];
	[_apfsBSDNameLink release];
	
	[super dealloc];
}

- (bool)mount:(NSString **)stdoutString stderrString:(NSString **)stderrString
{
	bool success = launchCommandAsAdmin(@"diskutil", @[@"mount", [NSString stringWithFormat:@"/dev/%@", _mediaBSDName]], stdoutString, stderrString);
	
	tryUpdateDiskInfo(self);
	
	return success;
}

- (bool)unmount:(NSString **)stdoutString stderrString:(NSString **)stderrString
{
	bool success = launchCommandAsAdmin(@"diskutil", @[@"unmount", [NSString stringWithFormat:@"/dev/%@", _mediaBSDName]], stdoutString, stderrString);
	
	tryUpdateDiskInfo(self);
	
	return success;
}

- (bool)eject:(NSString **)stdoutString stderrString:(NSString **)stderrString
{
	bool success = launchCommandAsAdmin(@"diskutil", @[@"eject", [NSString stringWithFormat:@"/dev/%@", _mediaBSDName]], stdoutString, stderrString);
	
	tryUpdateDiskInfo(self);
	
	return success;
}

- (bool)convertToAPFS:(NSString **)stdoutString stderrString:(NSString **)stderrString
{
	if (![self isHFS])
		return false;
	
	bool success = launchCommandAsAdmin(@"diskutil", @[@"apfs", @"convert", _mediaBSDName], stdoutString, stderrString);
	
	tryUpdateDiskInfo(self);
	
	return success;
}

- (bool)deleteAPFSContainer:(NSString **)stdoutString stderrString:(NSString **)stderrString
{
	if (![self isAPFSContainer])
		return false;
	
	bool success = launchCommandAsAdmin(@"diskutil", @[@"apfs", @"deleteContainer", _mediaBSDName], stdoutString, stderrString);
	
	tryUpdateDiskInfo(self);
	
	return success;
}

// http://www.edenwaith.com/blog/index.php?p=67
- (bool)sizeInfo:(NSNumber **)totalSize freeSize:(NSNumber **)freeSize
{
	if (_volumePath == nil)
		return false;
	
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSDictionary *fileAttributes = [fileManager attributesOfFileSystemForPath:[_volumePath path] error:nil];
	
	*totalSize = [fileAttributes objectForKey:NSFileSystemSize];
	*freeSize = [fileAttributes objectForKey:NSFileSystemFreeSize];
	
	return true;
}

- (bool)sizeInfo:(NSNumber **)blockSize totalSize:(NSNumber **)totalSize volumeTotalSize:(NSNumber **)volumeTotalSize volumeFreeSpace:(NSNumber **)volumeFreeSpace
{
	DASessionRef session;
	DADiskRef disk;
	
	if (getDASessionAndDisk(_mediaBSDName, &session, &disk) < 0)
		return false;
	
	DMManager *dmManager = [DMManager sharedManager];
	*blockSize = (NSNumber *)[dmManager blockSizeForDisk:disk error:nil];
	*totalSize = (NSNumber *)[dmManager totalSizeForDisk:disk error:nil];
	*volumeTotalSize = (NSNumber *)[dmManager volumeTotalSizeForDisk:disk error:nil];
	*volumeFreeSpace = (NSNumber *)[dmManager volumeFreeSpaceForDisk:disk error:nil];
	
	CFRelease(disk);
	CFRelease(session);
	
	return true;
}

- (NSString *)type
{
	int index = 0;
	
	while (true)
	{
		struct FileType fileType = _fileTypeArray[index];
		
		if (fileType.Name == nil)
			break;
		
		if ([_mediaContent isEqualToString:fileType.UUID])
			return fileType.Name;
		
		index++;
	}
	
	if (_mediaContent != nil)
		return _mediaContent;
	
	return @"";
}

- (NSColor *)color:(CGFloat)alpha
{
	int index = 0;
	
	while (true)
	{
		struct FileType fileType = _fileTypeArray[index];
		
		if (fileType.Name == nil)
			break;
		
		if (_isBootableEFI)
			return getColorAlpha([NSColor systemGreenColor], alpha);
		
		if ([_mediaContent isEqualToString:fileType.UUID])
			return getColorAlpha(fileType.Color, alpha);
		
		index++;
	}
	
	return getColorAlpha([NSColor controlBackgroundColor], 0.0f);
}

- (NSString *)disk
{
	return [NSString stringWithFormat:@"disk%d", [self device]];
}

- (int)device
{
	uint32_t device = 0, slice = -1;
	[self getBSDDeviceSlice:&device slice:&slice];
	
	return device;
}

- (int)slice
{
	uint32_t device = 0, slice = -1;
	[self getBSDDeviceSlice:&device slice:&slice];
	
	return slice;
}

- (NSNumber *)bsdNumber
{
	uint32_t device = 0, slice = 0;
	[self getBSDDeviceSlice:&device slice:&slice];
	
	return [NSNumber numberWithInteger:(device * 1000) + slice];
}

- (bool)getBSDDeviceSlice:(uint32_t *)device slice:(uint32_t *)slice
{
	if (_mediaBSDName == nil)
		return false;
	
	NSMutableArray *itemArray;
	
	if (getRegExArray(@"disk(.*)s(.*)", _mediaBSDName, 2, &itemArray))
	{
		*device = getIntFromString(itemArray[0]);
		*slice = getIntFromString(itemArray[1]);
		
		return true;
	}
	else if (getRegExArray(@"disk(.*)", _mediaBSDName, 1, &itemArray))
	{
		*device = getIntFromString(itemArray[0]);
		
		return true;
	}
	
	return false;
}

- (NSImage *)icon
{
	//if (_volumePath && [_volumePath checkResourceIsReachableAndReturnError:nil])
	//	return [[NSWorkspace sharedWorkspace] iconForFile:[_volumePath path]];
	
	NSURL *volumeIconURL = [_volumePath URLByAppendingPathComponent:kVolumeIconFileName];
	if (volumeIconURL && [volumeIconURL checkResourceIsReachableAndReturnError:nil])
	{
		NSImage *volumeIconImage = [[NSImage alloc] initWithContentsOfFile:[volumeIconURL path]];
		[volumeIconImage autorelease];
		return volumeIconImage;
	}
	
	NSString *bundleIdentifier = [_mediaIcon objectForKey:(NSString *)kCFBundleIdentifierKey];
	NSString *bundleResourceFile = [_mediaIcon objectForKey:@kIOBundleResourceFileKey];
	
	if (bundleIdentifier && bundleResourceFile)
	{
		NSURL *bundleURL = (__bridge NSURL *)KextManagerCreateURLForBundleIdentifier(kCFAllocatorDefault, (__bridge CFStringRef)bundleIdentifier);
		NSBundle *bundle = [NSBundle bundleWithURL:bundleURL];
		[bundleURL release];
		NSImage *volumeIconImage = [[NSImage alloc] initWithContentsOfFile:[bundle pathForResource:bundleResourceFile ofType:nil]];
		[volumeIconImage autorelease];
		return volumeIconImage;
	}
	
	return nil;
}

- (BOOL)isDisk
{
	return ([self slice] == -1);
}

- (BOOL)isMountable
{
	return (_diskAttributes & kDiskAttribVolumeMountable);
}

- (BOOL)isNetworkVolume
{
	return (_diskAttributes & kDiskAttribVolumeNetworkKey);
}

- (BOOL)isWholeDisk
{
	return (_diskAttributes & kDiskAttribMediaWholeKey);
}

- (BOOL)isLeaf
{
	return (_diskAttributes & kDiskAttribMediaLeafKey);
}

- (BOOL)isWriteable
{
	return (_diskAttributes & kDiskAttribMediaWritableKey);
}

- (BOOL)isEjectable
{
	return (_diskAttributes & kDiskAttribMediaEjectableKey);
}

- (BOOL)isRemovable
{
	return (_diskAttributes & kDiskAttribMediaRemovableKey);
}

- (BOOL)isInternal
{
	return (_diskAttributes & kDiskAttribDeviceInternalKey);
}

- (BOOL)isMounted
{
	return (_volumePath != nil);
}

- (BOOL)isHFS
{
	return [_volumeKind isEqualToString:@"hfs"];
}

- (BOOL)isEFI
{
	//return [_volumeName isEqualToString:@"EFI"];
	return [_mediaContent isEqualToString:DISKMEDIA_EFI];
}

- (BOOL)isAPFS
{
	return [_mediaContent isEqualToString:DISKMEDIA_APPLE_APFS];
}

- (BOOL)isAPFSContainer
{
	return ([_mediaContent isEqualToString:DISKMEDIA_APFS_CONTAINER_1] || [_mediaContent isEqualToString:DISKMEDIA_APFS_CONTAINER_2]);
}

- (BOOL)isFileSystemWritable
{
	BOOL retval = NO;
	struct statfs fsstat {};
	UInt8 fsrep[MAXPATHLEN];
	
	// if the media is not writable, the file system cannot be either
	if (![self isWriteable])
		return NO;
	
	if (_volumePath)
	{
		if (CFURLGetFileSystemRepresentation((__bridge CFURLRef)_volumePath, true, fsrep, sizeof(fsrep)))
		{
			if (statfs((char *)fsrep, &fsstat) == 0)
				retval = (fsstat.f_flags & MNT_RDONLY) ? NO : YES;
		}
	}
	
	return retval;
}

- (BOOL)isDMG
{
	return [self.deviceModel isEqualToString:@"Disk Image"];
}

@end
