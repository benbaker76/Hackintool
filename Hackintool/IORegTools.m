//
//  IORegTools.m
//  Hackintool
//
//  Created by Ben Baker on 1/29/19.
//  Copyright © 2019 Ben Baker. All rights reserved.
//

#include "IORegTools.h"
#include "MiscTools.h"
#include "Display.h"
#include "AudioDevice.h"
#include <IOKit/IOBSD.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/graphics/IOGraphicsLib.h>

extern "C" {
#include "efidevp.h"
}

#define GetLocalizedString(key) \
[[NSBundle mainBundle] localizedStringForKey:(key) value:@"" table:nil]

bool getDevicePath(NSString *search, NSString **devicePath)
{
	bool retVal = false;
	kern_return_t status = KERN_SUCCESS;
	io_registry_entry_t service = 0;
	const io_name_t kPlane = kIODeviceTreePlane;
	BOOLEAN match = false;
	EFI_DEVICE_PATH	*efiDevicePath = NULL;
	io_iterator_t iterator = 0;
	char *devPathText = NULL;
	
	service = IORegistryGetRootEntry(kIOMasterPortDefault);
	
	if (service)
	{
		status = IORegistryEntryCreateIterator(service, kPlane, 0, &iterator);
		
		if (status == KERN_SUCCESS)
		{
			RecursiveFindDevicePath(iterator, [search cStringUsingEncoding:NSUTF8StringEncoding], kPlane, &efiDevicePath, &match);
			
			if(efiDevicePath != NULL && match)
			{
				devPathText = ConvertDevicePathToText(efiDevicePath, 1, 1);
				*devicePath = [NSString stringWithUTF8String:devPathText];
				
				free(devPathText);
				free(efiDevicePath);
				
				retVal = true;
			}
		}
	}

	IOObjectRelease(iterator);
	IOObjectRelease(service);

	return retVal;
}

bool getIORegChild(io_service_t device, NSString *name, io_service_t *foundDevice, bool recursive)
{
	kern_return_t kr;
	io_iterator_t childIterator;
	
	kr = IORegistryEntryGetChildIterator(device, kIOServicePlane, &childIterator);
	
	if (kr != KERN_SUCCESS)
		return false;
	
	for (io_service_t childDevice; IOIteratorIsValid(childIterator) && (childDevice = IOIteratorNext(childIterator)); IOObjectRelease(childDevice))
	{
		if (IOObjectConformsTo(childDevice, [name UTF8String]))
		{
			*foundDevice = childDevice;
			
			IOObjectRelease(childIterator);
			
			return true;
		}
		
		if (recursive)
		{
			if (getIORegChild(childDevice, name, foundDevice, recursive))
				return true;
		}
	}
	
	return false;
}

bool getIORegParentArray(io_service_t device, NSString *name, NSMutableArray *parentArray, bool recursive)
{
	bool retVal = false;
	kern_return_t kr;
	io_iterator_t parentIterator;
	
	kr = IORegistryEntryGetParentIterator(device, kIOServicePlane, &parentIterator);
	
	if (kr != KERN_SUCCESS)
		return false;
	
	for (io_service_t parentDevice; IOIteratorIsValid(parentIterator) && (parentDevice = IOIteratorNext(parentIterator));)
	{
		id parentObject = @(parentDevice);
		
		if (IOObjectConformsTo(parentDevice, [name UTF8String]))
		{
			[parentArray addObject:parentObject];
			
			retVal = true;
		}
		
		if (recursive)
		{
			if (getIORegParentArray(parentDevice, name, parentArray, recursive))
				retVal = true;
		}
		
		if (![parentArray containsObject:parentObject])
			IOObjectRelease(parentDevice);
	}
	
	IOObjectRelease(parentIterator);
	
	return retVal;
}

bool getIORegParent(io_service_t device, NSString *name, io_service_t *foundDevice, bool recursive)
{
	kern_return_t kr;
	io_iterator_t parentIterator;
	
	kr = IORegistryEntryGetParentIterator(device, kIOServicePlane, &parentIterator);
	
	if (kr != KERN_SUCCESS)
		return false;
	
	for (io_service_t parentDevice; IOIteratorIsValid(parentIterator) && (parentDevice = IOIteratorNext(parentIterator)); IOObjectRelease(parentDevice))
	{
		if (IOObjectConformsTo(parentDevice, [name UTF8String]))
		{
			*foundDevice = parentDevice;
			
			IOObjectRelease(parentIterator);
			
			return true;
		}
		
		if (recursive)
		{
			if (getIORegParent(parentDevice, name, foundDevice, recursive))
				return true;
		}
	}
	
	return false;
}

bool getIORegParent(io_service_t device, NSArray *nameArray, io_service_t *foundDevice, uint32_t *foundIndex, bool useClass, bool recursive)
{
	kern_return_t kr;
	io_iterator_t parentIterator;
	
	kr = IORegistryEntryGetParentIterator(device, kIOServicePlane, &parentIterator);
	
	if (kr != KERN_SUCCESS)
		return false;
	
	for (io_service_t parentDevice; IOIteratorIsValid(parentIterator) && (parentDevice = IOIteratorNext(parentIterator)); IOObjectRelease(parentDevice))
	{
		io_name_t name {};
		kr = (useClass ? IOObjectGetClass(parentDevice, name) : IORegistryEntryGetName(parentDevice, name));
		
		if (kr == KERN_SUCCESS)
		{
			for (int i = 0; i < [nameArray count]; i++)
			{
				if (CFStringCompare((__bridge CFStringRef)[NSString stringWithUTF8String:name], (__bridge CFStringRef)[nameArray objectAtIndex:i], 0) == kCFCompareEqualTo)
				{
					*foundDevice = parentDevice;
					*foundIndex = i;
					
					IOObjectRelease(parentIterator);
					
					return true;
				}
			}
		}
		
		if (recursive)
		{
			if (getIORegParent(parentDevice, nameArray, foundDevice, foundIndex, useClass, recursive))
				return true;
		}
	}
	
	return false;
}

bool getIORegParent(io_service_t device, NSArray *nameArray, io_service_t *foundDevice, bool useClass, bool recursive)
{
	uint32_t foundIndex = 0;
	
	return getIORegParent(device, nameArray, foundDevice, &foundIndex, useClass, recursive);
}

bool getAPFSPhysicalStoreBSDName(NSString *mediaUUID, NSString **bsdName)
{
	io_iterator_t iterator;
	
	kern_return_t kr = IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching("AppleAPFSContainer"), &iterator);
	
	if (kr != KERN_SUCCESS)
		return false;
	
	for (io_service_t device; IOIteratorIsValid(iterator) && (device = IOIteratorNext(iterator)); IOObjectRelease(device))
	{
		CFMutableDictionaryRef propertyDictionaryRef = 0;
		
		kr = IORegistryEntryCreateCFProperties(device, &propertyDictionaryRef, kCFAllocatorDefault, kNilOptions);
		
		if (kr != KERN_SUCCESS)
			continue;
		
		NSDictionary *propertyDictionary = (__bridge NSDictionary *)propertyDictionaryRef;
		
		NSString *uuid = [propertyDictionary objectForKey:@"UUID"];
		
		if (uuid == nil || ![uuid isEqualToString:mediaUUID])
			continue;
		
		io_service_t parentDevice;
		
		if (getIORegParent(device, @[@"IOMedia"], &parentDevice, true, true))
		{
			CFMutableDictionaryRef parentPropertyDictionaryRef = 0;
			
			kr = IORegistryEntryCreateCFProperties(parentDevice, &parentPropertyDictionaryRef, kCFAllocatorDefault, kNilOptions);
			
			if (kr == KERN_SUCCESS)
			{
				NSMutableDictionary *parentPropertyDictionary = (__bridge NSMutableDictionary *)parentPropertyDictionaryRef;
				
				*bsdName = [parentPropertyDictionary objectForKey:@"BSD Name"];
				
				IOObjectRelease(parentDevice);
				IOObjectRelease(device);
				IOObjectRelease(iterator);
				
				return true;
			}
			
			IOObjectRelease(parentDevice);
		}
	}
	
	IOObjectRelease(iterator);
	
	return false;
}

