//
//  USB.m
//  Hackintool
//
//  Created by Ben Baker on 1/29/19.
//  Copyright © 2019 Ben Baker. All rights reserved.
//

#define USB_USEREGISTRY

#include "USB.h"
#include <IOKit/IOMessage.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>
#include "IORegTools.h"
#include "Config.h"
#include "Clover.h"
#include "OpenCore.h"
#include "MiscTools.h"

//static NSMutableArray *gDeviceArray = nil;
static CFMutableDictionaryRef gMatchingDict = nil;
static IONotificationPortRef gNotifyPort = nil;
static io_iterator_t gAddedIter = 0;

void usbUnRegisterEvents()
{
	/* if (gDeviceArray)
	{
		for (NSNumber *privateDataNumber in gDeviceArray)
		{
			MyPrivateData *privateDataRef = (MyPrivateData *)[privateDataNumber unsignedLongLongValue];
			
			destroyPrivateData(privateDataRef);
		}
		
		[gDeviceArray release];
		gDeviceArray = nil;
	} */
	
	if (gNotifyPort)
	{
		CFRunLoopRemoveSource(CFRunLoopGetCurrent(), IONotificationPortGetRunLoopSource(gNotifyPort), kCFRunLoopDefaultMode);
		IONotificationPortDestroy(gNotifyPort);
		gNotifyPort = 0;
	}
	
	if (gAddedIter)
	{
		IOObjectRelease(gAddedIter);
		gAddedIter = 0;
	}
	
	if (gMatchingDict)
	{
		//CFRelease(gMatchingDict);
		//CFRelease(gMatchingDict);
		gMatchingDict = nil;
	}
}

void usbRegisterEvents(AppDelegate *appDelegate)
{
	kern_return_t kr;

	usbUnRegisterEvents();
	
	//gDeviceArray = [[NSMutableArray alloc] init];
	
	gMatchingDict = IOServiceMatching(kIOUSBDeviceClassName);
	
	//gMatchingDict = (CFMutableDictionaryRef) CFRetain(gMatchingDict); // Needed for kIOTerminatedNotification
	
	if (!gMatchingDict)
		return;
	
	gNotifyPort = IONotificationPortCreate(kIOMasterPortDefault);
	
	CFRunLoopAddSource(CFRunLoopGetCurrent(), IONotificationPortGetRunLoopSource(gNotifyPort), kCFRunLoopDefaultMode);
	
	kr = IOServiceAddMatchingNotification(gNotifyPort, kIOPublishNotification, gMatchingDict, usbDeviceAdded, appDelegate, &gAddedIter);
	//kr = IOServiceAddMatchingNotification(gNotifyPort, kIOTerminatedNotification, gMatchingDict, usbDeviceRemoved, appDelegate, &gRemovedIter);
	
	usbDeviceAdded(appDelegate, gAddedIter);
	//usbDeviceRemoved(appDelegate, gRemovedIter);
}

void usbDeviceNotification(void *refCon, io_service_t usbDevice, natural_t messageType, void *messageArgument)
{
	MyPrivateData *privateDataRef = (__bridge MyPrivateData *)refCon;
	AppDelegate *appDelegate = (AppDelegate *)privateDataRef->appDelegate;
	
	if (messageType == kIOMessageServiceIsTerminated)
	{
		[appDelegate removeUSBDevice:privateDataRef->controllerID controllerLocationID:privateDataRef->controllerLocationID locationID:privateDataRef->locationID port:privateDataRef->port];
		
		destroyPrivateData(privateDataRef);
		
		//[gDeviceArray removeObject:[NSNumber numberWithUnsignedLongLong:(unsigned long long)privateDataRef]];
	}
}

void destroyPrivateData(MyPrivateData *privateDataRef)
{
	kern_return_t kr;
	
	IOObjectRelease(privateDataRef->removedIter);
	
	CFRelease(privateDataRef->deviceName);
	
	if (privateDataRef->deviceInterface)
		kr = (*privateDataRef->deviceInterface)->Release(privateDataRef->deviceInterface);

	NSDeallocateMemoryPages(privateDataRef, sizeof(MyPrivateData));
}

void usbDeviceAdded(void *refCon, io_iterator_t iterator)
{
	kern_return_t kr = KERN_FAILURE;
	AppDelegate *appDelegate = (__bridge AppDelegate *)refCon;
	
	for (io_service_t usbDevice; IOIteratorIsValid(iterator) && (usbDevice = IOIteratorNext(iterator)); IOObjectRelease(usbDevice))
	{
		io_name_t deviceName = { };
		//IOCFPlugInInterface **plugInInterface = 0;
		IOUSBDeviceInterface650 **deviceInterface = 0;
		//IOUSBDeviceInterface **deviceInterface = 0;
		//SInt32 score = 0;
		uint32_t locationID = 0;
		uint8_t devSpeed = -1;
		uint32_t vendorID = 0;
		uint32_t productID = 0;
		uint32_t controllerID = 0;
		uint32_t controllerLocationID = 0;
		uint32_t port = 0;
		uint64_t registryID = 0;
		
		kr = IORegistryEntryGetName(usbDevice, deviceName);
		
		if (kr != KERN_SUCCESS)
			deviceName[0] = '\0';
		
#ifdef USB_USEREGISTRY
		CFMutableDictionaryRef propertyDictionaryRef = nil;
		
		kr = IORegistryEntryCreateCFProperties(usbDevice, &propertyDictionaryRef, kCFAllocatorDefault, kNilOptions);
		
		if (kr == KERN_SUCCESS)
		{
			NSDictionary *propertyDictionary = (__bridge NSDictionary *)propertyDictionaryRef;
			
			locationID = propertyToUInt32([propertyDictionary objectForKey:@"locationID"]);
			devSpeed = propertyToUInt32([propertyDictionary objectForKey:@"Device Speed"]);
			vendorID = propertyToUInt32([propertyDictionary objectForKey:@"idVendor"]);
			productID = propertyToUInt32([propertyDictionary objectForKey:@"idProduct"]);
			NSNumber *appleUSBAlternateServiceRegistryID = [propertyDictionary objectForKey:@"AppleUSBAlternateServiceRegistryID"];
			
			if (appleUSBAlternateServiceRegistryID != nil)
			{
				registryID = [appleUSBAlternateServiceRegistryID unsignedLongLongValue];
				getUSBControllerInfoForUSBDevice(registryID, &controllerID, &controllerLocationID, &port);
			}
			else
				getUSBControllerInfoForUSBDevice(locationID, vendorID, productID, &controllerID, &controllerLocationID, &port);
		}
#else
		kr = IOCreatePlugInInterfaceForService(usbDevice, kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID, &plugInInterface, &score);
		
		if ((kr != kIOReturnSuccess) || !plugInInterface)
		{
			NSLog(@"IOCreatePlugInInterfaceForService failed for device '%@' (kr=0x%08x)", [NSString stringWithUTF8String:deviceName], kr);

			continue;
		}

		//kr = (*plugInInterface)->QueryInterface(plugInInterface, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID), (LPVOID*) &deviceInterface);
		kr = (*plugInInterface)->QueryInterface(plugInInterface, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID650), (LPVOID*) &deviceInterface);
		//kr = (*plugInInterface)->QueryInterface(plugInInterface, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID942), (LPVOID*) &deviceInterface);
		
		//(*plugInInterface)->Release(plugInInterface);
		IODestroyPlugInInterface(plugInInterface);
		
		if ((kr != kIOReturnSuccess) || !deviceInterface)
			continue;
		
		kr = (*deviceInterface)->GetLocationID(deviceInterface, &locationID);
		kr = (*deviceInterface)->GetDeviceSpeed(deviceInterface, &devSpeed);
#endif
		
		//MyPrivateData *privateDataRef = (MyPrivateData *)calloc(1, sizeof(MyPrivateData));
		MyPrivateData *privateDataRef = (MyPrivateData *)NSAllocateMemoryPages(sizeof(MyPrivateData));
		
		privateDataRef->deviceInterface = deviceInterface;
		privateDataRef->deviceName = CFStringCreateWithCString(kCFAllocatorDefault, deviceName, kCFStringEncodingASCII);
		privateDataRef->locationID = locationID;
		privateDataRef->controllerID = controllerID;
		privateDataRef->controllerLocationID = controllerLocationID;
		privateDataRef->port = port;
		privateDataRef->registryID = registryID;
		privateDataRef->appDelegate = appDelegate;
		
		//NSMutableDictionary *dictionary = (__bridge NSMutableDictionary *)IORegistryEntryIDMatching(registryID);
		
		//NSLog(@"%d ==> %@", registryID, dictionary);
		
		//[gDeviceArray addObject:[NSNumber numberWithUnsignedLongLong:(unsigned long long)privateDataRef]];

		//NSLog(@"deviceName: %@ controllerID: 0x%08X locationID: 0x%08X port: 0x%02X devSpeed: %d", privateDataRef->deviceName, controllerID, locationID, port, (uint32_t)devSpeed);
		
		[appDelegate addUSBDevice:controllerID controllerLocationID:controllerLocationID locationID:locationID port:port deviceName:(__bridge NSString *)privateDataRef->deviceName devSpeed:devSpeed];
		
		kr = IOServiceAddInterestNotification(gNotifyPort, usbDevice, kIOGeneralInterest, usbDeviceNotification, privateDataRef, &privateDataRef->removedIter);
	}
}

