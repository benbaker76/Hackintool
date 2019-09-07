//
//  Disk.h
//  Hackintool
//
//  Created by Ben Baker on 2/12/19.
//  Copyright © 2019 Ben Baker. All rights reserved.
//

#ifndef Disk_h
#define Disk_h

#import <Cocoa/Cocoa.h>

#define DISKMEDIA_HFS_PLUS				@"48465300-0000-11AA-AA11-00306543ECAC"
#define DISKMEDIA_FILEVAULT				@"53746F72-6167-11AA-AA11-00306543ECAC"
#define DISKMEDIA_APPLE_APFS			@"7C3457EF-0000-11AA-AA11-00306543ECAC"
#define DISKMEDIA_APFS_VOLUME			@"41504653-0000-11AA-AA11-00306543ECAC"
#define DISKMEDIA_ZFS					@"6A898CC3-1DD2-11B2-99A6-080020736631"
#define DISKMEDIA_APFS_CONTAINER_1		@"55465300-0000-11AA-AA11-00306543ECAC"
#define DISKMEDIA_APFS_CONTAINER_2		@"EF57347C-0000-11AA-AA11-00306543ECAC"
#define DISKMEDIA_EFI					@"C12A7328-F81F-11D2-BA4B-00A0C93EC93B"
#define DISKMEDIA_WINDOWS_RECOVERY		@"DE94BBA4-06D1-4D40-A16A-BFD50179D6AC"
#define DISKMEDIA_APPLE_RECOVERY		@"426F6F74-0000-11AA-AA11-00306543ECAC"
#define DISKMEDIA_MS_RESERVED			@"E3C9E316-0B5C-4DB8-817D-F92DF00215AE"
#define DISKMEDIA_MS_BASIC_DATA			@"EBD0A0A2-B9E5-4433-87C0-68B6B72699C7"

enum DiskAttributes : int
{
	kDiskAttribNone = 0,
	kDiskAttribVolumeMountable = (1 << 0),
	kDiskAttribVolumeNetworkKey = (2 << 0),
	kDiskAttribMediaWholeKey = (3 << 0),
	kDiskAttribMediaLeafKey = (4 << 0),
	kDiskAttribMediaWritableKey = (5 << 0),
	kDiskAttribMediaEjectableKey = (6 << 0),
	kDiskAttribMediaRemovableKey = (7 << 0),
	kDiskAttribDeviceInternalKey = (8 << 0)
};

struct FileType
{
	NSString *Name;
	NSString *UUID;
	NSColor *Color;
	
	FileType(NSString *name, NSString *uuid, NSColor *color) :
	Name(name),
	UUID(uuid),
	Color(color)
	{
	}
};

@interface Disk : NSObject
{
}

@property (nonatomic, retain) NSString *mediaName;
@property (nonatomic, retain) NSString *mediaBSDName;
@property (nonatomic, retain) NSString *mediaUUID;
@property (nonatomic, retain) NSString *volumeKind;
@property (nonatomic, retain) NSString *volumeName;
@property (nonatomic, retain) NSURL *volumePath;
@property (nonatomic, retain) NSString *volumeType;
@property (nonatomic, retain) NSString *volumeUUID;
@property (nonatomic, retain) NSString *busName;
@property (nonatomic, retain) NSDictionary *mediaIcon;
@property (nonatomic, retain) NSString *mediaContent;
@property (nonatomic, retain) NSNumber *mediaSize;
@property (nonatomic, retain) NSString *deviceModel;
@property uint32_t diskAttributes;
@property Boolean isBootableEFI;
@property (nonatomic, retain) NSString *apfsBSDNameLink;

-(id) initWithMediaName:(NSString *)mediaName mediaBSDName:(NSString *)mediaBSDName mediaUUID:(NSString *)mediaUUID volumeKind:(NSString *)volumeKind volumeName:(NSString *)volumeName volumePath:(NSURL *)volumePath volumeType:(NSString *)volumeType volumeUUID:(NSString *)volumeUUID busName:(NSString *)busName mediaIcon:(NSDictionary *)mediaIcon mediaContent:(NSString *)mediaContent mediaSize:(NSNumber *)mediaSize deviceModel:(NSString *)deviceModel diskAttributes:(uint32_t)diskAttributes;
- (bool)mount:(NSString **)stdoutString stderrString:(NSString **)stderrString;
- (bool)unmount:(NSString **)stdoutString stderrString:(NSString **)stderrString;
- (bool)eject:(NSString **)stdoutString stderrString:(NSString **)stderrString;
- (bool)convertToAPFS:(NSString **)stdoutString stderrString:(NSString **)stderrString;
- (bool)deleteAPFSContainer:(NSString **)stdoutString stderrString:(NSString **)stderrString;
- (bool)sizeInfo:(NSNumber **)totalSize freeSize:(NSNumber **)freeSize;
- (bool)sizeInfo:(NSNumber **)blockSize totalSize:(NSNumber **)totalSize volumeTotalSize:(NSNumber **)volumeTotalSize volumeFreeSpace:(NSNumber **)volumeFreeSpace;
- (NSString *)type;
- (NSColor *)color:(CGFloat)alpha;
- (NSString *)disk;
- (int)device;
- (int)slice;
- (NSNumber *)bsdNumber;
- (NSImage *)icon;
- (BOOL)isDisk;
- (BOOL)isMountable;
- (BOOL)isNetworkVolume;
- (BOOL)isWholeDisk;
- (BOOL)isLeaf;
- (BOOL)isWriteable;
- (BOOL)isEjectable;
- (BOOL)isRemovable;
- (BOOL)isInternal;
- (BOOL)isMounted;
- (BOOL)isHFS;
- (BOOL)isEFI;
- (BOOL)isAPFS;
- (BOOL)isAPFSContainer;
- (BOOL)isFileSystemWritable;

@end

#endif /* Disk_h */