bool getIORegUSBPropertyDictionaryArray(NSMutableArray **propertyDictionaryArray)
{
	*propertyDictionaryArray = [NSMutableArray array];
	io_iterator_t iterator;
	
	kern_return_t kr = IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching("AppleUSBHostPort"), &iterator);
	
	if (kr != KERN_SUCCESS)
		return false;
	
	for (io_service_t device; IOIteratorIsValid(iterator) && (device = IOIteratorNext(iterator)); IOObjectRelease(device))
	{
		io_name_t name {};
		kr = IORegistryEntryGetName(device, name);
		
		if (kr != KERN_SUCCESS)
			continue;
		
		io_name_t className {};
		kr = IOObjectGetClass(device, className);
		
		if (kr != KERN_SUCCESS)
			continue;

		bool isHubPort = IOObjectConformsTo(device, "AppleUSBHubPort");
		bool isInternalHubPort = IOObjectConformsTo(device, "AppleUSBInternalHubPort");
		bool hubDeviceFound = false;
		uint32_t hubLocationID = 0;
		io_service_t hubDevice;
		io_name_t hubName {};
		
		if (isHubPort || isInternalHubPort)
		{
			if (getIORegParent(device, @"IOUSBDevice", &hubDevice, true))
			{
				kr = IORegistryEntryGetName(hubDevice, hubName);
				
				if (kr == KERN_SUCCESS)
				{
					CFTypeRef locationID = IORegistryEntrySearchCFProperty(hubDevice, kIOServicePlane, CFSTR("locationID"), kCFAllocatorDefault, kNilOptions);
					
					if (locationID)
					{
						// HUB1: (locationID == 0x1D100000)
						// HUB2: (locationID == 0x1A100000)
						hubLocationID = [(__bridge NSNumber *)locationID unsignedIntValue];
						
						CFRelease(locationID);
						
						hubDeviceFound = true;
					}
				}
				
				IOObjectRelease(hubDevice);
			}
		}
		
		io_service_t parentDevice;
		
		if (getIORegParent(device, @"IOPCIDevice", &parentDevice, true))
		{
			io_name_t parentName {};
			kr = IORegistryEntryGetName(parentDevice, parentName);
			
			if (kr == KERN_SUCCESS)
			{
				CFMutableDictionaryRef parentPropertyDictionaryRef = 0;
				
				kr = IORegistryEntryCreateCFProperties(parentDevice, &parentPropertyDictionaryRef, kCFAllocatorDefault, kNilOptions);
				
				if (kr == KERN_SUCCESS)
				{
					NSMutableDictionary *parentPropertyDictionary = (__bridge NSMutableDictionary *)parentPropertyDictionaryRef;
					
					CFMutableDictionaryRef propertyDictionaryRef = 0;
					
					kr = IORegistryEntryCreateCFProperties(device, &propertyDictionaryRef, kCFAllocatorDefault, kNilOptions);
					
					if (kr == KERN_SUCCESS)
					{
						NSMutableDictionary *propertyDictionary = (__bridge NSMutableDictionary *)propertyDictionaryRef;
						
						NSString *portName = [propertyDictionary objectForKey:@"name"];
						NSData *deviceID = [parentPropertyDictionary objectForKey:@"device-id"];
						NSData *vendorID = [parentPropertyDictionary objectForKey:@"vendor-id"];
						
						if (portName == nil)
							[propertyDictionary setValue:[NSString stringWithUTF8String:name] forKey:@"name"];
						
						uint32_t deviceIDInt = getUInt32FromData(deviceID);
						uint32_t vendorIDInt = getUInt32FromData(vendorID);
						
						[propertyDictionary setValue:[NSString stringWithUTF8String:parentName] forKey:@"UsbController"];
						[propertyDictionary setValue:[NSNumber numberWithInt:(deviceIDInt << 16) | vendorIDInt] forKey:@"UsbControllerID"];
						
						if (hubDeviceFound)
						{
							[propertyDictionary setValue:[NSString stringWithUTF8String:hubName] forKey:@"HubName"];
							[propertyDictionary setValue:[NSNumber numberWithInt:hubLocationID] forKey:@"HubLocation"];
						}
						
						[*propertyDictionaryArray addObject:propertyDictionary];
					}
				}
			}
			
			IOObjectRelease(parentDevice);
		}
	}
	
	IOObjectRelease(iterator);
	
	return ([*propertyDictionaryArray count] > 0);
}

bool getIORegAudioDeviceArray(NSMutableArray **audioDeviceArray)
{
	*audioDeviceArray = [[NSMutableArray array] retain];
	io_iterator_t iterator;
	
	kern_return_t kr = IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching("IOHDACodecDevice"), &iterator);
	
	if (kr != KERN_SUCCESS)
		return false;
	
	for (io_service_t device; IOIteratorIsValid(iterator) && (device = IOIteratorNext(iterator)); IOObjectRelease(device))
	{
		io_name_t name {};
		kr = IORegistryEntryGetName(device, name);
		
		if (kr != KERN_SUCCESS)
			continue;
		
		io_name_t className {};
		kr = IOObjectGetClass(device, className);
		
		if (kr != KERN_SUCCESS)
			continue;
		
		io_service_t parentDevice;
		
		if (getIORegParent(device, @"IOPCIDevice", &parentDevice, true))
		{
			io_name_t parentName {};
			kr = IORegistryEntryGetName(parentDevice, parentName);
			
			if (kr == KERN_SUCCESS)
			{
				CFMutableDictionaryRef parentPropertyDictionaryRef = 0;
				
				kr = IORegistryEntryCreateCFProperties(parentDevice, &parentPropertyDictionaryRef, kCFAllocatorDefault, kNilOptions);
				
				if (kr == KERN_SUCCESS)
				{
					NSMutableDictionary *parentPropertyDictionary = (__bridge NSMutableDictionary *)parentPropertyDictionaryRef;
					
					CFMutableDictionaryRef propertyDictionaryRef = 0;
					
					kr = IORegistryEntryCreateCFProperties(device, &propertyDictionaryRef, kCFAllocatorDefault, kNilOptions);
					
					if (kr == KERN_SUCCESS)
					{
						NSMutableDictionary *propertyDictionary = (__bridge NSMutableDictionary *)propertyDictionaryRef;
						
						NSData *deviceID = [parentPropertyDictionary objectForKey:@"device-id"];
						NSData *vendorID = [parentPropertyDictionary objectForKey:@"vendor-id"];
						NSData *revisionID = [parentPropertyDictionary objectForKey:@"revision-id"];
						NSData *alcLayoutID = [parentPropertyDictionary objectForKey:@"alc-layout-id"];
						NSData *subSystemID = [parentPropertyDictionary objectForKey:@"subsystem-id"];
						NSData *subSystemVendorID = [parentPropertyDictionary objectForKey:@"subsystem-vendor-id"];
						NSData *pinConfigurations = [parentPropertyDictionary objectForKey:@"PinConfigurations"];
						
						NSDictionary *digitalAudioCapabilities = [propertyDictionary objectForKey:@"DigitalAudioCapabilities"];
						NSNumber *codecAddressNumber = [propertyDictionary objectForKey:@"IOHDACodecAddress"];
						NSNumber *venderProductIDNumber = [propertyDictionary objectForKey:@"IOHDACodecVendorID"];
						NSNumber *revisionIDNumber = [propertyDictionary objectForKey:@"IOHDACodecRevisionID"];
						
						uint32_t deviceIDInt = getUInt32FromData(deviceID);
						uint32_t vendorIDInt = getUInt32FromData(vendorID);
						uint32_t revisionIDInt = getUInt32FromData(revisionID);
						uint32_t alcLayoutIDInt = getUInt32FromData(alcLayoutID);
						uint32_t subSystemIDInt = getUInt32FromData(subSystemID);
						uint32_t subSystemVendorIDInt = getUInt32FromData(subSystemVendorID);
						
						uint32_t deviceIDNew = (vendorIDInt << 16) | deviceIDInt;
						uint32_t subDeviceIDNew = (subSystemVendorIDInt << 16) | subSystemIDInt;
						
						AudioDevice *audioDevice = [[AudioDevice alloc] initWithDeviceClass:[NSString stringWithUTF8String:parentName] deviceID:deviceIDNew revisionID:revisionIDInt alcLayoutID:alcLayoutIDInt subDeviceID:subDeviceIDNew codecAddress:[codecAddressNumber unsignedIntValue] codecID:[venderProductIDNumber unsignedIntValue] codecRevisionID:[revisionIDNumber unsignedIntValue] pinConfigurations:pinConfigurations digitalAudioCapabilities:digitalAudioCapabilities];
						
						[*audioDeviceArray addObject:audioDevice];
						
						io_service_t childDevice;
						
						if (getIORegChild(device, @"AppleHDACodec", &childDevice, true))
						{
							io_name_t childName {};
							kr = IORegistryEntryGetName(childDevice, childName);
							
							if (kr == KERN_SUCCESS)
							{
								CFMutableDictionaryRef childPropertyDictionaryRef = 0;
								
								kr = IORegistryEntryCreateCFProperties(childDevice, &childPropertyDictionaryRef, kCFAllocatorDefault, kNilOptions);
								
								if (kr == KERN_SUCCESS)
								{
									// +-o AppleHDACodecGeneric  <class AppleHDACodecGeneric, id 0x10000044d, registered, matched, active, busy 0 (14 ms), retain 6>
									//   | {
									//   |   "IOProbeScore" = 1
									//   |   "CFBundleIdentifier" = "com.apple.driver.AppleHDA"
									//   |   "IOProviderClass" = "IOHDACodecFunction"
									//   |   "IOClass" = "AppleHDACodecGeneric"
									//   |   "IOMatchCategory" = "IODefaultMatchCategory"
									//   |   "alc-pinconfig-status" = Yes
									//   |   "vendorcodecID" = 282984514
									//   |   "alc-sleep-status" = No
									//   |   "HDMIDPAudioCapabilities" = Yes
									//   |   "IOHDACodecFunctionGroupType" = 1
									//   |   "HDAConfigDefault" = ({"AFGLowPowerState"=<03000000>,"CodecID"=283904146,"Comment"="ALC892, Toleda","ConfigData"=<01470c02>,"FuncGroup"=1,"BootConfigData"=<21471c1021471d4021471e1121471f9021470c0221571c2021571d1021571e0121571f0121671c3021671d6021671e0121671f0121771cf021771d0021771e0021771f4021871c4021871d9021871ea021871f9021971c6021971d9021971e8121971f0221a71c5021a71d3021a71e8121a71f0121b71c7021b71d4021b71e2121b71f0221b70c0221e71c9021e71d6121e71e4b21e71f0121f71cf021f71d0021f71e0021f71f4021171cf021171d0021171e0021171f40>,"WakeVerbReinit"=Yes,"LayoutID"=7})
									//   | }
									
									NSMutableDictionary *childPropertyDictionary = (__bridge NSMutableDictionary *)childPropertyDictionaryRef;
									audioDevice.hdaConfigDefaultDictionary = [childPropertyDictionary objectForKey:@"HDAConfigDefault"];
									audioDevice.bundleID = [childPropertyDictionary objectForKey:@"CFBundleIdentifier"];
								}
							}
						}
						
						[audioDevice release];
					}
				}
			}
			
			IOObjectRelease(parentDevice);
		}
	}
	
	IOObjectRelease(iterator);
	
	return ([*audioDeviceArray count] > 0);
}