/* void usbDeviceRemoved(void *refCon, io_iterator_t iterator)
{
	for (io_service_t usbDevice; (usbDevice = IOIteratorNext(iterator)); IOObjectRelease(usbDevice));
} */

NSString *getUSBConnectorType(UsbConnector usbConnector)
{
	switch (usbConnector)
	{
		case kTypeA:
		case kMiniAB:
			return @"USB2";
		case kExpressCard:
			return @"ExpressCard";
		case kUSB3StandardA:
		case kUSB3StandardB:
		case kUSB3MicroB:
		case kUSB3MicroAB:
		case kUSB3PowerB:
			return @"USB3";
		case kTypeCUSB2Only:
		case kTypeCSSSw:
			return @"TypeC+Sw";
		case kTypeCSS:
			return @"TypeC";
		case kInternal:
			return @"Internal";
		default:
			return @"Reserved";
	}
}

NSString *getUSBConnectorSpeed(uint8_t speed)
{
	switch (speed)
	{
		case kUSBDeviceSpeedLow:
			return @"1.5 Mbps";
		case kUSBDeviceSpeedFull:
			return @"12 Mbps";
		case kUSBDeviceSpeedHigh:
			return @"480 Mbps";
		case kUSBDeviceSpeedSuper:
			return @"5 Gbps";
		case kUSBDeviceSpeedSuperPlus:
			return @"10 Gbps";
		default:
			return @"Unknown";
	}
}

void injectDefaultUSBPowerProperties(NSMutableDictionary *ioProviderMergePropertiesDictionary)
{
	[ioProviderMergePropertiesDictionary setObject:@(2100) forKey:@"kUSBSleepPortCurrentLimit"];
	[ioProviderMergePropertiesDictionary setObject:@(5100) forKey:@"kUSBSleepPowerSupply"];
	[ioProviderMergePropertiesDictionary setObject:@(2100) forKey:@"kUSBWakePortCurrentLimit"];
	[ioProviderMergePropertiesDictionary setObject:@(5100) forKey:@"kUSBWakePowerSupply"];
}

