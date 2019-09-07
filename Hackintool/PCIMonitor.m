//
//  PCIMonitor.m
//  Hackintool
//
//  Created by Daniel Siemer on 5/5/12.
//  Modified by Ben Baker.
//  Copyright (c) 2012 The Growl Project, LLC. All rights reserved.
//

#import "PCIMonitor.h"
#include <IOKit/IOKitLib.h>

@implementation PCIMonitor

@synthesize delegate;
@synthesize notificationsArePrimed;
@synthesize ioKitNotificationPort;
@synthesize notificationRunLoopSource;

-(id)init {
	if((self = [super init])){
		self.notificationsArePrimed = NO;
		//#warning	kIOMasterPortDefault is only available on 10.2 and above...
		self.ioKitNotificationPort = IONotificationPortCreate(kIOMasterPortDefault);
		self.notificationRunLoopSource = IONotificationPortGetRunLoopSource(ioKitNotificationPort);
		
		CFRunLoopAddSource(CFRunLoopGetCurrent(), notificationRunLoopSource, kCFRunLoopDefaultMode);
	}
	return self;
}

-(void)dealloc {
	if (ioKitNotificationPort) {
		CFRunLoopRemoveSource(CFRunLoopGetCurrent(), notificationRunLoopSource, kCFRunLoopDefaultMode);
		IONotificationPortDestroy(ioKitNotificationPort);
	}
	[super dealloc];
}

-(NSString*)nameForPCIObject:(io_object_t)thisObject {
	kern_return_t		nameResult;
	io_struct_inband_t	deviceNameChars;
	uint32_t size = sizeof(io_struct_inband_t);
	
	nameResult = IORegistryEntryGetProperty(thisObject, "IOName", deviceNameChars, &size);
	
	if (nameResult != KERN_SUCCESS) {
		NSLog(@"Could not get name for PCI object: IORegistryEntryGetName returned 0x%x", nameResult);
		return NULL;
	}
	
	NSString* tempDeviceName = [NSString stringWithCString:deviceNameChars encoding:NSASCIIStringEncoding];
	if (tempDeviceName) {
		return tempDeviceName;
	}
	
	return NSLocalizedString(@"Unnamed PCI Device", @"");
}

#pragma mark Callbacks

-(void)pciDeviceAdded:(io_iterator_t)iterator {
	io_object_t	thisObject;
	while ((thisObject = IOIteratorNext(iterator))) {
		if (notificationsArePrimed) {
			NSString *deviceName = [self nameForPCIObject:thisObject];
			[delegate pciDeviceName:deviceName added:YES];
		}
		IOObjectRelease(thisObject);
	}
}

static void pciDeviceAdded(void *refCon, io_iterator_t iterator) {
	PCIMonitor *monitor = (PCIMonitor*)refCon;
	[monitor pciDeviceAdded:iterator];
}

-(void)pciDeviceRemoved:(io_iterator_t)iterator {
	io_object_t thisObject;
	while ((thisObject = IOIteratorNext(iterator))) {
		NSString *deviceName = [self nameForPCIObject:thisObject];
		[delegate pciDeviceName:deviceName added:NO];
		IOObjectRelease(thisObject);
	}
}

static void pciDeviceRemoved(void *refCon, io_iterator_t iterator) {
	PCIMonitor *monitor = (PCIMonitor*)refCon;
	[monitor pciDeviceRemoved:iterator];
}

#pragma mark -

-(void)registerForPCINotifications {
	// http://developer.apple.com/documentation/DeviceDrivers/Conceptual/AccessingHardware/AH_Finding_Devices/chapter_4_section_2.html#//apple_ref/doc/uid/TP30000379/BABEACCJ
	kern_return_t   matchingResult;
	io_iterator_t   addedIterator;
	kern_return_t   removeNoteResult;
	io_iterator_t   removedIterator;
	CFDictionaryRef pciMatchDictionary;
	
	//	NSLog(@"registerForPCINotifications");
	
	//	Setup a matching dictionary.
	pciMatchDictionary = IOServiceMatching("IOPCIDevice");
	
	//	Register our notification
	matchingResult = IOServiceAddMatchingNotification(ioKitNotificationPort, kIOPublishNotification, pciMatchDictionary, pciDeviceAdded, self, &addedIterator);
	
	if (matchingResult)
		NSLog(@"Matching notification registration failed: %d)", matchingResult);
	
	//	Prime the notifications (And deal with the existing devices)...
	[self pciDeviceAdded:addedIterator];
	
	//	Register for removal notifications.
	
	//	It seems we have to make a new dictionary...  reusing the old one didn't work.
	pciMatchDictionary = IOServiceMatching("IOPCIDevice");
	removeNoteResult = IOServiceAddMatchingNotification(ioKitNotificationPort, kIOTerminatedNotification, pciMatchDictionary, pciDeviceRemoved, self, &removedIterator);
	
	// Matching notification must be "primed" by iterating over the
	// iterator returned from IOServiceAddMatchingNotification(), so
	// we call our device removed method here...
	//
	if (kIOReturnSuccess != removeNoteResult)
		NSLog(@"Couldn't add device removal notification");
	else
		[self pciDeviceRemoved:removedIterator];
	
	self.notificationsArePrimed = YES;
}

@end