NSString *properyToString(id value)
{
	if (value == nil)
		return @"???";
	
	if ([value isKindOfClass:[NSString class]])
		return value;
	else if ([value isKindOfClass:[NSData class]])
	{
		NSData *data = (NSData *)value;
		return [[[NSString alloc] initWithBytes:[data bytes] length:[data length] encoding:NSASCIIStringEncoding] autorelease];
	}
	
	return @"???";
}

uint32_t properyToUInt32(id value)
{
	if (value == nil)
		return 0;
	
	if ([value isKindOfClass:[NSNumber class]])
		return [value unsignedIntValue];
	
	return 0;
}

uint32_t nameToUInt32(NSString *name)
{
	if (![name hasPrefix:@"pci"] || [name rangeOfString:@","].location == NSNotFound)
		return 0;
	
	NSArray *nameArray = [[name stringByReplacingOccurrencesOfString:@"pci" withString:@""] componentsSeparatedByString:@","];
	
	return (uint32_t)(strHexDec([nameArray objectAtIndex:1]) << 16 | strHexDec([nameArray objectAtIndex:0]));
}

bool getDeviceLocation(io_service_t device, uint32_t *deviceNum, uint32_t *functionNum)
{
	io_name_t locationInPlane {};
	kern_return_t kr = IORegistryEntryGetLocationInPlane(device, kIOServicePlane, locationInPlane);
	
	if (kr != KERN_SUCCESS)
		return false;
	
	NSArray *locationArray = [[NSString stringWithUTF8String:locationInPlane] componentsSeparatedByString:@","];
	NSScanner *deviceScanner = [NSScanner scannerWithString:([locationArray count] > 0 ? locationArray[0] : @"")];
	NSScanner *functionScanner = [NSScanner scannerWithString:([locationArray count] > 1 ? locationArray[1] : @"")];
	[deviceScanner scanHexInt:deviceNum];
	[functionScanner scanHexInt:functionNum];
	
	return true;
}

bool getBusID(NSString *pciDebug, uint32_t *busNum, uint32_t *deviceNum, uint32_t *functionNum, uint32_t *secBridgeNum, uint32_t *subBridgeNum)
{
	if (pciDebug == nil)
		return false;
	
	NSArray *busArray = [[pciDebug componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@":()"]] valueForKey:@"integerValue"];
	
	if (busArray.count < 3)
		return false;

	// BDF: (String) Bus number, Device number, Function number (Format B:D:F)
	*busNum = [busArray[0] intValue];
	*deviceNum = [busArray[1] intValue];
	*functionNum = [busArray[2] intValue];
	*secBridgeNum = ([busArray count] > 3 ? [busArray[3] intValue] : 0);
	*subBridgeNum = ([busArray count] > 4 ? [busArray[4] intValue] : 0);
	
	return true;
}

bool getIORegPCIDeviceArray(NSMutableArray **pciDeviceArray)
{
	*pciDeviceArray = [[NSMutableArray array] retain];
	io_iterator_t iterator;
	
	kern_return_t kr = IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching("IOPCIDevice"), &iterator);
	
	if (kr != KERN_SUCCESS)
		return false;
	
	for (io_service_t device; IOIteratorIsValid(iterator) && (device = IOIteratorNext(iterator)); IOObjectRelease(device))
	{
		io_name_t name {};
		
		kr = IORegistryEntryGetName(device, name);

		if (kr != KERN_SUCCESS)
			continue;
		
		io_string_t path {};
		kr = IORegistryEntryGetPath(device, kIOServicePlane, path);
		
		if (kr != KERN_SUCCESS)
			continue;
		
		CFMutableDictionaryRef propertyDictionaryRef = 0;
		
		kr = IORegistryEntryCreateCFProperties(device, &propertyDictionaryRef, kCFAllocatorDefault, kNilOptions);
		
		if (kr == KERN_SUCCESS)
		{
			NSMutableDictionary *propertyDictionary = (__bridge NSMutableDictionary *)propertyDictionaryRef;
			NSData *vendorID = [propertyDictionary objectForKey:@"vendor-id"];
			NSData *deviceID = [propertyDictionary objectForKey:@"device-id"];
			NSData *subVendorID = [propertyDictionary objectForKey:@"subsystem-vendor-id"];
			NSData *subDeviceID = [propertyDictionary objectForKey:@"subsystem-id"];
			NSData *classCode = [propertyDictionary objectForKey:@"class-code"];
			NSString *_name = properyToString([propertyDictionary objectForKey:@"name"]);
			NSString *model = properyToString([propertyDictionary objectForKey:@"model"]);
			NSString *ioName = properyToString([propertyDictionary objectForKey:@"IOName"]);
			//NSString *pciDebug = [propertyDictionary objectForKey:@"pcidebug"];
			//NSString *uid = [propertyDictionary objectForKey:@"_UID"];
			NSString *deviceName = (ioName != nil ? ioName : _name != nil ? _name : @"???");
			
			uint32_t vendorIDInt = getUInt32FromData(vendorID);
			uint32_t deviceIDInt = getUInt32FromData(deviceID);
			uint32_t subVendorIDInt = getUInt32FromData(subVendorID);
			uint32_t subDeviceIDInt = getUInt32FromData(subDeviceID);
			uint32_t classCodeInt = getUInt32FromData(classCode);
			
			NSMutableDictionary *pciDictionary = [NSMutableDictionary dictionary];
		
			uint32_t shadowID = nameToUInt32(deviceName);
			[pciDictionary setObject:!shadowID ? @(vendorIDInt) : @(shadowID & 0xFFFF) forKey:@"ShadowVendor"];
			[pciDictionary setObject:!shadowID ? @(deviceIDInt) : @(shadowID >> 16) forKey:@"ShadowDevice"];
			
			//[pciDictionary setObject:[NSString stringWithUTF8String:name] forKey:@"IORegName"];
			[pciDictionary setObject:deviceName forKey:@"IORegIOName"];
			[pciDictionary setObject:[NSString stringWithUTF8String:path] forKey:@"IORegPath"];
			[pciDictionary setObject:[NSNumber numberWithInt:vendorIDInt] forKey:@"VendorID"];
			[pciDictionary setObject:[NSNumber numberWithInt:deviceIDInt] forKey:@"DeviceID"];
			[pciDictionary setObject:[NSNumber numberWithInt:subVendorIDInt] forKey:@"SubVendorID"];
			[pciDictionary setObject:[NSNumber numberWithInt:subDeviceIDInt] forKey:@"SubDeviceID"];
			[pciDictionary setObject:[NSNumber numberWithInt:classCodeInt] forKey:@"ClassCode"];
			//[pciDictionary setObject:@"Internal" forKey:@"SlotName"];
			//[pciDictionary setObject:@"???" forKey:@"DevicePath"];
			[pciDictionary setObject:model forKey:@"Model"];
			//[pciDictionary setObject:uid forKey:@"UID"];
			
			NSString *bundleID = (__bridge NSString *)IORegistryEntrySearchCFProperty(device, kIOServicePlane, CFSTR("CFBundleIdentifier"), kCFAllocatorDefault, kIORegistryIterateRecursively);
			
			if (bundleID == nil)
				bundleID = (__bridge NSString *)IORegistryEntrySearchCFProperty(device, kIOServicePlane, CFSTR("CFBundleIdentifier"), kCFAllocatorDefault, kIORegistryIterateRecursively | kIORegistryIterateParents);

			if (bundleID != nil)
			{
				[pciDictionary setObject:bundleID forKey:@"BundleID"];
				
				[bundleID release];
			}
			
			NSString *devicePath = @"", *slotName = @"", *ioregName = @"";
			uint32_t deviceNum = 0, functionNum = 0;
			
			getDeviceLocation(device, &deviceNum, &functionNum);
			
			ioregName = [NSString stringWithFormat:@"%s", name];
			devicePath = [NSString stringWithFormat:@"Pci(0x%x,0x%x)", deviceNum, functionNum];
			slotName = [NSString stringWithFormat:@"%d,%d", deviceNum, functionNum];
			
			[pciDictionary setObject:@(deviceNum << 16 | functionNum) forKey:@"Address"];
			
			NSMutableArray *parentArray = [NSMutableArray array];
			
			if (getIORegParentArray(device, @"IOPCIDevice", parentArray, true))
			{
				for (NSNumber *parentNumber in parentArray)
				{
					io_service_t parentDevice = [parentNumber unsignedIntValue];
					io_name_t parentName {};
					uint32_t deviceNum = 0, functionNum = 0;
					
					kr = IORegistryEntryGetName(parentDevice, parentName);
					
					getDeviceLocation(parentDevice, &deviceNum, &functionNum);
					
					ioregName = [NSString stringWithFormat:@"%s.%@", parentName, ioregName];
					devicePath = [NSString stringWithFormat:@"Pci(0x%x,0x%x)/%@", deviceNum, functionNum, devicePath];
					slotName = [NSString stringWithFormat:@"%d,%d/%@", deviceNum, functionNum, slotName];
					
					IOObjectRelease(parentDevice);
				}
			}
			
			io_service_t rootDevice;
			
			if (getIORegParent(device, @"IOACPIPlatformDevice", &rootDevice, true))
			{
				io_name_t rootName {};
				io_struct_inband_t pnp {}, uid {};
				uint32_t size = sizeof(pnp);
				
				kr = IORegistryEntryGetProperty(rootDevice, "compatible", pnp, &size);
				
				if (kr != KERN_SUCCESS)
				{
					size = sizeof(pnp);
					kr = IORegistryEntryGetProperty(rootDevice, "name", pnp, &size);
				}
				
				kr = IORegistryEntryGetName(rootDevice, rootName);
				
				size = sizeof(uid);
				
				kr = IORegistryEntryGetProperty(rootDevice, "_UID", uid, &size);
				
				NSNumber *uidNumber = @([[NSString stringWithUTF8String:uid] intValue]);
				unsigned int pnpId = (unsigned int)(strlen(pnp) > 3 ? strtol(pnp + 3, NULL, 16) : 0);
				unsigned int eisaId = (strlen(pnp) > 3 ? (((pnp[0] - '@') & 0x1f) << 10) + (((pnp[1] - '@') & 0x1f) << 5) + ((pnp[2] - '@') & 0x1f) + (pnpId << 16) : 0);
				
				if ((eisaId & PNP_EISA_ID_MASK) == PNP_EISA_ID_CONST)
				{
					switch (EISA_ID_TO_NUM(eisaId))
					{
						case 0x0a03:
							devicePath = [NSString stringWithFormat:@"PciRoot(0x%x)/%@", [uidNumber unsignedIntValue], devicePath];
							break;
						default:
							devicePath = [NSString stringWithFormat:@"Acpi(PNP%04x,0x%x)/%@", EISA_ID_TO_NUM(eisaId), [uidNumber unsignedIntValue], devicePath];
							break;
					}
				}
				else
					devicePath = [NSString stringWithFormat:@"Acpi(0x%08x,0x%x)/%@", eisaId, [uidNumber unsignedIntValue], devicePath];
				
				ioregName = [NSString stringWithFormat:@"%s.%@", rootName, ioregName];
				slotName = [NSString stringWithFormat:@"Internal@%d,%@", [uidNumber unsignedIntValue], slotName];
				
				IOObjectRelease(rootDevice);
			}
			
			[pciDictionary setObject:devicePath forKey:@"DevicePath"];
			[pciDictionary setObject:slotName forKey:@"SlotName"];
			[pciDictionary setObject:ioregName forKey:@"IORegName"];
			
			[*pciDeviceArray addObject:pciDictionary];
		}
	}
	
	IOObjectRelease(iterator);
	
	return ([*pciDeviceArray count] > 0);
}