bool injectUSBPowerProperties(AppDelegate *appDelegate, uint32_t controllerLocationID, bool isHub, NSMutableDictionary *ioProviderMergePropertiesDictionary)
{
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSString *ioUSBHostPath1 = @"/System/Library/Extensions/IOUSBHostFamily.kext/Contents/PlugIns/AppleUSBHostPlatformProperties.kext/Contents/Info.plist";
	NSString *ioUSBHostPath2 = @"/System/Library/Extensions/IOUSBHostFamily.kext/Contents/Info.plist";
	NSDictionary *ioUSBHostIOProviderMergePropertiesDictionary = nil;

	if ([fileManager fileExistsAtPath:ioUSBHostPath1])
	{
		NSDictionary *ioUSBHostInfoDictionary = [NSDictionary dictionaryWithContentsOfFile:ioUSBHostPath1];
		NSDictionary *ioUSBHostIOKitPersonalities = [ioUSBHostInfoDictionary objectForKey:@"IOKitPersonalities_x86_64"];
		NSMutableArray *sortedKeys = [[[ioUSBHostIOKitPersonalities allKeys] mutableCopy] autorelease];
		NSDictionary *ioUSBHostIOKitPersonalityDictionary = nil;
		NSString *nearestModelIdentifier = nil;
		[sortedKeys sortUsingSelector:@selector(compare:)];
		sortedKeys = [[[[sortedKeys reverseObjectEnumerator] allObjects] mutableCopy] autorelease];
		
		for (NSString *key in sortedKeys)
		{
			// iMac13,1
			// iMac13,1-EHC1
			// iMac13,1-EHC2
			// iMac13,1-InternalHub-EHC1
			// iMac13,1-InternalHub-EHC1-InternalHub
			// iMac13,1-XHC1
			NSArray *keyArray = [key componentsSeparatedByString:@"-"];
			NSString *model = nil;
			NSString *controllerName = nil;
			bool isControllerHub = false;
			
			if ([keyArray count] == 1)
				model = keyArray[0];
			else if ([keyArray count] == 2)
			{
				model = keyArray[0];
				controllerName = keyArray[1];
			}
			else if ([keyArray count] >= 3)
			{
				model = keyArray[0];
				controllerName = keyArray[2];
				isControllerHub = true;
			}
			
			bool isHubMatch = (isControllerHub == isHub);
			bool isModelMatch = [appDelegate.modelIdentifier isEqualToString:model];
			
			if (controllerName != nil)
			{
				if (isHubMatch && isModelMatch && isControllerLocationXHC(controllerLocationID) && isControllerNameXHC(controllerName))
				{
					ioUSBHostIOKitPersonalityDictionary = [ioUSBHostIOKitPersonalities objectForKey:key];
					break;
				}
				else if (isHubMatch && isModelMatch && isControllerLocationEH1(controllerLocationID) && isControllerNameEH1(controllerName))
				{
					ioUSBHostIOKitPersonalityDictionary = [ioUSBHostIOKitPersonalities objectForKey:key];
					break;
				}
				else if (isHubMatch && isModelMatch && isControllerLocationEH2(controllerLocationID) && isControllerNameEH2(controllerName))
				{
					ioUSBHostIOKitPersonalityDictionary = [ioUSBHostIOKitPersonalities objectForKey:key];
					break;
				}
			}
			else
			{
				if (isModelMatch)
				{
					ioUSBHostIOKitPersonalityDictionary = [ioUSBHostIOKitPersonalities objectForKey:key];
					break;
				}
			}
		}
		
		if (ioUSBHostIOKitPersonalityDictionary == nil)
		{
			if ([appDelegate tryGetNearestModel:[ioUSBHostIOKitPersonalities allKeys] modelIdentifier:appDelegate.modelIdentifier nearestModelIdentifier:&nearestModelIdentifier])
				ioUSBHostIOKitPersonalityDictionary = [ioUSBHostIOKitPersonalities objectForKey:nearestModelIdentifier];
		}

		if (ioUSBHostIOKitPersonalityDictionary != nil)
			ioUSBHostIOProviderMergePropertiesDictionary = [ioUSBHostIOKitPersonalityDictionary objectForKey:@"IOProviderMergeProperties"];
	}
	else if ([fileManager fileExistsAtPath:ioUSBHostPath2])
	{
		NSDictionary *ioUSBHostInfoDictionary = [NSDictionary dictionaryWithContentsOfFile:ioUSBHostPath2];
		NSDictionary *ioUSBHostIOKitPersonalities = [ioUSBHostInfoDictionary objectForKey:@"IOKitPersonalities"];
		NSString *nearestModelIdentifier = nil;
		
		if ([appDelegate tryGetNearestModel:[ioUSBHostIOKitPersonalities allKeys] modelIdentifier:appDelegate.modelIdentifier nearestModelIdentifier:&nearestModelIdentifier])
		{
			NSDictionary *ioUSBHostIOKitPersonalityDictionary = [ioUSBHostIOKitPersonalities objectForKey:nearestModelIdentifier];
			ioUSBHostIOProviderMergePropertiesDictionary = [ioUSBHostIOKitPersonalityDictionary objectForKey:@"IOProviderMergeProperties"];
		}
	}
	
	if (ioUSBHostIOProviderMergePropertiesDictionary == nil)
		return false;

	NSNumber *sleepPortCurrentLimit = [ioUSBHostIOProviderMergePropertiesDictionary objectForKey:@"kUSBSleepPortCurrentLimit"];
	NSNumber *sleepPowerSupply = [ioUSBHostIOProviderMergePropertiesDictionary objectForKey:@"kUSBSleepPowerSupply"];
	NSNumber *wakePortCurrentLimit = [ioUSBHostIOProviderMergePropertiesDictionary objectForKey:@"kUSBWakePortCurrentLimit"];
	NSNumber *wakePowerSupply = [ioUSBHostIOProviderMergePropertiesDictionary objectForKey:@"kUSBWakePowerSupply"];
	//NSNumber *usbMuxEnabled = [ioUSBHostIOProviderMergePropertiesDictionary objectForKey:@"kUSBMuxEnabled"];
	
	if (sleepPortCurrentLimit == nil || sleepPowerSupply == nil || wakePortCurrentLimit == nil || wakePowerSupply == nil)
		return false;
	
	[ioProviderMergePropertiesDictionary setObject:sleepPortCurrentLimit forKey:@"kUSBSleepPortCurrentLimit"];
	[ioProviderMergePropertiesDictionary setObject:sleepPowerSupply forKey:@"kUSBSleepPowerSupply"];
	[ioProviderMergePropertiesDictionary setObject:wakePortCurrentLimit forKey:@"kUSBWakePortCurrentLimit"];
	[ioProviderMergePropertiesDictionary setObject:wakePowerSupply forKey:@"kUSBWakePowerSupply"];
		
	return true;
}

void injectUSBControllerProperties(AppDelegate *appDelegate, NSMutableDictionary *ioKitPersonalities, uint32_t usbControllerID)
{
	// AppleUSBXHCISPT
	// AppleUSBXHCISPT1
	// AppleUSBXHCISPT2
	// AppleUSBXHCISPT3
	// AppleUSBXHCISPT3
	
	// Haswell:
	// AppleUSBXHCILPTHB iMac14,2
	// CFBundleIdentifier		com.apple.driver.usb.AppleUSBXHCIPCI
	// IOClass					AppleUSBXHCILPTHB
	// IOPCIPrimaryMatch		0x8cb18086
	// IOPCIPauseCompatible		YES
	// IOPCITunnelCompatible	YES
	// IOProviderClass			IOPCIDevice
	// IOProbeScore				5000
	//
	// Skylake:
	// AppleUSBXHCISPT1 iMac17,1
	// CFBundleIdentifier		com.apple.driver.usb.AppleUSBXHCIPCI
	// IOClass					AppleUSBXHCISPT1
	// IOPCIPrimaryMatch		0xa12f8086
	// IOPCIPauseCompatible		YES
	// IOPCITunnelCompatible	YES
	// IOProviderClass			IOPCIDevice
	// IOProbeScore				5000
	
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSString *ioUSBHostPlugInsPath = @"/System/Library/Extensions/IOUSBHostFamily.kext/Contents/PlugIns/AppleUSBXHCIPCI.kext/Contents/Info.plist";
	
	if (![fileManager fileExistsAtPath:ioUSBHostPlugInsPath])
		return;
	
	NSDictionary *ioUSBHostInfoDictionary = [NSDictionary dictionaryWithContentsOfFile:ioUSBHostPlugInsPath];
	NSDictionary *ioUSBHostIOKitPersonalities = [ioUSBHostInfoDictionary objectForKey:@"IOKitPersonalities"];
	NSString *usbControllerIDString = [NSString stringWithFormat:@"0x%08x", usbControllerID];
	
	for (NSString *key in ioUSBHostIOKitPersonalities.allKeys)
	{
		NSMutableDictionary *ioUSBDictionary = [[[ioUSBHostIOKitPersonalities objectForKey:key] mutableCopy] autorelease];
		NSString *ioPCIPrimaryMatch = [ioUSBDictionary objectForKey:@"IOPCIPrimaryMatch"];
		
		if (ioPCIPrimaryMatch == nil)
			continue;
		
		if ([ioPCIPrimaryMatch rangeOfString:usbControllerIDString options:NSCaseInsensitiveSearch].location == NSNotFound)
			continue;
		
		[ioUSBDictionary setObject:@(5000) forKey:@"IOProbeScore"];
		
		[ioKitPersonalities setObject:ioUSBDictionary forKey:[NSString stringWithFormat:@"%@ %@", key, appDelegate.modelIdentifier]];
	}
}

