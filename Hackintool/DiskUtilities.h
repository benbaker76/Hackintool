//
//  DiskUtilities.h
//  Hackintool
//
//  Created by Ben Baker on 1/26/19.
//  Copyright © 2019 Ben Baker. All rights reserved.
//

#ifndef DiskUtilities_h
#define DiskUtilities_h

#include "AppDelegate.h"
#include "Disk.h"
#include <DiskArbitration/DiskArbitration.h>

int getDASessionAndDisk(NSString *bsdName, DASessionRef *pSession, DADiskRef *pDisk);
void updateDiskList(NSMutableArray *disksArray, NSString *efiBootDeviceUUID);
bool tryUpdateDiskInfo(Disk *disk);
void diskAppearedCallback(DADiskRef disk, void *context);
void diskDisappearedCallback(DADiskRef disk, void *context);
void diskDescriptionChangedCallback(DADiskRef disk, CFArrayRef keys, void *context);
bool tryGetEFIBootDisk(NSMutableArray *disksArray, Disk **foundDisk);
NSMutableArray *getEfiPartitionsArray(NSMutableArray *disksArray);
void registerDiskCallbacks(void *context);
NSString *getDeviceName(NSMutableArray *disksArray, NSString *mediaBSDName);

#endif /* DiskUtilities_hpp */