bool getIORegNetworkArray(NSMutableArray **networkInterfacesArray)
{
	*networkInterfacesArray = [[NSMutableArray array] retain];
	io_iterator_t iterator;
	
	kern_return_t kr = IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching("IONetworkInterface"), &iterator);
	
	if (kr != KERN_SUCCESS)
		return false;
	
	for (io_service_t device; IOIteratorIsValid(iterator) && (device = IOIteratorNext(iterator)); IOObjectRelease(device))
	{
		io_service_t parentDevice;
		
		if (getIORegParent(device, @"IOPCIDevice", &parentDevice, true))
		{
			CFMutableDictionaryRef parentPropertyDictionaryRef = 0;
			
			kr = IORegistryEntryCreateCFProperties(parentDevice, &parentPropertyDictionaryRef, kCFAllocatorDefault, kNilOptions);
			
			if (kr == KERN_SUCCESS)
			{
				NSMutableDictionary *parentPropertyDictionary = (__bridge NSMutableDictionary *)parentPropertyDictionaryRef;
				
				CFMutableDictionaryRef propertyDictionaryRef = 0;
				
				kr = IORegistryEntryCreateCFProperties(device, &propertyDictionaryRef, kCFAllocatorDefault, kNilOptions);
				
				if (kr == KERN_SUCCESS)
				{
					NSMutableDictionary *propertyDictionary = (__bridge NSMutableDictionary *)propertyDictionaryRef;
					
					NSData *deviceID = [parentPropertyDictionary objectForKey:@"device-id"];
					NSData *vendorID = [parentPropertyDictionary objectForKey:@"vendor-id"];
					NSString *bsdName = [propertyDictionary objectForKey:@"BSD Name"];
					NSNumber *builtIn = [propertyDictionary objectForKey:@"IOBuiltin"];
					
					uint32_t vendorIDInt = getUInt32FromData(vendorID);
					uint32_t deviceIDInt = getUInt32FromData(deviceID);
					
					NSMutableDictionary *networkInterfacesDictionary = [NSMutableDictionary dictionary];
					
					[networkInterfacesDictionary setObject:[NSNumber numberWithInteger:deviceIDInt] forKey:@"DeviceID"];
					[networkInterfacesDictionary setObject:[NSNumber numberWithInteger:vendorIDInt] forKey:@"VendorID"];
					[networkInterfacesDictionary setObject:bsdName forKey:@"BSD Name"];
					[networkInterfacesDictionary setObject:builtIn forKey:@"Builtin"];
					
					NSString *bundleID = (__bridge NSString *)IORegistryEntrySearchCFProperty(device, kIOServicePlane, CFSTR("CFBundleIdentifier"), kCFAllocatorDefault, kIORegistryIterateRecursively | kIORegistryIterateParents);
					
					if (bundleID != nil)
					{
						[networkInterfacesDictionary setObject:bundleID forKey:@"BundleID"];
						
						[bundleID release];
					}
					
					[*networkInterfacesArray addObject:networkInterfacesDictionary];
				}
			}
			
			IOObjectRelease(parentDevice);
		}
	}
	
	IOObjectRelease(iterator);
	
	return ([*networkInterfacesArray count] > 0);
}

bool getIORegGraphicsArray(NSMutableArray **graphicsArray)
{
	*graphicsArray = [[NSMutableArray array] retain];
	io_iterator_t iterator;
	NSMutableDictionary *graphicsDictionaryDictionary = [NSMutableDictionary dictionary];
	
	// Intel: AppleIntelFramebuffer (class: AppleIntelFramebuffer)
	// AMD: ATY,AMD,RadeonFramebuffer (class: AtiFbStub)
	// AMD: ATY,RadeonFramebuffer (class: AMDRadeonX6000_AmdRadeonFramebuffer)
	// nVidia: NVDA,Display-A, NVDA,Display-B, NVDA,Display-C, NVDA,Display-D, NVDA,Display-E, NVDA,Display-F (class: IONDRVDevice)
	
	//NSArray *framebufferArray = @[@"AppleIntelFramebuffer", @"AtiFbStub", @"AMDRadeonX6000_AmdRadeonFramebuffer", @"IONDRVDevice"];
	
	kern_return_t kr = IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching("IOFramebuffer"), &iterator);
	
	if (kr != KERN_SUCCESS)
		return false;
	
	uint32_t portCount = 1;
	
	for (io_service_t device; IOIteratorIsValid(iterator) && (device = IOIteratorNext(iterator)); IOObjectRelease(device))
	{
		io_name_t name {};
		kr = IORegistryEntryGetName(device, name);
		
		if (kr != KERN_SUCCESS)
			continue;
		
		io_service_t parentDevice;
		
		if (getIORegParent(device, @"IOPCIDevice", &parentDevice, true))
		{
			CFMutableDictionaryRef parentPropertyDictionaryRef = 0;
			
			kr = IORegistryEntryCreateCFProperties(parentDevice, &parentPropertyDictionaryRef, kCFAllocatorDefault, kNilOptions);
			
			if (kr == KERN_SUCCESS)
			{
				NSMutableDictionary *parentPropertyDictionary = (__bridge NSMutableDictionary *)parentPropertyDictionaryRef;
				
				NSData *modelData = [parentPropertyDictionary objectForKey:@"model"];
				NSString *modelString = [[[NSString alloc] initWithData:modelData encoding:NSASCIIStringEncoding] autorelease];
				NSData *platformID = [parentPropertyDictionary objectForKey:@"AAPL,snb-platform-id"];
				
				if (!platformID)
					platformID = [parentPropertyDictionary objectForKey:@"AAPL,ig-platform-id"];
				
				uint32_t platformIDInt = getUInt32FromData(platformID);
				
				NSMutableDictionary *graphicsDictionary = [graphicsDictionaryDictionary objectForKey:modelString];
				
				if (graphicsDictionary == nil)
				{
					graphicsDictionary = [NSMutableDictionary dictionary];
					
					[graphicsDictionary setObject:modelString forKey:@"Model"];
					[graphicsDictionary setObject:[NSString stringWithUTF8String:name] forKey:@"Framebuffer"];
					
					if (platformID != nil)
						[graphicsDictionary setObject:[NSString stringWithFormat:@"0x%08X", platformIDInt] forKey:@"Framebuffer"];
					
					NSString *bundleID = (__bridge NSString *)IORegistryEntrySearchCFProperty(parentDevice, kIOServicePlane, CFSTR("CFBundleIdentifier"), kCFAllocatorDefault, kIORegistryIterateRecursively);
					
					if (bundleID != nil)
					{
						[graphicsDictionary setObject:bundleID forKey:@"BundleID"];
						
						[bundleID release];
					}
					
					[*graphicsArray addObject:graphicsDictionary];
					[graphicsDictionaryDictionary setObject:graphicsDictionary forKey:modelString];
				}
				
				[graphicsDictionary setObject:[NSNumber numberWithInt:portCount] forKey:@"PortCount"];
			}
			
			IOObjectRelease(parentDevice);
		}
		
		portCount++;
	}
	
	IOObjectRelease(iterator);
	
	return ([*graphicsArray count] > 0);
}