bool getECName(AppDelegate *appDelegate, NSString **ecName)
{
	io_iterator_t iterator;
	
	kern_return_t kr = IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching("IOACPIPlatformDevice"), &iterator);
	
	if (kr != KERN_SUCCESS)
		return false;
	
	for (io_service_t device; IOIteratorIsValid(iterator) && (device = IOIteratorNext(iterator)); IOObjectRelease(device))
	{
		io_name_t name {};
		kr = IORegistryEntryGetName(device, name);
		
		if (kr != KERN_SUCCESS)
			continue;
		
		if ([[NSString stringWithUTF8String:name] isEqualToString:@"EC"])
			continue;
		
		CFMutableDictionaryRef propertyDictionaryRef = 0;
		
		kr = IORegistryEntryCreateCFProperties(device, &propertyDictionaryRef, kCFAllocatorDefault, kNilOptions);
		
		if (kr != KERN_SUCCESS)
			continue;
		
		NSMutableDictionary *propertyDictionary = (__bridge NSMutableDictionary *)propertyDictionaryRef;
		
		NSData *propertyValue = [propertyDictionary objectForKey:@"name"];
		
		if (propertyValue == nil)
			continue;
		
		NSString *nameEntry = [NSString stringWithCString:(const char *)[propertyValue bytes] encoding:NSASCIIStringEncoding];
		
		if ([nameEntry isEqualToString:@"PNP0C09"])
		{
			*ecName = [NSString stringWithUTF8String:name];
			
			IOObjectRelease(iterator);
			IOObjectRelease(device);
			
			return true;
		}
	}
	
	IOObjectRelease(iterator);
	
	return false;
}

ECType checkEC(AppDelegate *appDelegate)
{
	// An EC device is needed so AppleBusPowerController attaches to it and injects
	// correct power properties to XHC/EHCx in Mojave and older. In Catalina
	// (as of now and probably higher), an EC device is needed for booting,
	// and AppleBusPowerController loads if IORTC is found and then attaches to IOResources.
	// - whatnameisit
	
	NSOperatingSystemVersion minimumSupportedOSVersion = { .majorVersion = 10, .minorVersion = 15, .patchVersion = 0 };
	BOOL isOSAtLeastCatalina = [NSProcessInfo.processInfo isOperatingSystemAtLeastVersion:minimumSupportedOSVersion];
	
	if (isOSAtLeastCatalina)
		return kECNoSSDTRequired;
	
	// https://github.com/corpnewt/USBMap/blob/master/USBMap.command
	//
	// Let's look for a couple of things
	// 1. We check for the existence of AppleBusPowerController in ioreg -> IOService
	//    If it exists, then we don't need any SSDT or renames
	// 2. We want to see if we have ECDT in ACPI and if so, we force a fake EC SSDT
	//    as renames and such can interfere
	// 3. We check for EC, EC0, H_EC, or ECDV in ioreg - and if found, we check
	//    if the _STA is 0 or not - if it's not 0, and not EC, we prompt for a rename
	//    We match that against the PNP0C09 name in ioreg
	
	if (hasIORegEntry(@"IOService:/AppleACPIPlatformExpert/EC/AppleBusPowerController"))
		return kECNoSSDTRequired;
	
	// At this point - we know AppleBusPowerController isn't loaded - let's look at renames and such
	// Check for ECDT in ACPI - if this is present, all bets are off
	// and we need to avoid any EC renames and such
	
	if (appDelegate.bootLog != nil)
	{
		NSRange startString = [appDelegate.bootLog rangeOfString:@"GetAcpiTablesList"];
		NSRange endString = [appDelegate.bootLog rangeOfString:@"GetUserSettings"];
		NSRange stringRange = NSMakeRange(startString.location + startString.length, endString.location - startString.location - startString.length);
		NSString *acpiString = [appDelegate.bootLog substringWithRange:stringRange];
		
		if ([acpiString containsString:@"ECDT"])
			return kECSSDTRequired;
	}
	
	NSArray *usbACPIArray = @[@"EC", @"EC0", @"H_EC", @"ECDV"];
	
	for (int i = 0; i < [usbACPIArray count]; i++)
	{
		NSMutableDictionary *acpiDictionary = nil;
		
		if (!getIORegProperties([NSString stringWithFormat:@"IOService:/AppleACPIPlatformExpert/%@", [usbACPIArray objectAtIndex:i]], &acpiDictionary))
			continue;
		
		NSData *propertyValue = [acpiDictionary objectForKey:@"name"];
		NSString *name = [NSString stringWithCString:(const char *)[propertyValue bytes] encoding:NSASCIIStringEncoding];
		NSNumber *_sta = [acpiDictionary objectForKey:@"_STA"];
		
		if ([name isEqualToString:@"PNP0C09"] && [_sta unsignedIntValue] == 0)
			return kECSSDTRequired;
		
		return (ECType)i;
	}
	
	// If we got here, then we didn't find EC, and didn't need to rename it
	// so we return 0 to prompt for an EC fake SSDT to be made
	return kECSSDTRequired;
}

void validateUSBPower(AppDelegate *appDelegate)
{
	NSBundle *mainBundle = [NSBundle mainBundle];
	NSString *iaslPath = [mainBundle pathForResource:@"iasl" ofType:@"" inDirectory:@"Utilities"];
	NSString *ssdtECPath = [mainBundle pathForResource:@"SSDT-EC" ofType:@"dsl" inDirectory:@"ACPI"];
	NSString *desktopPath = [NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES) objectAtIndex:0];
	NSString *stdoutString = nil;
	
	ECType retVal = checkEC(appDelegate);
	
	switch(retVal)
	{
		case kECSSDTRequired:
			if ([appDelegate showAlert:@"SSDT-EC Required" text:@"Generating SSDT-EC..."])
			{
				launchCommand(iaslPath, @[@"-p", [NSString stringWithFormat:@"%@/SSDT-EC.aml", desktopPath], ssdtECPath], &stdoutString);
				//NSLog(@"%@", stdoutString);
			}
			break;
		case kECRenameEC0toEC:
		{
			if ([appDelegate showAlert:@"Rename Required" text:@"Renaming EC0 to EC..."])
			{
				NSMutableDictionary *configDictionary = nil;
				NSString *configPath = nil;
				
				if (![Config openConfig:appDelegate configDictionary:&configDictionary configPath:&configPath])
					break;
				
				if ([appDelegate isBootloaderOpenCore])
				{
					NSMutableDictionary *acpiDSDTDictionary = [OpenCore createACPIDSDTDictionaryWithFind:@"EC0_" replace:@"EC__"];
					[OpenCore addACPIDSDTPatchWith:configDictionary patchDictionary:acpiDSDTDictionary];
					[configDictionary writeToFile:configPath atomically:YES];
				}
				else
				{
					NSMutableDictionary *acpiDSDTDictionary = [Clover createACPIDSDTDictionaryWithFind:@"EC0_" replace:@"EC__"];
					[Clover addACPIDSDTPatchWith:configDictionary patchDictionary:acpiDSDTDictionary];
					[configDictionary writeToFile:configPath atomically:YES];
				}
			}
			break;
		}
		case kECRenameH_ECtoEC:
		{
			if ([appDelegate showAlert:@"Rename Required" text:@"Renaming H_EC to EC..."])
			{
				NSMutableDictionary *configDictionary = nil;
				NSString *configPath = nil;
				
				if (![Config openConfig:appDelegate configDictionary:&configDictionary configPath:&configPath])
					break;
				
				if ([appDelegate isBootloaderOpenCore])
				{
					NSMutableDictionary *acpiDSDTDictionary = [OpenCore createACPIDSDTDictionaryWithFind:@"H_EC" replace:@"EC__"];
					[OpenCore addACPIDSDTPatchWith:configDictionary patchDictionary:acpiDSDTDictionary];
					[configDictionary writeToFile:configPath atomically:YES];
				}
				else
				{
					NSMutableDictionary *acpiDSDTDictionary = [Clover createACPIDSDTDictionaryWithFind:@"H_EC" replace:@"EC__"];
					[Clover addACPIDSDTPatchWith:configDictionary patchDictionary:acpiDSDTDictionary];
					[configDictionary writeToFile:configPath atomically:YES];
				}
			}
			break;
		}
		case kECRenameECDVtoEC:
		{
			if ([appDelegate showAlert:@"Rename Required" text:@"Renaming ECDV to EC..."])
			{
				NSMutableDictionary *configDictionary = nil;
				NSString *configPath = nil;
				
				if (![Config openConfig:appDelegate configDictionary:&configDictionary configPath:&configPath])
					break;
				
				if ([appDelegate isBootloaderOpenCore])
				{
					NSMutableDictionary *acpiDSDTDictionary = [OpenCore createACPIDSDTDictionaryWithFind:@"ECDV" replace:@"EC__"];
					[OpenCore addACPIDSDTPatchWith:configDictionary patchDictionary:acpiDSDTDictionary];
					[configDictionary writeToFile:configPath atomically:YES];
				}
				else
				{
					NSMutableDictionary *acpiDSDTDictionary = [Clover createACPIDSDTDictionaryWithFind:@"ECDV" replace:@"EC__"];
					[Clover addACPIDSDTPatchWith:configDictionary patchDictionary:acpiDSDTDictionary];
					[configDictionary writeToFile:configPath atomically:YES];
				}
			}
			break;
		}
		case kECNoSSDTRequired:
			NSLog(@"No SSDT-EC Required");
			break;
	}
}

void addUSBDictionary(AppDelegate *appDelegate, NSMutableDictionary *ioKitPersonalities)
{
	NSMutableDictionary *maxPortDictionary = [NSMutableDictionary dictionary];
	
	for (NSMutableDictionary *usbEntryDictionary in appDelegate.usbPortsArray)
	{
		NSMutableDictionary *newUSBEntryDictionary = [[usbEntryDictionary mutableCopy] autorelease];
		NSString *name = [usbEntryDictionary objectForKey:@"name"];
		NSString *usbController = [usbEntryDictionary objectForKey:@"UsbController"];
		uint32_t usbControllerID = propertyToUInt32([usbEntryDictionary objectForKey:@"UsbControllerID"]);
		uint32_t usbControllerLocationID = propertyToUInt32([usbEntryDictionary objectForKey:@"UsbControllerLocationID"]);
		uint32_t vendorID = (usbControllerID & 0xFFFF);
		uint32_t deviceID = (usbControllerID >> 16);
		NSString *deviceName = (usbControllerID != 0 ? [NSString stringWithFormat:@"%04x_%04x", vendorID, deviceID] : @"???");

		if (usbController == nil)
			continue;
		
		uint32_t port = propertyToUInt32([usbEntryDictionary objectForKey:@"port"]);
		NSString *hubName = [usbEntryDictionary objectForKey:@"HubName"];
		bool isHub = (hubName != nil);
		NSNumber *hubLocation = [usbEntryDictionary objectForKey:@"HubLocation"];
		NSString *modelEntryName = [NSString stringWithFormat:@"%@-%@", appDelegate.modelIdentifier, usbController];
		NSString *providerClass = (isHub ? hubName : [usbEntryDictionary objectForKey:@"UsbControllerIOClass"]);
		
		// For hub's we'll append "-internal-hub"
		if (isHub)
			modelEntryName = [modelEntryName stringByAppendingString:@"-internal-hub"];
		// For unknown controllers we'll append "-VID_PID"
		else if (isControllerNameXHC(usbController) && !isControllerLocationXHC(usbControllerLocationID))
			modelEntryName = [modelEntryName stringByAppendingFormat:@"-%@", deviceName];
		else if (isControllerNameEH1(usbController) && !isControllerLocationEH1(usbControllerLocationID))
			modelEntryName = [modelEntryName stringByAppendingFormat:@"-%@", deviceName];
		else if (isControllerNameEH2(usbController) && !isControllerLocationEH2(usbControllerLocationID))
			modelEntryName = [modelEntryName stringByAppendingFormat:@"-%@", deviceName];
		
		if (providerClass == nil)
		{
			if (isControllerNameXHC(usbController))
				providerClass = @"AppleUSBXHCIPCI";
			else if (isControllerNameEH1(usbController) || isControllerNameEH2(usbController))
				providerClass = @"AppleUSBEHCIPCI";
		}
		
		NSMutableDictionary *modelEntryDictionary = [ioKitPersonalities objectForKey:modelEntryName];
		NSMutableDictionary *ioProviderMergePropertiesDictionary = nil;
		NSMutableDictionary *portsDictionary = nil;
		
		if (modelEntryDictionary == nil)
		{
			modelEntryDictionary =  [NSMutableDictionary dictionary];
			ioProviderMergePropertiesDictionary = [NSMutableDictionary dictionary];
			portsDictionary = [NSMutableDictionary dictionary];
			
			[ioKitPersonalities setObject:modelEntryDictionary forKey:modelEntryName];
			[modelEntryDictionary setObject:ioProviderMergePropertiesDictionary forKey:@"IOProviderMergeProperties"];
			[ioProviderMergePropertiesDictionary setObject:portsDictionary forKey:@"ports"];
			
			// For HUB's
			if (isHub)
			{
				[modelEntryDictionary setObject:@"com.apple.driver.AppleUSBHostMergeProperties" forKey:@"CFBundleIdentifier"];
				[modelEntryDictionary setObject:@"AppleUSBHostMergeProperties" forKey:@"IOClass"];
				[modelEntryDictionary setObject:providerClass forKey:@"IOProviderClass"];
				
				// Inject model instead
				/* NSMutableDictionary *platformDictionary;
				
				if (getIORegProperties(@"IODeviceTree:/", &platformDictionary))
					[modelEntryDictionary setObject:properyToString([platformDictionary objectForKey:@"board-id"]) forKey:@"board-id"]; */
				
				[modelEntryDictionary setObject:hubLocation forKey:@"locationID"];
			}
			else
			{
				if (!injectUSBPowerProperties(appDelegate, usbControllerLocationID, isHub, ioProviderMergePropertiesDictionary))
					injectDefaultUSBPowerProperties(ioProviderMergePropertiesDictionary);
				
				[modelEntryDictionary setObject:@"com.apple.driver.AppleUSBMergeNub" forKey:@"CFBundleIdentifier"];
				[modelEntryDictionary setObject:@"AppleUSBMergeNub" forKey:@"IOClass"];
				
				if (usbControllerID != 0)
					[modelEntryDictionary setObject:[NSString stringWithFormat:@"0x%08x", usbControllerID] forKey:@"IOPCIPrimaryMatch"];
				
				[modelEntryDictionary setObject:usbController forKey:@"IONameMatch"];
				[modelEntryDictionary setObject:providerClass forKey:@"IOProviderClass"];
			}
			
			[modelEntryDictionary setObject:appDelegate.modelIdentifier forKey:@"model"];
			[modelEntryDictionary setObject:@(5000) forKey:@"IOProbeScore"];
			[modelEntryDictionary setObject:usbController forKey:@"UsbController"];
			[modelEntryDictionary setObject:@(usbControllerID) forKey:@"UsbControllerID"];
			[modelEntryDictionary setObject:@(usbControllerLocationID) forKey:@"UsbControllerLocationID"];
			
			//injectUSBControllerProperties(appDelegate, ioKitPersonalities, usbControllerID);
		}
		else
		{
			ioProviderMergePropertiesDictionary = [modelEntryDictionary objectForKey:@"IOProviderMergeProperties"];
			portsDictionary = [ioProviderMergePropertiesDictionary objectForKey:@"ports"];
		}
		
		uint32_t maxPort = [maxPortDictionary[modelEntryName] unsignedIntValue];
		maxPort = MAX(maxPort, port);
		
		maxPortDictionary[modelEntryName] = [NSNumber numberWithInt:maxPort];
		
		NSData *maxPortData = [NSData dataWithBytes:&maxPort length:sizeof(maxPort)];
		
		[ioProviderMergePropertiesDictionary setObject:maxPortData forKey:@"port-count"];
		
		[portsDictionary setObject:newUSBEntryDictionary forKey:name];
	}
}