bool getIORegStorageArray(NSMutableArray **storageArray)
{
	*storageArray = [[NSMutableArray array] retain];
	io_iterator_t iterator;
	
	kern_return_t kr = IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching("IOBlockStorageDevice"), &iterator);
	
	if (kr != KERN_SUCCESS)
		return false;
	
	for (io_service_t device; IOIteratorIsValid(iterator) && (device = IOIteratorNext(iterator)); IOObjectRelease(device))
	{
		CFMutableDictionaryRef propertyDictionaryRef = 0;
		
		kr = IORegistryEntryCreateCFProperties(device, &propertyDictionaryRef, kCFAllocatorDefault, kNilOptions);
		
		if (kr == KERN_SUCCESS)
		{
			NSMutableDictionary *propertyDictionary = (__bridge NSMutableDictionary *)propertyDictionaryRef;
			
			NSMutableDictionary *deviceCharacteristicsDictionary = [propertyDictionary objectForKey:@"Device Characteristics"];
			NSMutableDictionary *protocolCharacteristicsDictionary = [propertyDictionary objectForKey:@"Protocol Characteristics"];
			NSNumber *physicalBlockSize = [propertyDictionary objectForKey:@"Physical Block Size"];
			
			NSString *productName = [deviceCharacteristicsDictionary objectForKey:@"Product Name"];
			
			if (physicalBlockSize == nil)
				physicalBlockSize = [deviceCharacteristicsDictionary objectForKey:@"Physical Block Size"];
			
			NSString *physicalInterconnect = [protocolCharacteristicsDictionary objectForKey:@"Physical Interconnect"];
			NSString *physicalInterconnectLocation = [protocolCharacteristicsDictionary objectForKey:@"Physical Interconnect Location"];
			
			NSMutableDictionary *storageDictionary = [NSMutableDictionary dictionary];
			
			[storageDictionary setObject:productName != nil ? productName : @"???" forKey:@"Model"];
			[storageDictionary setObject:physicalInterconnect != nil ? physicalInterconnect : @"???" forKey:@"Type"];
			[storageDictionary setObject:physicalInterconnectLocation != nil ? physicalInterconnectLocation : @"???" forKey:@"Location"];
			
			if (physicalBlockSize != nil)
				[storageDictionary setObject:physicalBlockSize forKey:@"BlockSize"];
			
			NSString *bundleID = (__bridge NSString *)IORegistryEntrySearchCFProperty(device, kIOServicePlane, CFSTR("CFBundleIdentifier"), kCFAllocatorDefault, kIORegistryIterateRecursively | kIORegistryIterateParents);
			
			if (bundleID != nil)
			{
				[storageDictionary setObject:bundleID forKey:@"BundleID"];
				
				[bundleID release];
			}
			
			[*storageArray addObject:storageDictionary];
		}
	}
	
	IOObjectRelease(iterator);
	
	return ([*storageArray count] > 0);
}

bool getIORegPropertyDictionaryArrayWithParent(NSString *serviceName, NSString *parentName, NSMutableArray **propertyArray)
{
	*propertyArray = [NSMutableArray array];
	io_iterator_t iterator;
	
	kern_return_t kr = IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching([serviceName UTF8String]), &iterator);
	
	if (kr != KERN_SUCCESS)
		return false;
	
	for (io_service_t device; IOIteratorIsValid(iterator) && (device = IOIteratorNext(iterator)); IOObjectRelease(device))
	{
		io_service_t parentDevice;
		
		if (getIORegParent(device, parentName, &parentDevice, true))
		{
			CFMutableDictionaryRef parentPropertyDictionaryRef = 0;
			
			kr = IORegistryEntryCreateCFProperties(parentDevice, &parentPropertyDictionaryRef, kCFAllocatorDefault, kNilOptions);
			
			if (kr == KERN_SUCCESS)
			{
				NSMutableDictionary *parentPropertyDictionary = (__bridge NSMutableDictionary *)parentPropertyDictionaryRef;
				
				[*propertyArray addObject:parentPropertyDictionary];
			}
		}
	}
	
	IOObjectRelease(iterator);
	
	return ([*propertyArray count] > 0);
}

bool getIORegPropertyDictionary(NSString *serviceName, NSString *entryName, NSArray *classNameArray, NSMutableDictionary **propertyDictionary)
{
	*propertyDictionary = [NSMutableDictionary dictionary];
	io_iterator_t iterator;
	
	kern_return_t kr = IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching([serviceName UTF8String]), &iterator);
	
	if (kr != KERN_SUCCESS)
		return false;
	
	for (io_service_t device; IOIteratorIsValid(iterator) && (device = IOIteratorNext(iterator)); IOObjectRelease(device))
	{
		io_name_t name {};
		kr = IORegistryEntryGetName(device, name);
		
		if (kr != KERN_SUCCESS)
			continue;
		
		if (CFStringCompare((__bridge CFStringRef)[NSString stringWithUTF8String:name], (__bridge CFStringRef)entryName, 0) != kCFCompareEqualTo)
			continue;
		
		io_iterator_t childIterator;
		
		kr = IORegistryEntryGetChildIterator(device, kIOServicePlane, &childIterator);
		
		if (kr != KERN_SUCCESS)
			continue;
		
		for (io_service_t childDevice; IOIteratorIsValid(childIterator) && (childDevice = IOIteratorNext(childIterator)); IOObjectRelease(childDevice))
		{
			io_name_t childClassName {};
			kr = IOObjectGetClass(childDevice, childClassName);
			
			if (kr != KERN_SUCCESS)
				continue;
			
			bool classFound = false;
			
			for (int i = 0; i < [classNameArray count]; i++)
			{
				if (CFStringCompare((__bridge CFStringRef)[NSString stringWithUTF8String:childClassName], (__bridge CFStringRef)[classNameArray objectAtIndex:i], 0) == kCFCompareEqualTo)
				{
					classFound = true;
					
					break;
				}
			}
			
			if (!classFound)
				continue;
			
			CFMutableDictionaryRef propertyDictionaryRef = 0;
			
			kr = IORegistryEntryCreateCFProperties(childDevice, &propertyDictionaryRef, kCFAllocatorDefault, kNilOptions);
			
			if (kr != KERN_SUCCESS)
				continue;
			
			*propertyDictionary = (__bridge NSMutableDictionary *)propertyDictionaryRef;
			
			IOObjectRelease(childIterator);
			IOObjectRelease(childDevice);
			IOObjectRelease(iterator);
			IOObjectRelease(device);
			
			return (*propertyDictionary != nil);
		}
	}
	
	IOObjectRelease(iterator);
	
	return false;
}

/* bool getIORegPropertyDictionaryArray(io_service_t device, NSMutableArray **propertyDictionaryArray, bool recursive)
{
	kern_return_t kr;
	io_iterator_t childIterator;
	
	kr = IORegistryEntryGetChildIterator(device, kIOServicePlane, &childIterator);
	
	if (kr != KERN_SUCCESS)
		return false;
	
	for (io_service_t childDevice; IOIteratorIsValid(childIterator) && (childDevice = IOIteratorNext(childIterator)); IOObjectRelease(childDevice))
	{
		if (recursive)
			getIORegPropertyDictionaryArray(childDevice, propertyDictionaryArray, recursive);
		
		CFMutableDictionaryRef propertyDictionaryRef = 0;
		
		kr = IORegistryEntryCreateCFProperties(childDevice, &propertyDictionaryRef, kCFAllocatorDefault, kNilOptions);
		
		if (kr != KERN_SUCCESS)
			continue;
		
		NSMutableDictionary *propertyDictionary = (__bridge NSMutableDictionary *)propertyDictionaryRef;
		
		[*propertyDictionaryArray addObject:propertyDictionary];
	}
	
	return true;
}

bool getIORegPropertyDictionaryArray(NSString *serviceName, NSMutableArray **propertyDictionaryArray, bool recursive)
{
	*propertyDictionaryArray = [NSMutableArray array];
	io_iterator_t iterator;
	
	kern_return_t kr = IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching([serviceName UTF8String]), &iterator);
	
	if (kr != KERN_SUCCESS)
		return false;
	
	for (io_service_t device; IOIteratorIsValid(iterator) && (device = IOIteratorNext(iterator)); IOObjectRelease(device))
		getIORegPropertyDictionaryArray(device, propertyDictionaryArray, recursive);
	
	IOObjectRelease(iterator);
	
	return ([*propertyDictionaryArray count] > 0);
} */