void exportUSBPowerSSDT(AppDelegate *appDelegate)
{
	NSMutableString *ssdtUSBXString = [NSMutableString string];
	
	[ssdtUSBXString appendString:@"DefinitionBlock (\"\", \"SSDT\", 2, \"ACDT\", \"SsdtEC\", 0)\n"];
	[ssdtUSBXString appendString:@"{\n"];
	[ssdtUSBXString appendString:@"    External (_SB_.PCI0.LPCB, DeviceObj)\n"];
	
	NSString *ecName = nil;
	
	if (getECName(appDelegate, &ecName))
	{
		[ssdtUSBXString appendFormat:@"    External (_SB_.PCI0.LPCB.%@, DeviceObj)\n", ecName];
		[ssdtUSBXString appendString:@"\n"];
		[ssdtUSBXString appendFormat:@"    Scope (\\_SB.PCI0.LPCB.%@)\n", ecName];
		[ssdtUSBXString appendString:@"    {\n"];
		[ssdtUSBXString appendString:@"        Method (_STA, 0, NotSerialized)  // _STA: Status\n"];
		[ssdtUSBXString appendString:@"        {\n"];
		[ssdtUSBXString appendString:@"            If (_OSI (\"Darwin\"))\n"];
		[ssdtUSBXString appendString:@"            {\n"];
		[ssdtUSBXString appendString:@"                Return (0)\n"];
		[ssdtUSBXString appendString:@"            }\n"];
		[ssdtUSBXString appendString:@"            Else\n"];
		[ssdtUSBXString appendString:@"            {\n"];
		[ssdtUSBXString appendString:@"                Return (0x0F)\n"];
		[ssdtUSBXString appendString:@"            }\n"];
		[ssdtUSBXString appendString:@"        }\n"];
		[ssdtUSBXString appendString:@"    }\n"];
	}
	
	[ssdtUSBXString appendString:@"\n"];
	[ssdtUSBXString appendString:@"    Scope (\\_SB)\n"];
	[ssdtUSBXString appendString:@"    {\n"];
	
	[ssdtUSBXString appendString:@"        Device (USBX)\n"];
	[ssdtUSBXString appendString:@"        {\n"];
	[ssdtUSBXString appendString:@"            Name (_ADR, Zero)  // _ADR: Address\n"];
	[ssdtUSBXString appendString:@"            Method (_DSM, 4, NotSerialized)  // _DSM: Device-Specific Method\n"];
	[ssdtUSBXString appendString:@"            {\n"];
	[ssdtUSBXString appendString:@"                If ((Arg2 == Zero))\n"];
	[ssdtUSBXString appendString:@"                {\n"];
	[ssdtUSBXString appendString:@"                    Return (Buffer (One)\n"];
	[ssdtUSBXString appendString:@"                    {\n"];
	[ssdtUSBXString appendString:@"                         0x03                                             // .\n"];
	[ssdtUSBXString appendString:@"                    })\n"];
	[ssdtUSBXString appendString:@"                }\n"];
	[ssdtUSBXString appendString:@"\n"];
	[ssdtUSBXString appendString:@"                Return (Package (0x08)\n"];
	[ssdtUSBXString appendString:@"                {\n"];
	[ssdtUSBXString appendString:@"                    \"kUSBSleepPowerSupply\",\n"];
	[ssdtUSBXString appendString:@"                    0x13EC,\n"];
	[ssdtUSBXString appendString:@"                    \"kUSBSleepPortCurrentLimit\",\n"];
	[ssdtUSBXString appendString:@"                    0x0834,\n"];
	[ssdtUSBXString appendString:@"                    \"kUSBWakePowerSupply\",\n"];
	[ssdtUSBXString appendString:@"                    0x13EC,\n"];
	[ssdtUSBXString appendString:@"                    \"kUSBWakePortCurrentLimit\",\n"];
	[ssdtUSBXString appendString:@"                    0x0834\n"];
	[ssdtUSBXString appendString:@"                })\n"];
	[ssdtUSBXString appendString:@"            }\n"];
	[ssdtUSBXString appendString:@"        }\n"];
	
	[ssdtUSBXString appendString:@"\n"];
	
	NSOperatingSystemVersion minimumSupportedOSVersion = { .majorVersion = 10, .minorVersion = 15, .patchVersion = 0 };
	BOOL isOSAtLeastCatalina = [NSProcessInfo.processInfo isOperatingSystemAtLeastVersion:minimumSupportedOSVersion];
	
	if (!isOSAtLeastCatalina)
	{
		[ssdtUSBXString appendString:@"        Scope (\\_SB.PCI0.LPCB)\n"];
		[ssdtUSBXString appendString:@"        {\n"];
		[ssdtUSBXString appendString:@"            Device (EC)\n"];
		[ssdtUSBXString appendString:@"            {\n"];
		[ssdtUSBXString appendString:@"                Name (_HID, \"ACID0001\")  // _HID: Hardware ID\n"];
		[ssdtUSBXString appendString:@"                Method (_STA, 0, NotSerialized)  // _STA: Status\n"];
		[ssdtUSBXString appendString:@"                {\n"];
		[ssdtUSBXString appendString:@"                    If (_OSI (\"Darwin\"))\n"];
		[ssdtUSBXString appendString:@"                    {\n"];
		[ssdtUSBXString appendString:@"                        Return (0x0F)\n"];
		[ssdtUSBXString appendString:@"                    }\n"];
		[ssdtUSBXString appendString:@"                    Else\n"];
		[ssdtUSBXString appendString:@"                    {\n"];
		[ssdtUSBXString appendString:@"                        Return (Zero)\n"];
		[ssdtUSBXString appendString:@"                    }\n"];
		[ssdtUSBXString appendString:@"                }\n"];
		[ssdtUSBXString appendString:@"            }\n"];
		[ssdtUSBXString appendString:@"        }\n"];
	}
	
	[ssdtUSBXString appendString:@"    }\n"];
	[ssdtUSBXString appendString:@"}\n"];

	NSBundle *mainBundle = [NSBundle mainBundle];
	NSString *iaslPath = [mainBundle pathForResource:@"iasl" ofType:@"" inDirectory:@"Utilities"];
	NSString *desktopPath = [NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES) objectAtIndex:0];
	NSString *tempFilePath = [NSString stringWithFormat:@"%@/SSDT-EC-USBX.dsl", desktopPath];
	NSString *outputFilePath = [NSString stringWithFormat:@"%@/SSDT-EC-USBX.aml", desktopPath];
	NSString *stdoutString = nil;
	
	if ([[NSFileManager defaultManager] fileExistsAtPath:tempFilePath])
		[[NSFileManager defaultManager] removeItemAtPath:tempFilePath error:nil];
	
	NSError *error;
	
	[ssdtUSBXString writeToFile:tempFilePath atomically:YES encoding:NSUTF8StringEncoding error:&error];
	
	launchCommand(iaslPath, @[@"-p", outputFilePath, tempFilePath], &stdoutString);
	
	NSArray *fileURLs = [NSArray arrayWithObjects:[NSURL fileURLWithPath:outputFilePath], nil];
	[[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:fileURLs];
}

void exportUSBPortsKext(AppDelegate *appDelegate)
{
	// XHC
	//	IONameMatch: XHC
	//	IOProviderClass: AppleUSBXHCIPCI
	//	CFBundleIdentifier: com.apple.driver.AppleUSBHostMergeProperties
	//	# kConfigurationName: XHC
	//	# kIsXHC: True
	// EH01
	//	IONameMatch: EH01
	//	IOProviderClass: AppleUSBEHCIPCI
	//	CFBundleIdentifier: com.apple.driver.AppleUSBHostMergeProperties
	//	# kConfigurationName: EH01
	// EH02
	//	IONameMatch: EH02
	//	IOProviderClass: AppleUSBEHCIPCI
	//	CFBundleIdentifier: com.apple.driver.AppleUSBHostMergeProperties
	//	# kConfigurationName: EH02
	
	NSMutableDictionary *infoDictionary = [NSMutableDictionary dictionary];
	NSMutableDictionary *ioKitPersonalities = [NSMutableDictionary dictionary];
	
	[infoDictionary setObject:@"English" forKey:@"CFBundleDevelopmentRegion"];
	[infoDictionary setObject:@"1.0 Copyright © 2018-2020 Headsoft. All rights reserved." forKey:@"CFBundleGetInfoString"];
	[infoDictionary setObject:@"com.Headsoft.USBPorts" forKey:@"CFBundleIdentifier"];
	[infoDictionary setObject:@"6.0" forKey:@"CFBundleInfoDictionaryVersion"];
	[infoDictionary setObject:@"USBPorts" forKey:@"CFBundleName"];
	[infoDictionary setObject:@"KEXT" forKey:@"CFBundlePackageType"];
	[infoDictionary setObject:@"1.0" forKey:@"CFBundleShortVersionString"];
	[infoDictionary setObject:@"????" forKey:@"CFBundleSignature"];
	[infoDictionary setObject:@"1.0" forKey:@"CFBundleVersion"];
	[infoDictionary setObject:@"Root" forKey:@"OSBundleRequired"];
	
	[infoDictionary setObject:ioKitPersonalities forKey:@"IOKitPersonalities"];
	
	addUSBDictionary(appDelegate, ioKitPersonalities);
	
	for (NSString *ioKitKey in [ioKitPersonalities allKeys])
	{
		NSMutableDictionary *modelEntryDictionary = [ioKitPersonalities objectForKey:ioKitKey];
		NSMutableDictionary *ioProviderMergePropertiesDictionary = [modelEntryDictionary objectForKey:@"IOProviderMergeProperties"];
		NSMutableDictionary *portsDictionary = [ioProviderMergePropertiesDictionary objectForKey:@"ports"];
		
		[modelEntryDictionary removeObjectForKey:@"UsbController"];
		[modelEntryDictionary removeObjectForKey:@"UsbControllerID"];
		[modelEntryDictionary removeObjectForKey:@"UsbControllerLocationID"];
		[modelEntryDictionary removeObjectForKey:@"UsbControllerIOClass"];

		for (NSString *portKey in [portsDictionary allKeys])
		{
			NSMutableDictionary *usbEntryDictionary = [portsDictionary objectForKey:portKey];
			
			//[usbEntryDictionary removeObjectForKey:@"name"];
			[usbEntryDictionary removeObjectForKey:@"locationID"];
			[usbEntryDictionary removeObjectForKey:@"Device"];
			[usbEntryDictionary removeObjectForKey:@"IsActive"];
			[usbEntryDictionary removeObjectForKey:@"UsbController"];
			[usbEntryDictionary removeObjectForKey:@"UsbControllerID"];
			[usbEntryDictionary removeObjectForKey:@"UsbControllerLocationID"];
			[usbEntryDictionary removeObjectForKey:@"UsbControllerIOClass"];
			[usbEntryDictionary removeObjectForKey:@"HubName"];
			[usbEntryDictionary removeObjectForKey:@"HubLocation"];
			[usbEntryDictionary removeObjectForKey:@"DevSpeed"];
			//[usbEntryDictionary removeObjectForKey:@"Comment"];
		}
	}
	
	NSString *desktopPath = [NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES) objectAtIndex:0];
	NSString *destFilePath = [NSString stringWithFormat:@"%@/USBPorts.kext", desktopPath];
	
	if ([[NSFileManager defaultManager] fileExistsAtPath:destFilePath])
		[[NSFileManager defaultManager] removeItemAtPath:destFilePath error:nil];
	
	NSError *error;
	
	if(![[NSFileManager defaultManager] createDirectoryAtPath:[NSString stringWithFormat:@"%@/USBPorts.kext/Contents", desktopPath] withIntermediateDirectories:YES attributes:nil error:&error])
		return;
	
	NSString *outputInfoPath = [NSString stringWithFormat:@"%@/USBPorts.kext/Contents/Info.plist", desktopPath];
	[infoDictionary writeToFile:outputInfoPath atomically:YES];
	
	NSArray *fileURLs = [NSArray arrayWithObjects:[NSURL fileURLWithPath:destFilePath], nil];
	[[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:fileURLs];
}