bool getIORegPropertyDictionaryArray(NSString *serviceName, NSMutableArray **propertyDictionaryArray)
{
	*propertyDictionaryArray = [NSMutableArray array];
	io_iterator_t iterator;
	
	kern_return_t kr = IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching([serviceName UTF8String]), &iterator);
	
	if (kr != KERN_SUCCESS)
		return false;
	
	for (io_service_t device; IOIteratorIsValid(iterator) && (device = IOIteratorNext(iterator)); IOObjectRelease(device))
	{
		CFMutableDictionaryRef propertyDictionaryRef = 0;
		
		kr = IORegistryEntryCreateCFProperties(device, &propertyDictionaryRef, kCFAllocatorDefault, kNilOptions);
		
		if (kr != KERN_SUCCESS)
			continue;
		
		NSMutableDictionary *propertyDictionary = (__bridge NSMutableDictionary *)propertyDictionaryRef;
		
		[*propertyDictionaryArray addObject:propertyDictionary];
	}
	
	IOObjectRelease(iterator);
	
	return ([*propertyDictionaryArray count] > 0);
}

bool getIORegPropertyDictionary(NSString *serviceName, NSArray *entryNameArray, NSMutableDictionary **propertyDictionary, uint32_t *foundIndex)
{
	io_iterator_t iterator;
	
	kern_return_t kr = IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching([serviceName UTF8String]), &iterator);
	
	if (kr != KERN_SUCCESS)
		return false;
	
	for (io_service_t device; IOIteratorIsValid(iterator) && (device = IOIteratorNext(iterator)); IOObjectRelease(device))
	{
		io_name_t name {};
		kr = IORegistryEntryGetName(device, name);
		
		if (kr != KERN_SUCCESS)
			continue;
		
		bool entryFound = false;
		
		for (int i = 0; i < [entryNameArray count]; i++)
		{
			if (CFStringCompare((__bridge CFStringRef)[NSString stringWithUTF8String:name], (__bridge CFStringRef)[entryNameArray objectAtIndex:i], 0) == kCFCompareEqualTo)
			{
				entryFound = true;
				*foundIndex = i;
				
				break;
			}
		}
		
		if (!entryFound)
			continue;
		
		CFMutableDictionaryRef propertyDictionaryRef = 0;
		
		kr = IORegistryEntryCreateCFProperties(device, &propertyDictionaryRef, kCFAllocatorDefault, kNilOptions);
		
		if (kr != KERN_SUCCESS)
			continue;
		
		*propertyDictionary = (__bridge NSMutableDictionary *)propertyDictionaryRef;
		
		IOObjectRelease(iterator);
		IOObjectRelease(device);
		
		return true;
	}
	
	IOObjectRelease(iterator);
	
	return false;
}

bool getIORegPropertyDictionary(NSString *serviceName, NSString *entryName, NSMutableDictionary **propertyDictionary)
{
	io_iterator_t iterator;
	
	kern_return_t kr = IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching([serviceName UTF8String]), &iterator);
	
	if (kr != KERN_SUCCESS)
		return false;
	
	for (io_service_t device; IOIteratorIsValid(iterator) && (device = IOIteratorNext(iterator)); IOObjectRelease(device))
	{
		io_name_t name {};
		kr = IORegistryEntryGetName(device, name);
		
		if (kr != KERN_SUCCESS)
			continue;
		
		if (CFStringCompare((__bridge CFStringRef)[NSString stringWithUTF8String:name], (__bridge CFStringRef)entryName, 0) != kCFCompareEqualTo)
			continue;
		
		CFMutableDictionaryRef propertyDictionaryRef = 0;
		
		kr = IORegistryEntryCreateCFProperties(device, &propertyDictionaryRef, kCFAllocatorDefault, kNilOptions);
		
		if (kr != KERN_SUCCESS)
			continue;
		
		*propertyDictionary = (__bridge NSMutableDictionary *)propertyDictionaryRef;
		
		IOObjectRelease(iterator);
		IOObjectRelease(device);
		
		return true;
	}
	
	IOObjectRelease(iterator);
	
	return false;
}

bool hasIORegEntry(NSString *path)
{
	io_registry_entry_t device = IORegistryEntryFromPath(kIOMasterPortDefault, [path UTF8String]);
	
	return (device != MACH_PORT_NULL);
}

bool hasACPIEntry(NSString *name)
{
	bool result = false;
	
	io_registry_entry_t device = IORegistryEntryFromPath(kIOMasterPortDefault, "IOService:/AppleACPIPlatformExpert");
	
	if (device == MACH_PORT_NULL)
		return false;
	
	io_service_t foundDevice;
	
	result = getIORegChild(device, name, &foundDevice, true);

	IOObjectRelease(device);
	
	return result;
}

bool getIORegProperty(NSString *path, NSString *propertyName, CFTypeRef *property)
{
	*property = nil;
	io_registry_entry_t device = IORegistryEntryFromPath(kIOMasterPortDefault, [path UTF8String]);
	
	if (device == MACH_PORT_NULL)
		return false;
	
	*property = IORegistryEntryCreateCFProperty(device, (__bridge CFStringRef)propertyName, kCFAllocatorDefault, kNilOptions);
	
	IOObjectRelease(device);
	
	return (*property != nil);
}

bool getIORegProperties(NSString *path, NSMutableDictionary **propertyDictionary)
{
	*propertyDictionary = nil;
	io_registry_entry_t device = IORegistryEntryFromPath(kIOMasterPortDefault, [path UTF8String]);
	
	if (device == MACH_PORT_NULL)
		return false;
	
	CFMutableDictionaryRef propertyDictionaryRef = 0;
	
	kern_return_t kr = IORegistryEntryCreateCFProperties(device, &propertyDictionaryRef, kCFAllocatorDefault, kNilOptions);
	
	if (kr == KERN_SUCCESS)
		*propertyDictionary = (__bridge NSMutableDictionary *)propertyDictionaryRef;
	
	IOObjectRelease(device);
	
	return (*propertyDictionary != nil);
}

bool getIORegProperty(NSString *serviceName, NSString *entryName, NSString *propertyName, CFTypeRef *property)
{
	*property = nil;
	io_iterator_t iterator;
	
	kern_return_t kr = IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching([serviceName UTF8String]), &iterator);
	
	if (kr != KERN_SUCCESS)
		return false;
	
	for (io_service_t device; IOIteratorIsValid(iterator) && (device = IOIteratorNext(iterator)); IOObjectRelease(device))
	{
		io_name_t name {};
		kr = IORegistryEntryGetName(device, name);
		
		if (kr != KERN_SUCCESS)
			continue;
		
		if (CFStringCompare((__bridge CFStringRef)[NSString stringWithUTF8String:name], (__bridge CFStringRef)entryName, 0) != kCFCompareEqualTo)
			continue;
		
		*property = IORegistryEntrySearchCFProperty(device, kIOServicePlane, (__bridge CFStringRef)propertyName, kCFAllocatorDefault, kNilOptions);
		
		IOObjectRelease(iterator);
		IOObjectRelease(device);
		
		return (*property != nil);
	}
	
	IOObjectRelease(iterator);
	
	return false;
}

void getVRAMSize(io_service_t device, mach_vm_size_t &vramSize)
{
	_Bool valueInBytes = TRUE;
	CFTypeRef totalSize = IORegistryEntrySearchCFProperty(device, kIOServicePlane, CFSTR("VRAM,totalsize"), kCFAllocatorDefault, kIORegistryIterateRecursively);
	
	if (!totalSize)
	{
		valueInBytes = FALSE;
		totalSize = IORegistryEntrySearchCFProperty(device, kIOServicePlane, CFSTR("VRAM,totalMB"), kCFAllocatorDefault, kIORegistryIterateRecursively);
	}
	
	if (totalSize)
	{
		mach_vm_size_t size = 0;
		CFTypeID type = CFGetTypeID(totalSize);
		
		if (type == CFDataGetTypeID())
			vramSize = (CFDataGetLength((__bridge CFDataRef)totalSize) == sizeof(uint32_t) ? (mach_vm_size_t) *(const uint32_t *)CFDataGetBytePtr((__bridge CFDataRef)totalSize) : *(const uint64_t *)CFDataGetBytePtr((__bridge CFDataRef)totalSize));
		else if (type == CFNumberGetTypeID())
			CFNumberGetValue((__bridge CFNumberRef)totalSize, kCFNumberSInt64Type, &size);
		
		if (valueInBytes)
			vramSize >>= 20;
		
		CFRelease(totalSize);
	}
}