void exportUSBPortsSSDT(AppDelegate *appDelegate)
{
	NSMutableDictionary *ioKitPersonalities = [NSMutableDictionary dictionary];
	NSMutableString *ssdtUIACString = [NSMutableString string];
	
	addUSBDictionary(appDelegate, ioKitPersonalities);
	
	[ssdtUIACString appendString:@"DefinitionBlock (\"\", \"SSDT\", 2, \"ACDT\", \"_UIAC\", 0)\n"];
	[ssdtUIACString appendString:@"{\n"];
	[ssdtUIACString appendString:@"    Device(UIAC)\n"];
	[ssdtUIACString appendString:@"    {\n"];
	[ssdtUIACString appendString:@"        Name(_HID, \"UIA00000\")\n"];
	[ssdtUIACString appendString:@"\n"];
	[ssdtUIACString appendString:@"        Name(RMCF, Package()\n"];
	[ssdtUIACString appendString:@"        {\n"];

	for (NSString *ioKitKey in [ioKitPersonalities allKeys])
	{
		NSMutableDictionary *modelEntryDictionary = [ioKitPersonalities objectForKey:ioKitKey];
		NSString *usbController = [modelEntryDictionary objectForKey:@"UsbController"];
		
		if (usbController == nil)
			continue;
		
		uint32_t usbControllerID = propertyToUInt32([modelEntryDictionary objectForKey:@"UsbControllerID"]);
		uint32_t usbControllerLocationID = propertyToUInt32([modelEntryDictionary objectForKey:@"UsbControllerLocationID"]);
		uint32_t vendorID = (usbControllerID & 0xFFFF);
		uint32_t deviceID = (usbControllerID >> 16);
		NSString *name = usbController;
		NSString *deviceName = (usbControllerID != 0 ? [NSString stringWithFormat:@"%04x_%04x", vendorID, deviceID] : @"???");
		NSNumber *locationID = [modelEntryDictionary objectForKey:@"locationID"];
		NSMutableDictionary *ioProviderMergePropertiesDictionary = [modelEntryDictionary objectForKey:@"IOProviderMergeProperties"];
		NSData *portCount = [ioProviderMergePropertiesDictionary objectForKey:@"port-count"];
		NSMutableDictionary *portsDictionary = [ioProviderMergePropertiesDictionary objectForKey:@"ports"];
		
		if (usbControllerID != 0)
		{
			// For unknown controllers we'll append VID/PID
			if (isControllerNameXHC(usbController) && !isControllerLocationXHC(usbControllerLocationID))
				name = deviceName;
			else if (isControllerNameEH1(usbController) && !isControllerLocationEH1(usbControllerLocationID))
				name = deviceName;
			else if (isControllerNameEH2(usbController) && !isControllerLocationEH2(usbControllerLocationID))
				name = deviceName;
		}
		
		if (locationID != nil)
		{
			if (isPortLocationHUB1([locationID unsignedIntValue]))
				name = @"HUB1";
			else if (isPortLocationHUB2([locationID unsignedIntValue]))
				name = @"HUB2";
		}
		
		[ssdtUIACString appendFormat:@"            // %@ (%@)\n", usbController, deviceName];
		[ssdtUIACString appendFormat:@"            \"%@\", Package()\n", name];
		[ssdtUIACString appendString:@"            {\n"];
		[ssdtUIACString appendFormat:@"                \"port-count\", Buffer() { %@ },\n", getByteString(portCount)];
		[ssdtUIACString appendString:@"                \"ports\", Package()\n"];
		[ssdtUIACString appendString:@"                {\n"];
		
		NSArray *portKeys = [portsDictionary allKeys];
		portKeys = [portKeys sortedArrayUsingSelector:@selector(compare:)];
		
		for (NSString *portKey in portKeys)
		{
			NSMutableDictionary *usbEntryDictionary = [portsDictionary objectForKey:portKey];
			
			NSString *portName = [usbEntryDictionary objectForKey:@"name"];
			NSNumber *portType = [usbEntryDictionary objectForKey:@"portType"];
			NSNumber *usbConnector = [usbEntryDictionary objectForKey:@"UsbConnector"];
			NSData *port = [usbEntryDictionary objectForKey:@"port"];
			NSString *comment = [usbEntryDictionary objectForKey:@"Comment"];
			
			[ssdtUIACString appendFormat:@"                      \"%@\", Package()\n", portKey];
			[ssdtUIACString appendString:@"                      {\n"];
			[ssdtUIACString appendFormat:@"                          \"name\", Buffer() { \"%@\" },\n", portName];
			if (portType != nil)
				[ssdtUIACString appendFormat:@"                          \"portType\", %d,\n", [portType unsignedIntValue]];
			else if (usbConnector != nil)
				[ssdtUIACString appendFormat:@"                          \"UsbConnector\", %d,\n", [usbConnector unsignedIntValue]];
			[ssdtUIACString appendFormat:@"                          \"port\", Buffer() { %@ },\n", getByteString(port)];
			if (comment != nil)
				[ssdtUIACString appendFormat:@"                          \"Comment\", Buffer() { \"%@\" },\n", comment];
			[ssdtUIACString appendString:@"                      },\n"];
		}
		
		[ssdtUIACString appendString:@"                },\n"];
		[ssdtUIACString appendString:@"            },\n"];
	}
	
	[ssdtUIACString appendString:@"        })\n"];
	[ssdtUIACString appendString:@"    }\n"];
	[ssdtUIACString appendString:@"}\n"];
	
	NSBundle *mainBundle = [NSBundle mainBundle];
	NSString *iaslPath = [mainBundle pathForResource:@"iasl" ofType:@"" inDirectory:@"Utilities"];
	NSString *desktopPath = [NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES) objectAtIndex:0];
	NSString *outputDslFilePath = [NSString stringWithFormat:@"%@/SSDT-UIAC.dsl", desktopPath];
	NSString *outputAmlFilePath = [NSString stringWithFormat:@"%@/SSDT-UIAC.aml", desktopPath];
	NSString *stdoutString = nil;
	NSError *error;
	
	[ssdtUIACString writeToFile:outputDslFilePath atomically:YES encoding:NSUTF8StringEncoding error:&error];
	
	launchCommand(iaslPath, @[@"-p", outputAmlFilePath, outputDslFilePath], &stdoutString);
	//NSLog(@"%@", stdoutString);
	
	NSArray *fileURLs = [NSArray arrayWithObjects:[NSURL fileURLWithPath:outputAmlFilePath], nil];
	[[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:fileURLs];
}

void exportUSBPorts(AppDelegate *appDelegate)
{
	//validateUSBPower(appDelegate);
	exportUSBPortsKext(appDelegate);
	exportUSBPortsSSDT(appDelegate);
	exportUSBPowerSSDT(appDelegate);
}

bool isControllerLocationXHC(uint32_t usbControllerLocationID)
{
	return (usbControllerLocationID == 0x14);
}

bool isControllerLocationEH1(uint32_t usbControllerLocationID)
{
	return (usbControllerLocationID == 0x1D);
}

bool isControllerLocationEH2(uint32_t usbControllerLocationID)
{
	return (usbControllerLocationID == 0x1A);
}

bool isControllerNameXHC(NSString *controllerName)
{
	NSArray *controllerArray =  @[@"XHCI", @"XHC1", @"XHC"];
	
	return ([controllerArray indexOfObject:controllerName] != NSNotFound);
}

bool isControllerNameEH1(NSString *controllerName)
{
	NSArray *controllerArray =  @[@"EHC1", @"EH01"];
	
	return ([controllerArray indexOfObject:controllerName] != NSNotFound);
}

bool isControllerNameEH2(NSString *controllerName)
{
	NSArray *controllerArray =  @[@"EHC2", @"EH02"];
	
	return ([controllerArray indexOfObject:controllerName] != NSNotFound);
}

bool isPortLocationHUB1(uint32_t locationID)
{
	return (locationID == 0x1D100000);
}

bool isPortLocationHUB2(uint32_t locationID)
{
	return (locationID == 0x1A100000);
}