bool getVideoPerformanceStatisticsDictionary(CFMutableDictionaryRef *performanceStatisticsDictionary)
{
	io_iterator_t iterator;
	kern_return_t kr = IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching(kIOAcceleratorClassName), &iterator);
	
	if (kr != KERN_SUCCESS)
		return false;
	
	for (io_service_t device; IOIteratorIsValid(iterator) && (device = IOIteratorNext(iterator)); IOObjectRelease(device))
	{
		CFMutableDictionaryRef properties = NULL;
		kr = IORegistryEntryCreateCFProperties(device, &properties, kCFAllocatorDefault, kNilOptions);
		
		if (kr == KERN_SUCCESS)
		{
			*performanceStatisticsDictionary = (CFMutableDictionaryRef)CFDictionaryGetValue(properties, CFSTR("PerformanceStatistics"));
			
			if (*performanceStatisticsDictionary)
			{
				IOObjectRelease(iterator);
				IOObjectRelease(device);
				
				return true;
			}
		}
		
		if (properties)
			CFRelease(properties);
	}
	
	IOObjectRelease(iterator);
	
	return false;
}

void getVRAMFreeBytes(mach_vm_size_t &vramFree)
{
	CFMutableDictionaryRef performanceStatisticsDictionary = nil;
	
	if (getVideoPerformanceStatisticsDictionary(&performanceStatisticsDictionary))
	{
		CFNumberRef vramFreeBytes = (__bridge CFNumberRef)CFDictionaryGetValue(performanceStatisticsDictionary, CFSTR("vramFreeBytes"));
		
		if (vramFreeBytes)
			CFNumberGetValue(vramFreeBytes, kCFNumberSInt64Type, &vramFree);
	}
}

bool getIGPUModelAndVRAM(NSString **gpuModel, uint32_t &gpuDeviceID, uint32_t &gpuVendorID, mach_vm_size_t &vramSize, mach_vm_size_t &vramFree)
{
	*gpuModel = @"???";
	io_iterator_t iterator;
	kern_return_t kr = IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching("IOPCIDevice"), &iterator);
	
	if (kr != KERN_SUCCESS)
		return false;
	
	for (io_service_t device; IOIteratorIsValid(iterator) && (device = IOIteratorNext(iterator)); IOObjectRelease(device))
	{
		io_name_t name {};
		kr = IORegistryEntryGetName(device, name);
		
		if (kr != KERN_SUCCESS)
			continue;
		
		if (CFStringCompare((__bridge CFStringRef)[NSString stringWithUTF8String:name], CFSTR("IGPU"), 0) != kCFCompareEqualTo)
			continue;
		
		CFTypeRef model = IORegistryEntrySearchCFProperty(device, kIOServicePlane, CFSTR("model"), kCFAllocatorDefault, kNilOptions);
		
		if (model)
		{
			NSData *modelData = (__bridge NSData *)model;
			const char *modelBytes = (const char *)[modelData bytes];
			
			if (modelBytes)
				*gpuModel = [[NSString stringWithUTF8String:modelBytes] retain];
			
			CFRelease(model);
		}
		
		CFTypeRef deviceID = IORegistryEntrySearchCFProperty(device, kIOServicePlane, CFSTR("device-id"), kCFAllocatorDefault, kNilOptions);
		
		if (deviceID)
		{
			gpuDeviceID = *(const uint32_t *)CFDataGetBytePtr((__bridge CFDataRef)deviceID);
			
			CFRelease(deviceID);
		}
		
		CFTypeRef vendorID = IORegistryEntrySearchCFProperty(device, kIOServicePlane, CFSTR("vendor-id"), kCFAllocatorDefault, kNilOptions);
		
		if (vendorID)
		{
			gpuVendorID = *(const uint32_t *)CFDataGetBytePtr((__bridge CFDataRef)vendorID);
			
			CFRelease(vendorID);
		}
		
		getVRAMSize(device, vramSize);
		getVRAMFreeBytes(vramFree);
		
		IOObjectRelease(iterator);
		IOObjectRelease(device);
		
		return true;
	}
	
	IOObjectRelease(iterator);
	
	return false;
}

bool getScreenNumberForDisplay(SInt32 myVendorID, SInt32 myProductID, SInt32 mySerialNumber, CGDirectDisplayID *directDisplayID)
{
	bool retval = false;
	CGDirectDisplayID directDisplayIDArray[10];
	uint32_t displayCount = 0;
	CGError err = CGGetActiveDisplayList(10, directDisplayIDArray, &displayCount);
	
	if (err != kCGErrorSuccess)
		return false;
	
	if (displayCount == 0)
		return false;
	
	for (uint32_t i = 0; i < displayCount; i++)
	{
		io_service_t servicePort = CGDisplayIOServicePort(directDisplayIDArray[i]);
		CFDictionaryRef displayInfo = IODisplayCreateInfoDictionary(servicePort, kIODisplayMatchingInfo);
		
		CFNumberRef vendorIDRef = nil;
		CFNumberRef productIDRef = nil;
		CFNumberRef serialNumberRef = nil;
		SInt32 vendorID = 0, productID = 0, serialNumber = 0;
		
		Boolean success;
		success = CFDictionaryGetValueIfPresent(displayInfo, CFSTR(kDisplayVendorID), (const void **)&vendorIDRef);
		success &= CFDictionaryGetValueIfPresent(displayInfo, CFSTR(kDisplayProductID), (const void **)&productIDRef);
		
		if (success)
		{
			CFNumberGetValue(vendorIDRef, kCFNumberSInt32Type, &vendorID);
			CFNumberGetValue(productIDRef, kCFNumberSInt32Type, &productID);
		}
		
		if (CFDictionaryGetValueIfPresent(displayInfo, CFSTR(kDisplaySerialNumber), (const void **)&serialNumberRef))
		{
			CFNumberGetValue(serialNumberRef, kCFNumberSInt32Type, &serialNumber);
		}
		
		if (myVendorID == vendorID && myProductID == productID && mySerialNumber == serialNumber)
		{
			*directDisplayID = directDisplayIDArray[i];
			
			retval = true;
		}
		
		CFRelease(displayInfo);
		IOObjectRelease(servicePort);
	}
	
	return retval;
}

void getScreenInfoForDisplay(io_service_t service, NSString **displayName, SInt32 *vendorID, SInt32 *productID, SInt32 *serialNumber, NSData **edid, NSString **prefsKey)
{
	*displayName = GetLocalizedString(@"Unknown");
	
	CFDictionaryRef displayInfo = IODisplayCreateInfoDictionary(service, kIODisplayOnlyPreferredName);
	//CFStringRef displayNameRef = nil;
	CFNumberRef vendorIDRef = nil;
	CFNumberRef productIDRef = nil;
	CFNumberRef serialNumberRef = nil;
	CFDataRef edidRef = nil;
	CFStringRef prefsKeyRef = nil;
	CFDictionaryRef names = (CFDictionaryRef)CFDictionaryGetValue(displayInfo, CFSTR(kDisplayProductName));
	
	if (names && CFDictionaryGetCount(names) > 0)
	{
		NSDictionary *namesDictionary = (__bridge NSDictionary *)names;
		*displayName = [[namesDictionary valueForKey:namesDictionary.allKeys[0]] retain];
	}
	
	/* if (names && CFDictionaryGetValueIfPresent(names, CFSTR("en_US"), (const void **)&displayNameRef))
	{
		*displayName = [[NSString stringWithString:(__bridge NSString *)displayNameRef] retain];
	} */
	
	Boolean success;
	success = CFDictionaryGetValueIfPresent(displayInfo, CFSTR(kDisplayVendorID), (const void **)&vendorIDRef);
	success &= CFDictionaryGetValueIfPresent(displayInfo, CFSTR(kDisplayProductID), (const void **)&productIDRef);
	
	if (success)
	{
		CFNumberGetValue(vendorIDRef, kCFNumberSInt32Type, vendorID);
		CFNumberGetValue(productIDRef, kCFNumberSInt32Type, productID);
	}
	
	if (CFDictionaryGetValueIfPresent(displayInfo, CFSTR(kDisplaySerialNumber), (const void **)&serialNumberRef))
	{
		CFNumberGetValue(serialNumberRef, kCFNumberSInt32Type, serialNumber);
	}
	
	if (CFDictionaryGetValueIfPresent(displayInfo, CFSTR("IODisplayEDID"), (const void **)&edidRef))
	{
		*edid = [[NSData dataWithData:(__bridge NSData *)edidRef] retain];
	}
	
	if (CFDictionaryGetValueIfPresent(displayInfo, CFSTR("IODisplayPrefsKey"), (const void **)&prefsKeyRef))
	{
		*prefsKey = [[NSString stringWithString:(__bridge NSString *)prefsKeyRef] retain];
	}
	
	CFRelease(displayInfo);
}

// https://github.com/opensource-apple/IOKitTools/blob/master/ioreg.tproj/ioreg.c
bool getDisplayArray(NSMutableArray **displayArray)
{
	*displayArray = [[NSMutableArray array] retain];
	kern_return_t kr;
	io_iterator_t iterator;
	
	kr = IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching("IODisplay"), &iterator);
	
	if (kr == KERN_SUCCESS)
	{
		for (io_service_t device; IOIteratorIsValid(iterator) && (device = IOIteratorNext(iterator)); IOObjectRelease(device))
		{
			io_name_t name {};
			kr = IORegistryEntryGetName(device, name);
			
			if (kr != KERN_SUCCESS)
				continue;
			
			io_service_t framebufferDevice, videoDevice;
			uint32_t framebufferIndex = 0;
			
			if (!getIORegParent(device, @"IOFramebuffer", &framebufferDevice, true))
				continue;
			
			if (!getIORegParent(device, @"IOPCIDevice", &videoDevice, true))
				continue;
			
			io_name_t locationInPlane {};
			kr = IORegistryEntryGetLocationInPlane(framebufferDevice, kIOServicePlane, locationInPlane);
			
			if (kr == KERN_SUCCESS)
				framebufferIndex = [[NSString stringWithUTF8String:locationInPlane] intValue];
			
			io_string_t videoPath {};
			NSString *videoPathString = nil;
			kr = IORegistryEntryGetPath(videoDevice, kIOServicePlane, videoPath);
			
			if (kr == KERN_SUCCESS)
				videoPathString = [NSString stringWithCString:videoPath encoding:NSASCIIStringEncoding];

			uint32_t port = 0;
			uint32_t videoVendorID = 0, videoDeviceID = 0, videoID = 0;
			
			CFMutableDictionaryRef framebufferPropertiesRef = 0;
			kr = IORegistryEntryCreateCFProperties(framebufferDevice, &framebufferPropertiesRef, kCFAllocatorDefault, kNilOptions);
			
			if (kr == KERN_SUCCESS)
			{
				NSDictionary *framebufferProperties = (__bridge NSDictionary *)framebufferPropertiesRef;
				
				port = properyToUInt32([framebufferProperties objectForKey:@"port-number"]);
				
				CFRelease(framebufferPropertiesRef);
			}
			
			CFMutableDictionaryRef videoDevicePropertiesRef = 0;
			kr = IORegistryEntryCreateCFProperties(videoDevice, &videoDevicePropertiesRef, kCFAllocatorDefault, kNilOptions);
			
			if (kr == KERN_SUCCESS)
			{
				NSDictionary *videoDeviceProperties = (__bridge NSDictionary *)videoDevicePropertiesRef;
				
				NSData *deviceID = [videoDeviceProperties objectForKey:@"device-id"];
				NSData *vendorID = [videoDeviceProperties objectForKey:@"vendor-id"];
				
				videoVendorID = getUInt32FromData(vendorID);
				videoDeviceID = getUInt32FromData(deviceID);
				videoID = (videoDeviceID << 16) | videoVendorID;
				
				CFRelease(videoDevicePropertiesRef);
			}
			
			NSString *screenName = [NSString string];
			bool isInternal = [[NSString stringWithUTF8String:name] isEqualToString:@"AppleBacklightDisplay"];
			SInt32 vendorID = 0, productID = 0, serialNumber = 0;
			NSData *edid = nil;
			NSString *prefsKey = nil;
			NSMutableArray *resolutionsArray = [NSMutableArray array];
			CGDirectDisplayID directDisplayID = 0;
			getScreenInfoForDisplay(device, &screenName, &vendorID, &productID, &serialNumber, &edid, &prefsKey);
			getScreenNumberForDisplay(vendorID, productID, serialNumber, &directDisplayID);
			Display *display = [[[Display alloc] initWithName:screenName index:framebufferIndex port:port vendorID:(uint32_t)vendorID productID:(uint32_t)productID serialNumber:(uint32_t)serialNumber edid:edid prefsKey:prefsKey isInternal:isInternal videoPath:videoPathString videoID:videoID resolutionsArray:resolutionsArray directDisplayID:directDisplayID] autorelease];
			
			[*displayArray addObject:display];
			
			IOObjectRelease(videoDevice);
		}
	}
	
	IOObjectRelease(iterator);
	
	return true;
}

bool hasIORegChildEntry(io_registry_entry_t device, NSString *findClassName)
{
	kern_return_t kr;
	io_iterator_t childIterator;
	
	kr = IORegistryEntryGetChildIterator(device, kIOServicePlane, &childIterator);
	
	if (kr != KERN_SUCCESS)
		return false;
	
	for (io_service_t childDevice; IOIteratorIsValid(childIterator) && (childDevice = IOIteratorNext(childIterator)); IOObjectRelease(childDevice))
	{
		io_name_t childClassName {};
		kr = IOObjectGetClass(childDevice, childClassName);
		
		if (kr == KERN_SUCCESS)
		{
			if (CFStringCompare((__bridge CFStringRef)findClassName, (__bridge CFStringRef)[NSString stringWithUTF8String:childClassName], 0) == kCFCompareEqualTo)
			{
				IOObjectRelease(childIterator);
				IOObjectRelease(childDevice);
				
				return true;
			}
		}
		
		if (hasIORegChildEntry(childDevice, findClassName))
		{
			IOObjectRelease(childIterator);
			IOObjectRelease(childDevice);
			
			return true;
		}
	}
	
	return false;
}

bool hasIORegClassEntry(NSString *findClassName)
{
	io_registry_entry_t device = IORegistryEntryFromPath(kIOMasterPortDefault, kIOServicePlane ":/");
	
	if (hasIORegChildEntry(device, findClassName))
	{
		IOObjectRelease(device);
		
		return true;
	}
	
	IOObjectRelease(device);
	
	return false;
}

bool getIORegString(NSString *service, NSString *name, NSString **value)
{
	io_service_t ioService = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching([service UTF8String]));
	
	if (!ioService)
		return false;
	
	CFTypeRef data = IORegistryEntryCreateCFProperty(ioService, (__bridge CFStringRef)name, kCFAllocatorDefault, 0);
	
	IOObjectRelease(ioService);
	
	if (data == nil)
		return false;
	
	CFTypeID type = CFGetTypeID(data);
	
	if (type == CFStringGetTypeID())
	{
		*value = (__bridge NSString *)data;
		
		return true;
	}
	else if (type == CFDataGetTypeID())
		*value = [NSString stringWithUTF8String:(const char *)[(__bridge NSData *)data bytes]];
	
	CFRelease(data);
	
	return true;
}

bool getIORegArray(NSString *service, NSString *name, NSArray **value)
{
	io_service_t ioService = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching([service UTF8String]));
	
	if (!ioService)
		return false;
	
	CFTypeRef data = IORegistryEntryCreateCFProperty(ioService, (__bridge CFStringRef)name, kCFAllocatorDefault, 0);
	
	IOObjectRelease(ioService);
	
	if (data == nil)
		return false;
	
	*value = (__bridge NSArray *)data;
	
	return true;
}

bool getIORegDictionary(NSString *service, NSString *name, NSDictionary **value)
{
	io_service_t ioService = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching([service UTF8String]));
	
	if (!ioService)
		return false;
	
	CFTypeRef data = IORegistryEntryCreateCFProperty(ioService, (__bridge CFStringRef)name, kCFAllocatorDefault, 0);
	
	IOObjectRelease(ioService);
	
	if (data == nil)
		return false;
	
	*value = (__bridge NSDictionary *)data;
	
	return true;
}

bool getIORegPCIDeviceUInt32(NSString *pciName, NSString *propertyName, uint32_t *propertyValue)
{
	CFTypeRef property = nil;
	
	if (!getIORegProperty(@"IOPCIDevice", pciName, propertyName, &property))
		return false;
	
	*propertyValue = *(const uint32_t *)CFDataGetBytePtr((CFDataRef)property);
	
	CFRelease(property);
	
	return true;
}

bool getIORegPCIDeviceNSData(NSString *pciName, NSString *propertyName, NSData **propertyValue)
{
	CFTypeRef property = nil;
	
	if (!getIORegProperty(@"IOPCIDevice", pciName, propertyName, &property))
		return false;
	
	*propertyValue = (__bridge NSData *)property;
	
	CFRelease(property);
	
	return true;
}

bool getPlatformTableNative(NSData **nativePlatformTable)
{
	CFTypeRef property = nil;
	
	if (!getIORegProperty(@"IOService:/IOResources/WhateverGreen", @"platform-table-native", &property))
		return false;
	
	*nativePlatformTable = (__bridge NSData *)property;
	
	return true;
}

bool getPlatformTablePatched(NSData **patchedPlatformTable)
{
	CFTypeRef property = nil;
	
	if (!getIORegProperty(@"IOService:/IOResources/WhateverGreen", @"platform-table-patched", &property))
		return false;
	
	*patchedPlatformTable = (__bridge NSData *)property;
	
	return true;
}

bool getPlatformID(uint32_t *platformID)
{
	if (!getIORegPCIDeviceUInt32(@"IGPU", @"AAPL,ig-platform-id", platformID))
		if (!getIORegPCIDeviceUInt32(@"IGPU", @"AAPL,snb-platform-id", platformID))
			return false;
	
	return true;
}

