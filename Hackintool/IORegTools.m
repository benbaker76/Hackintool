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
#include <IOKit/usb/USBSpec.h>
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
	io_iterator_t childIterator;
	kern_return_t kr = IORegistryEntryCreateIterator(device, kIOServicePlane, (recursive ? kIORegistryIterateRecursively : 0), &childIterator);
	
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
	}
	
	return false;
}

bool getIORegChild(io_service_t device, NSArray *nameArray, io_service_t *foundDevice, uint32_t *foundIndex, bool recursive)
{
	io_iterator_t childIterator;
	kern_return_t kr = IORegistryEntryCreateIterator(device, kIOServicePlane, (recursive ? kIORegistryIterateRecursively : 0), &childIterator);
	
	if (kr != KERN_SUCCESS)
		return false;
	
	for (io_service_t childDevice; IOIteratorIsValid(childIterator) && (childDevice = IOIteratorNext(childIterator)); IOObjectRelease(childDevice))
	{
		for (int i = 0; i < [nameArray count]; i++)
		{
			if (IOObjectConformsTo(childDevice, [[nameArray objectAtIndex:i] UTF8String]))
			{
				*foundDevice = childDevice;
				*foundIndex = i;
				
				IOObjectRelease(childIterator);
				
				return true;
			}
		}
	}
	
	return false;
}

bool getIORegParentArray(io_service_t device, NSArray *nameArray, NSMutableArray *parentArray, bool recursive)
{
    bool retVal = false;
    io_iterator_t parentIterator;
    kern_return_t kr = IORegistryEntryCreateIterator(device, kIOServicePlane, (recursive ? kIORegistryIterateRecursively : 0) | kIORegistryIterateParents, &parentIterator);
    
    if (kr != KERN_SUCCESS)
        return false;
    
    for (io_service_t parentDevice; IOIteratorIsValid(parentIterator) && (parentDevice = IOIteratorNext(parentIterator));)
    {
        id parentObject = @(parentDevice);
        
        for (int i = 0; i < [nameArray count]; i++)
        {
            if (IOObjectConformsTo(parentDevice, [[nameArray objectAtIndex:i] UTF8String]))
            {
                [parentArray addObject:parentObject];
                
                retVal = true;
            }
        }
    }
    
    IOObjectRelease(parentIterator);
    
    return retVal;
}

bool getIORegParentArray(io_service_t device, NSString *name, NSMutableArray *parentArray, bool recursive)
{
    return getIORegParentArray(device, @[name], parentArray, recursive);
}


bool getIORegParent(io_service_t device, NSString *name, io_service_t *foundDevice, bool recursive)
{
	io_iterator_t parentIterator;
	kern_return_t kr = IORegistryEntryCreateIterator(device, kIOServicePlane, (recursive ? kIORegistryIterateRecursively : 0) | kIORegistryIterateParents, &parentIterator);
	
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
	}
	
	return false;
}

bool getIORegParent(io_service_t device, NSArray *nameArray, io_service_t *foundDevice, uint32_t *foundIndex, bool useClass, bool recursive)
{
	io_iterator_t parentIterator;
	kern_return_t kr = IORegistryEntryCreateIterator(device, kIOServicePlane, (recursive ? kIORegistryIterateRecursively : 0) | kIORegistryIterateParents, &parentIterator);
	
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

bool getIORegUSBPortsPropertyDictionaryArray(NSMutableArray **propertyDictionaryArray)
{
	*propertyDictionaryArray = [NSMutableArray array];
	io_iterator_t iterator;
	
	kern_return_t kr = IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching("AppleUSBHostPort"), &iterator);
	
	if (kr != KERN_SUCCESS)
		return false;
	
	for (io_service_t usbPort; IOIteratorIsValid(iterator) && (usbPort = IOIteratorNext(iterator)); IOObjectRelease(usbPort))
	{
		CFMutableDictionaryRef usbPortPropertyDictionaryRef = 0;
		
		kr = IORegistryEntryCreateCFProperties(usbPort, &usbPortPropertyDictionaryRef, kCFAllocatorDefault, kNilOptions);
		
		if (kr == KERN_SUCCESS)
		{
			NSMutableDictionary *usbPortPropertyDictionary = (__bridge NSMutableDictionary *)usbPortPropertyDictionaryRef;
	
			io_service_t controller;
			
			if (getIORegParent(usbPort, @"AppleUSBHostController", &controller, true))
			{
				io_name_t controllerName {};
				kr = IORegistryEntryGetName(controller, controllerName);
				
				if (kr == KERN_SUCCESS)
				{
					CFMutableDictionaryRef controllerPropertyDictionaryRef = 0;
					
					kr = IORegistryEntryCreateCFProperties(controller, &controllerPropertyDictionaryRef, kCFAllocatorDefault, kNilOptions);
					
					if (kr == KERN_SUCCESS)
					{
						NSMutableDictionary *controllerPropertyDictionary = (__bridge NSMutableDictionary *)controllerPropertyDictionaryRef;
						
						io_service_t pciDevice;
						
						if (getIORegParent(controller, @"IOPCIDevice", &pciDevice, true))
						{
							CFMutableDictionaryRef pciDevicePropertyDictionaryRef = 0;
							
							kr = IORegistryEntryCreateCFProperties(pciDevice, &pciDevicePropertyDictionaryRef, kCFAllocatorDefault, kNilOptions);
							
							if (kr == KERN_SUCCESS)
							{
								NSMutableDictionary *pciDevicePropertyDictionary = (__bridge NSMutableDictionary *)pciDevicePropertyDictionaryRef;
						
								uint32_t deviceID = propertyToUInt32([pciDevicePropertyDictionary objectForKey:@"device-id"]);
								uint32_t vendorID = propertyToUInt32([pciDevicePropertyDictionary objectForKey:@"vendor-id"]);
								uint32_t locationID = propertyToUInt32([controllerPropertyDictionary objectForKey:@"locationID"]);
								NSString *ioClass = [controllerPropertyDictionary objectForKey:@"IOClass"];
								
								[usbPortPropertyDictionary setValue:[NSString stringWithUTF8String:controllerName] forKey:@"UsbController"];
								[usbPortPropertyDictionary setValue:ioClass forKey:@"UsbControllerIOClass"];
								[usbPortPropertyDictionary setValue:@((deviceID << 16) | vendorID) forKey:@"UsbControllerID"];
								[usbPortPropertyDictionary setValue:@(locationID >> 24) forKey:@"UsbControllerLocationID"];
								
								io_service_t hubDevice;

								if (getIORegParent(usbPort, @"AppleUSBHub", &hubDevice, true))
								{
									//bool hubIsInternal = IOObjectConformsTo(hubDevice, "AppleUSB20InternalHub");
								
									io_name_t hubClassName {};
									kr = IOObjectGetClass(hubDevice, hubClassName);
									
									if (kr == KERN_SUCCESS)
									{
										CFMutableDictionaryRef hubPropertyDictionaryRef = 0;
										
										kr = IORegistryEntryCreateCFProperties(hubDevice, &hubPropertyDictionaryRef, kCFAllocatorDefault, kNilOptions);
										
										if (kr == KERN_SUCCESS)
										{
											NSMutableDictionary *hubPropertyDictionary = (__bridge NSMutableDictionary *)hubPropertyDictionaryRef;
											
											NSNumber *hubLocationID = [hubPropertyDictionary objectForKey:@"locationID"];
											
											[usbPortPropertyDictionary setValue:[NSString stringWithUTF8String:hubClassName] forKey:@"HubName"];
											[usbPortPropertyDictionary setValue:hubLocationID forKey:@"HubLocation"];
											//[propertyDictionary setValue:[NSNumber numberWithBool:hubIsInternal] forKey:@"HubIsInternal"];

											//NSLog(@"PortName: %s LocationID: 0x%08X HubName: %s HubLocation: 0x%8X HubIsInternal: %d", name, [locationID unsignedIntValue], hubClassName, [hubLocationID unsignedIntValue], hubIsInternal);
										}
									}
									
									IOObjectRelease(hubDevice);
								}
								
								//NSLog(@"PortName: %@ LocationID: 0x%08X UsbController: %s", portName, [locationID unsignedIntValue], parentName);
								
								[*propertyDictionaryArray addObject:usbPortPropertyDictionary];
							}
							
							IOObjectRelease(pciDevice);
						}
					}
				}
				
				IOObjectRelease(controller);
			}
		}
	}
	
	IOObjectRelease(iterator);
	
	return ([*propertyDictionaryArray count] > 0);
}

bool getIORegUSBControllersPropertyDictionaryArray(NSMutableArray **propertyDictionaryArray)
{
	*propertyDictionaryArray = [NSMutableArray array];
	io_iterator_t iterator;
	
	kern_return_t kr = IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching("AppleUSBHostController"), &iterator);
	
	if (kr != KERN_SUCCESS)
		return false;
	
	for (io_service_t controller; IOIteratorIsValid(iterator) && (controller = IOIteratorNext(iterator)); IOObjectRelease(controller))
	{
		io_name_t controllerName {};
		kr = IORegistryEntryGetName(controller, controllerName);
		
		if (kr == KERN_SUCCESS)
		{
			CFMutableDictionaryRef controllerPropertyDictionaryRef = 0;
			
			kr = IORegistryEntryCreateCFProperties(controller, &controllerPropertyDictionaryRef, kCFAllocatorDefault, kNilOptions);
			
			if (kr == KERN_SUCCESS)
			{
				NSMutableDictionary *controllerPropertyDictionary = (__bridge NSMutableDictionary *)controllerPropertyDictionaryRef;
				
				io_service_t pciDevice;
				
				if (getIORegParent(controller, @"IOPCIDevice", &pciDevice, true))
				{
					CFMutableDictionaryRef pciDevicePropertyDictionaryRef = 0;
					
					kr = IORegistryEntryCreateCFProperties(pciDevice, &pciDevicePropertyDictionaryRef, kCFAllocatorDefault, kNilOptions);
					
					if (kr == KERN_SUCCESS)
					{
						NSMutableDictionary *pciDevicePropertyDictionary = (__bridge NSMutableDictionary *)pciDevicePropertyDictionaryRef;

						uint32_t deviceID = propertyToUInt32([pciDevicePropertyDictionary objectForKey:@"device-id"]);
						uint32_t vendorID = propertyToUInt32([pciDevicePropertyDictionary objectForKey:@"vendor-id"]);
						uint32_t locationID = propertyToUInt32([controllerPropertyDictionary objectForKey:@"locationID"]);
						
						[controllerPropertyDictionary setValue:[NSString stringWithUTF8String:controllerName] forKey:@"Name"];
						[controllerPropertyDictionary setValue:@((deviceID << 16) | vendorID) forKey:@"DeviceID"];
						[controllerPropertyDictionary setValue:@(locationID >> 24) forKey:@"ID"];
						
						[*propertyDictionaryArray addObject:controllerPropertyDictionary];
					}
				
					IOObjectRelease(pciDevice);
				}
			}
		}
	}
	
	IOObjectRelease(iterator);
	
	return ([*propertyDictionaryArray count] > 0);
}

bool getUSBControllerInfoForUSBDevice(uint64_t idRegistry, uint32_t *usbControllerID, uint32_t *usbControllerLocationID, uint32_t *port)
{
	bool retVal = false;
	io_iterator_t iterator;
	
	kern_return_t kr = IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching("AppleUSBHostPort"), &iterator);
	
	if (kr != KERN_SUCCESS)
		return false;
	
	for (io_service_t usbPort; IOIteratorIsValid(iterator) && (usbPort = IOIteratorNext(iterator)); IOObjectRelease(usbPort))
	{
		CFMutableDictionaryRef usbPortPropertyDictionaryRef = 0;
		
		kr = IORegistryEntryCreateCFProperties(usbPort, &usbPortPropertyDictionaryRef, kCFAllocatorDefault, kNilOptions);
		
		if (kr == KERN_SUCCESS)
		{
			NSMutableDictionary *usbPortPropertyDictionary = (__bridge NSMutableDictionary *)usbPortPropertyDictionaryRef;
			
			uint32_t portNum = propertyToUInt32([usbPortPropertyDictionary objectForKey:@"port"]);
		
			io_service_t usbDevice;
			
			if (getIORegChild(usbPort, @"IOUSBDevice", &usbDevice, true))
			{
				uint64_t registryID;
				
				kr = IORegistryEntryGetRegistryEntryID(usbDevice, &registryID);
				
				if (registryID == idRegistry)
				{
					io_service_t controller;
					
					if (getIORegParent(usbDevice, @"AppleUSBHostController", &controller, true))
					{
						CFMutableDictionaryRef controllerPropertyDictionaryRef = 0;
							
						kr = IORegistryEntryCreateCFProperties(controller, &controllerPropertyDictionaryRef, kCFAllocatorDefault, kNilOptions);
							
						if (kr == KERN_SUCCESS)
						{
							NSMutableDictionary *controllerPropertyDictionary = (__bridge NSMutableDictionary *)controllerPropertyDictionaryRef;
							
							io_service_t pciDevice;
							
							if (getIORegParent(controller, @"IOPCIDevice", &pciDevice, true))
							{
								CFMutableDictionaryRef parentPropertyDictionaryRef = 0;
								
								kr = IORegistryEntryCreateCFProperties(pciDevice, &parentPropertyDictionaryRef, kCFAllocatorDefault, kNilOptions);
								
								if (kr == KERN_SUCCESS)
								{
									NSMutableDictionary *parentPropertyDictionary = (__bridge NSMutableDictionary *)parentPropertyDictionaryRef;
									
									uint32_t controllerDeviceID = propertyToUInt32([parentPropertyDictionary objectForKey:@"device-id"]);
									uint32_t controllerVendorID = propertyToUInt32([parentPropertyDictionary objectForKey:@"vendor-id"]);
									uint32_t locationID = propertyToUInt32([controllerPropertyDictionary objectForKey:@"locationID"]);
									
									*usbControllerID = (controllerDeviceID << 16) | controllerVendorID;
									*usbControllerLocationID = (locationID >> 24);
									*port = portNum;
									
									retVal = true;
								}
								
								IOObjectRelease(pciDevice);
							}
						}
						
						IOObjectRelease(controller);
					}
				}
				
				IOObjectRelease(usbDevice);
			}
		}
	}
	
	IOObjectRelease(iterator);
	
	return retVal;
}

/* bool getUSBControllerIDInfoForUSBDevice(uint64_t idRegistry, uint32_t *usbControllerID, uint32_t *port)
{
	bool retVal = false;
	io_iterator_t iterator;
	
	kern_return_t kr = IOServiceGetMatchingServices(kIOMasterPortDefault, IORegistryEntryIDMatching(idRegistry), &iterator);
	
	if (kr != KERN_SUCCESS)
		return false;
	
	for (io_service_t device; IOIteratorIsValid(iterator) && (device = IOIteratorNext(iterator)); IOObjectRelease(device))
	{
		io_service_t portDevice;
		
		if (getIORegParent(device, @"AppleUSBHostPort", &portDevice, true))
		{
			CFMutableDictionaryRef portPropertyDictionaryRef = 0;
			
			kr = IORegistryEntryCreateCFProperties(portDevice, &portPropertyDictionaryRef, kCFAllocatorDefault, kNilOptions);
			
			if (kr == KERN_SUCCESS)
			{
				NSMutableDictionary *portPropertyDictionary = (__bridge NSMutableDictionary *)portPropertyDictionaryRef;
				
				uint32_t portNum = propertyToUInt32([portPropertyDictionary objectForKey:@"port"]);
				
				io_service_t controllerDevice;
				
				if (getIORegParent(device, @"IOPCIDevice", &controllerDevice, true))
				{
					CFMutableDictionaryRef controllerPropertyDictionaryRef = 0;
					
					kr = IORegistryEntryCreateCFProperties(controllerDevice, &controllerPropertyDictionaryRef, kCFAllocatorDefault, kNilOptions);
					
					if (kr == KERN_SUCCESS)
					{
						NSMutableDictionary *controllerPropertyDictionary = (__bridge NSMutableDictionary *)controllerPropertyDictionaryRef;
						
						uint32_t controllerDeviceID = propertyToUInt32([controllerPropertyDictionary objectForKey:@"device-id"]);
						uint32_t controllerVendorID = propertyToUInt32([controllerPropertyDictionary objectForKey:@"vendor-id"]);
						
						*port = portNum;
						*usbControllerID = (controllerDeviceID << 16) | controllerVendorID;
						
						retVal = true;
					}
					
					IOObjectRelease(controllerDevice);
				}
			}
			
			IOObjectRelease(portDevice);
		}
	}
	
	IOObjectRelease(iterator);
	
	return retVal;
} */

bool getUSBControllerInfoForUSBDevice(uint32_t idLocation, uint32_t idVendor, uint32_t idProduct, uint32_t *usbControllerID, uint32_t *usbControllerLocationID, uint32_t *port)
{
	bool retVal = false;
	io_iterator_t iterator;
	
	kern_return_t kr = IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching("AppleUSBHostPort"), &iterator);
	
	if (kr != KERN_SUCCESS)
		return false;
	
	for (io_service_t usbPort; IOIteratorIsValid(iterator) && (usbPort = IOIteratorNext(iterator)); IOObjectRelease(usbPort))
	{
		CFMutableDictionaryRef usbPortPropertyDictionaryRef = 0;
		
		kr = IORegistryEntryCreateCFProperties(usbPort, &usbPortPropertyDictionaryRef, kCFAllocatorDefault, kNilOptions);
		
		if (kr == KERN_SUCCESS)
		{
			NSMutableDictionary *usbPortPropertyDictionary = (__bridge NSMutableDictionary *)usbPortPropertyDictionaryRef;
			
			uint32_t portNum = propertyToUInt32([usbPortPropertyDictionary objectForKey:@"port"]);
		
			io_service_t usbDevice;
			
			if (getIORegChild(usbPort, @"IOUSBDevice", &usbDevice, true))
			{
				CFMutableDictionaryRef usbDevicePropertyDictionaryRef = 0;
					
				kr = IORegistryEntryCreateCFProperties(usbDevice, &usbDevicePropertyDictionaryRef, kCFAllocatorDefault, kNilOptions);
					
				if (kr == KERN_SUCCESS)
				{
					NSMutableDictionary *usbDevicePropertyDictionary = (__bridge NSMutableDictionary *)usbDevicePropertyDictionaryRef;
					
					uint32_t locationID = propertyToUInt32([usbDevicePropertyDictionary objectForKey:@"locationID"]);
					uint32_t vendorID = propertyToUInt32([usbDevicePropertyDictionary objectForKey:@"idVendor"]);
					uint32_t productID = propertyToUInt32([usbDevicePropertyDictionary objectForKey:@"idProduct"]);
					
					if ((idLocation == locationID) && (idVendor == vendorID) && (idProduct == productID))
					{
						io_service_t controller;
						
						if (getIORegParent(usbDevice, @"AppleUSBHostController", &controller, true))
						{
							CFMutableDictionaryRef controllerPropertyDictionaryRef = 0;
								
							kr = IORegistryEntryCreateCFProperties(controller, &controllerPropertyDictionaryRef, kCFAllocatorDefault, kNilOptions);
								
							if (kr == KERN_SUCCESS)
							{
								NSMutableDictionary *controllerPropertyDictionary = (__bridge NSMutableDictionary *)controllerPropertyDictionaryRef;
								
								io_service_t pciDevice;
								
								if (getIORegParent(controller, @"IOPCIDevice", &pciDevice, true))
								{
									CFMutableDictionaryRef parentPropertyDictionaryRef = 0;
									
									kr = IORegistryEntryCreateCFProperties(pciDevice, &parentPropertyDictionaryRef, kCFAllocatorDefault, kNilOptions);
									
									if (kr == KERN_SUCCESS)
									{
										NSMutableDictionary *parentPropertyDictionary = (__bridge NSMutableDictionary *)parentPropertyDictionaryRef;
										
										uint32_t controllerDeviceID = propertyToUInt32([parentPropertyDictionary objectForKey:@"device-id"]);
										uint32_t controllerVendorID = propertyToUInt32([parentPropertyDictionary objectForKey:@"vendor-id"]);
										uint32_t locationID = propertyToUInt32([controllerPropertyDictionary objectForKey:@"locationID"]);
										
										*usbControllerID = (controllerDeviceID << 16) | controllerVendorID;
										*usbControllerLocationID = (locationID >> 24);
										*port = portNum;
										
										retVal = true;
									}
									
									IOObjectRelease(pciDevice);
								}
							}
							
							IOObjectRelease(controller);
						}
					}
				}
				
				IOObjectRelease(usbDevice);
			}
		}
	}
	
	IOObjectRelease(iterator);
	
	return retVal;
}

bool getIORegAudioDeviceArray(NSMutableArray **audioDeviceArray)
{
	*audioDeviceArray = [[NSMutableArray array] retain];
	io_iterator_t pciIterator;
	
	kern_return_t kr = IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching("IOPCIDevice"), &pciIterator);
	
	if (kr != KERN_SUCCESS)
		return false;
	
	io_iterator_t iterator;
	
	for (io_service_t pciDevice; IOIteratorIsValid(pciIterator) && (pciDevice = IOIteratorNext(pciIterator)); IOObjectRelease(pciDevice))
	{
		kern_return_t kr = IORegistryEntryCreateIterator(pciDevice, kIOServicePlane, kIORegistryIterateRecursively, &iterator);
		
		if (kr != KERN_SUCCESS)
			continue;
		
		for (io_service_t device; IOIteratorIsValid(iterator) && (device = IOIteratorNext(iterator)); IOObjectRelease(device))
		{
			if (IOObjectConformsTo(device, "IOPCIDevice"))
			{
				IOObjectRelease(device);
				break;
			}
			
			if (!IOObjectConformsTo(device, "IOAudioDevice"))
				continue;
			
			io_name_t className {};
			kr = IOObjectGetClass(device, className);
			
			if (kr != KERN_SUCCESS)
				continue;
			
			CFMutableDictionaryRef propertyDictionaryRef = 0;
			
			kr = IORegistryEntryCreateCFProperties(device, &propertyDictionaryRef, kCFAllocatorDefault, kNilOptions);
			
			if (kr == KERN_SUCCESS)
			{
				NSMutableDictionary *propertyDictionary = (__bridge NSMutableDictionary *)propertyDictionaryRef;
				
				NSString *bundleID = [propertyDictionary objectForKey:@"CFBundleIdentifier"];
				NSString *audioDeviceName = [propertyDictionary objectForKey:@"IOAudioDeviceName"];
				NSString *audioDeviceModelID = [propertyDictionary objectForKey:@"IOAudioDeviceModelID"];
				NSString *audioDeviceManufacturerName = [propertyDictionary objectForKey:@"IOAudioDeviceManufacturerName"];
				uint32_t audioDeviceDeviceID = 0, audioDeviceVendorID = 0;
				uint32_t audioDeviceDeviceIDNew = 0;
				
				if (audioDeviceModelID != nil)
				{
					NSArray *modelIDArray = [audioDeviceModelID componentsSeparatedByString:@":"];
					
					if ([modelIDArray count] == 3)
					{
						NSScanner *deviceIDScanner = [NSScanner scannerWithString:[modelIDArray objectAtIndex:1]];
						NSScanner *productIDScanner = [NSScanner scannerWithString:[modelIDArray objectAtIndex:2]];

						[deviceIDScanner setScanLocation:0];
						[deviceIDScanner scanHexInt:&audioDeviceVendorID];
													   
						[productIDScanner setScanLocation:0];
						[productIDScanner scanHexInt:&audioDeviceDeviceID];
													   
						audioDeviceDeviceIDNew = (audioDeviceVendorID << 16) | audioDeviceDeviceID;
					}
				}
				
				io_service_t parentDevice;
					
				if (getIORegParent(device, @"IOPCIDevice", &parentDevice, true))
				{
					CFMutableDictionaryRef parentPropertyDictionaryRef = 0;
					
					kr = IORegistryEntryCreateCFProperties(parentDevice, &parentPropertyDictionaryRef, kCFAllocatorDefault, kNilOptions);
					
					if (kr == KERN_SUCCESS)
					{
						NSMutableDictionary *parentPropertyDictionary = (__bridge NSMutableDictionary *)parentPropertyDictionaryRef;
						
						uint32_t deviceID = propertyToUInt32([parentPropertyDictionary objectForKey:@"device-id"]);
						uint32_t vendorID = propertyToUInt32([parentPropertyDictionary objectForKey:@"vendor-id"]);
						uint32_t revisionID = propertyToUInt32([parentPropertyDictionary objectForKey:@"revision-id"]);
						uint32_t alcLayoutID = propertyToUInt32([parentPropertyDictionary objectForKey:@"alc-layout-id"]);
						uint32_t subSystemID = propertyToUInt32([parentPropertyDictionary objectForKey:@"subsystem-id"]);
						uint32_t subSystemVendorID = propertyToUInt32([parentPropertyDictionary objectForKey:@"subsystem-vendor-id"]);
						
						uint32_t deviceIDNew = (vendorID << 16) | deviceID;
						uint32_t subDeviceIDNew = (subSystemVendorID << 16) | subSystemID;
						
						AudioDevice *audioDevice = [[AudioDevice alloc] initWithDeviceBundleID:bundleID deviceClass:[NSString stringWithUTF8String:className] audioDeviceName:audioDeviceName audioDeviceManufacturerName:audioDeviceManufacturerName audioDeviceModelID:audioDeviceDeviceIDNew deviceID:deviceIDNew revisionID:revisionID alcLayoutID:alcLayoutID subDeviceID:subDeviceIDNew];

						io_service_t codecDevice;
						
						if (getIORegParent(device, @"IOHDACodecDevice", &codecDevice, true))
						{
							CFMutableDictionaryRef codecPropertyDictionaryRef = 0;
							
							kr = IORegistryEntryCreateCFProperties(codecDevice, &codecPropertyDictionaryRef, kCFAllocatorDefault, kNilOptions);
							
							if (kr == KERN_SUCCESS)
							{
								NSMutableDictionary *codecPropertyDictionary = (__bridge NSMutableDictionary *)codecPropertyDictionaryRef;
								
								audioDevice.digitalAudioCapabilities = [codecPropertyDictionary objectForKey:@"DigitalAudioCapabilities"];
								audioDevice.codecAddress = propertyToUInt32([codecPropertyDictionary objectForKey:@"IOHDACodecAddress"]);
								audioDevice.codecID = propertyToUInt32([codecPropertyDictionary objectForKey:@"IOHDACodecVendorID"]);
								audioDevice.revisionID = propertyToUInt32([codecPropertyDictionary objectForKey:@"IOHDACodecRevisionID"]);
							}
						}
						
						if (getIORegParent(device, @"AppleHDACodec", &codecDevice, true))
						{
							CFMutableDictionaryRef codecPropertyDictionaryRef = 0;
							
							kr = IORegistryEntryCreateCFProperties(codecDevice, &codecPropertyDictionaryRef, kCFAllocatorDefault, kNilOptions);
							
							if (kr == KERN_SUCCESS)
							{
								NSMutableDictionary *codecPropertyDictionary = (__bridge NSMutableDictionary *)codecPropertyDictionaryRef;
								
								NSArray *hdaConfigDefaultArray = [codecPropertyDictionary objectForKey:@"HDAConfigDefault"];
								
								if (hdaConfigDefaultArray != nil && [hdaConfigDefaultArray count] > 0)
									audioDevice.hdaConfigDefaultDictionary = [hdaConfigDefaultArray objectAtIndex:0];
							}
						}
						
						[*audioDeviceArray addObject:audioDevice];
						
						[audioDevice release];
					}
					
					IOObjectRelease(parentDevice);
				}
			}
		}
		
		IOObjectRelease(iterator);
	}
	
	IOObjectRelease(pciIterator);
	
	return ([*audioDeviceArray count] > 0);
}

NSString *propertyToString(id value)
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

uint32_t propertyToUInt32(id value)
{
	if (value == nil)
		return 0;
	
	if ([value isKindOfClass:[NSNumber class]])
		return [value unsignedIntValue];
	else if ([value isKindOfClass:[NSData class]])
	{
		NSData *data = (NSData *)value;
		uint32_t retVal = 0;
		
		memcpy(&retVal, data.bytes, MIN(data.length, 4));
		
		return retVal;
	}
	
	return 0;
}

uint32_t nameToUInt32(NSString *name)
{
	if (![name hasPrefix:@"pci"] || [name rangeOfString:@","].location == NSNotFound)
		return 0;
	
	NSArray *nameArray = [[name stringByReplacingOccurrencesOfString:@"pci" withString:@""] componentsSeparatedByString:@","];
	
	return (uint32_t)(strHexDec([nameArray objectAtIndex:1]) << 16 | strHexDec([nameArray objectAtIndex:0]));
}

bool getDeviceLocation(io_service_t device, uint32_t *deviceNum, uint32_t *functionNum, bool *hasFunction)
{
	*deviceNum = 0;
	*functionNum = 0;
	*hasFunction = false;
	
	io_name_t locationInPlane {};
	kern_return_t kr = IORegistryEntryGetLocationInPlane(device, kIOServicePlane, locationInPlane);
	
	if (kr != KERN_SUCCESS)
		return false;
	
	NSArray *locationArray = [[NSString stringWithUTF8String:locationInPlane] componentsSeparatedByString:@","];
	
	if ([locationArray count] > 0)
	{
		NSScanner *deviceScanner = [NSScanner scannerWithString:locationArray[0]];
		[deviceScanner scanHexInt:deviceNum];
	}
	
	if ([locationArray count] > 1)
	{
		NSScanner *functionScanner = [NSScanner scannerWithString:locationArray[1]];
		[functionScanner scanHexInt:functionNum];
		*hasFunction = true;
	}
	
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
			uint32_t vendorID = propertyToUInt32([propertyDictionary objectForKey:@"vendor-id"]);
			uint32_t deviceID = propertyToUInt32([propertyDictionary objectForKey:@"device-id"]);
			uint32_t subVendorID = propertyToUInt32([propertyDictionary objectForKey:@"subsystem-vendor-id"]);
			uint32_t subDeviceID = propertyToUInt32([propertyDictionary objectForKey:@"subsystem-id"]);
			uint32_t aspm = propertyToUInt32([propertyDictionary objectForKey:@"pci-aspm-default"]);
			uint32_t classCode = propertyToUInt32([propertyDictionary objectForKey:@"class-code"]);
			NSString *_name = propertyToString([propertyDictionary objectForKey:@"name"]);
			NSString *model = propertyToString([propertyDictionary objectForKey:@"model"]);
			NSString *ioName = propertyToString([propertyDictionary objectForKey:@"IOName"]);
			NSString *pciDebug = [propertyDictionary objectForKey:@"pcidebug"];
			//NSString *uid = [propertyDictionary objectForKey:@"_UID"];
			NSString *deviceName = (ioName != nil ? ioName : _name != nil ? _name : @"???");
			
			uint32_t busNum = 0, deviceNum = 0, functionNum = 0, secBridgeNum = 0, subBridgeNum = 0;
			
			getBusID(pciDebug, &busNum, &deviceNum, &functionNum, &secBridgeNum, &subBridgeNum);
			
			NSMutableDictionary *pciDictionary = [NSMutableDictionary dictionary];
		
			uint32_t shadowID = nameToUInt32(deviceName);
			[pciDictionary setObject:!shadowID ? @(vendorID) : @(shadowID & 0xFFFF) forKey:@"ShadowVendor"];
			[pciDictionary setObject:!shadowID ? @(deviceID) : @(shadowID >> 16) forKey:@"ShadowDevice"];
			
			//[pciDictionary setObject:[NSString stringWithUTF8String:name] forKey:@"IORegName"];
			[pciDictionary setObject:deviceName forKey:@"IORegIOName"];
			[pciDictionary setObject:[NSString stringWithUTF8String:path] forKey:@"IORegPath"];
			[pciDictionary setObject:[NSNumber numberWithInt:vendorID] forKey:@"VendorID"];
			[pciDictionary setObject:[NSNumber numberWithInt:deviceID] forKey:@"DeviceID"];
			[pciDictionary setObject:[NSNumber numberWithInt:subVendorID] forKey:@"SubVendorID"];
			[pciDictionary setObject:[NSNumber numberWithInt:subDeviceID] forKey:@"SubDeviceID"];
			//[pciDictionary setObject:aspm forKey:@"ASPM"];
			[pciDictionary setObject:getASPMString(aspm) forKey:@"ASPM"];
			[pciDictionary setObject:[NSNumber numberWithInt:classCode] forKey:@"ClassCode"];
			//[pciDictionary setObject:@"Internal" forKey:@"SlotName"];
			//[pciDictionary setObject:@"???" forKey:@"DevicePath"];
			[pciDictionary setObject:model forKey:@"Model"];
			//[pciDictionary setObject:uid forKey:@"UID"];
			[pciDictionary setObject:[NSString stringWithFormat:@"%02X:%02X.%X", busNum, deviceNum, functionNum] forKey:@"PCIDebug"];
			
			NSString *bundleID = (__bridge NSString *)IORegistryEntrySearchCFProperty(device, kIOServicePlane, CFSTR("CFBundleIdentifier"), kCFAllocatorDefault, kIORegistryIterateRecursively);
			
			if (bundleID == nil)
				bundleID = (__bridge NSString *)IORegistryEntrySearchCFProperty(device, kIOServicePlane, CFSTR("CFBundleIdentifier"), kCFAllocatorDefault, kIORegistryIterateRecursively | kIORegistryIterateParents);

			if (bundleID != nil)
			{
				[pciDictionary setObject:bundleID forKey:@"BundleID"];
				
				[bundleID release];
			}
			
			NSString *devicePath = @"", *slotName = @"", *ioregName = @"";
			bool hasFunction = false;
			
			getDeviceLocation(device, &deviceNum, &functionNum, &hasFunction);
			
			ioregName = (hasFunction ? [NSString stringWithFormat:@"%s@%X,%X", name, deviceNum, functionNum] : [NSString stringWithFormat:@"%s@%X", name, deviceNum]);
			//devicePath = (hasFunction ? [NSString stringWithFormat:@"Pci(0x%X,0x%X)", deviceNum, functionNum] : [NSString stringWithFormat:@"Pci(0x%X)", deviceNum]);
			devicePath = [NSString stringWithFormat:@"Pci(0x%X,0x%X)", deviceNum, functionNum];
			slotName = [NSString stringWithFormat:@"%d,%d", deviceNum, functionNum];
			
			[pciDictionary setObject:@(deviceNum << 16 | functionNum) forKey:@"Address"];
			
			NSMutableArray *parentArray = [NSMutableArray array];
			
			if (getIORegParentArray(device, @"IOPCIDevice", parentArray, true)) // Add IOPCIBridge?
			{
				for (NSNumber *parentNumber in parentArray)
				{
					io_service_t parentDevice = [parentNumber unsignedIntValue];
					io_name_t parentName {};
					
					kr = IORegistryEntryGetName(parentDevice, parentName);
					
					if (kr == KERN_SUCCESS)
					{
                        if (IOObjectConformsTo(parentDevice, "IOPCIDevice"))
                        {
                            getDeviceLocation(parentDevice, &deviceNum, &functionNum, &hasFunction);
                            
                            ioregName = (hasFunction ? [NSString stringWithFormat:@"%s@%X,%X/%@", parentName, deviceNum, functionNum, ioregName] : [NSString stringWithFormat:@"%s@%X/%@", parentName, deviceNum, ioregName]);
                            //devicePath = (hasFunction ? [NSString stringWithFormat:@"Pci(0x%X,0x%X)/%@", deviceNum, functionNum, devicePath] : [NSString stringWithFormat:@"Pci(0x%X)/%@", deviceNum, devicePath]);
                            devicePath = [NSString stringWithFormat:@"Pci(0x%X,0x%X)/%@", deviceNum, functionNum, devicePath];
                            slotName = [NSString stringWithFormat:@"%d,%d/%@", deviceNum, functionNum, slotName];
                        }
                        else
                        {
                            ioregName = [NSString stringWithFormat:@"%s/%@", parentName, ioregName];
                        }
					}
					
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
						case 0x0A03:
							devicePath = [NSString stringWithFormat:@"PciRoot(0x%X)/%@", [uidNumber unsignedIntValue], devicePath];
							break;
						default:
							devicePath = [NSString stringWithFormat:@"Acpi(PNP%04X,0x%X)/%@", EISA_ID_TO_NUM(eisaId), [uidNumber unsignedIntValue], devicePath];
							break;
					}
				}
				else
					devicePath = [NSString stringWithFormat:@"Acpi(0x%08X,0x%X)/%@", eisaId, [uidNumber unsignedIntValue], devicePath];
				
				ioregName = [NSString stringWithFormat:@"/%s@%d/%@", rootName, [uidNumber unsignedIntValue], ioregName];
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
					
					uint32_t deviceID = propertyToUInt32([parentPropertyDictionary objectForKey:@"device-id"]);
					uint32_t vendorID = propertyToUInt32([parentPropertyDictionary objectForKey:@"vendor-id"]);
					NSString *bsdName = [propertyDictionary objectForKey:@"BSD Name"];
					NSNumber *builtIn = [propertyDictionary objectForKey:@"IOBuiltin"];
					
					NSMutableDictionary *networkInterfacesDictionary = [NSMutableDictionary dictionary];
					
					[networkInterfacesDictionary setObject:[NSNumber numberWithInteger:deviceID] forKey:@"DeviceID"];
					[networkInterfacesDictionary setObject:[NSNumber numberWithInteger:vendorID] forKey:@"VendorID"];
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

bool getIORegBluetoothArray(NSMutableArray **propertyArray)
{
	*propertyArray = [NSMutableArray array];
	io_iterator_t iterator;
	
	kern_return_t kr = IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching("AppleUSBHostPort"), &iterator);
	
	if (kr != KERN_SUCCESS)
		return false;
	
	for (io_service_t device; IOIteratorIsValid(iterator) && (device = IOIteratorNext(iterator)); IOObjectRelease(device))
	{
		if (IOObjectConformsTo(device, "AppleUSBHubPort"))
			continue;
		
		io_service_t childDevice;
		
		if (!getIORegChild(device, @"IOUserClient", &childDevice, true))
			continue;
		
		CFMutableDictionaryRef properties = NULL;
		kr = IORegistryEntryCreateCFProperties(childDevice, &properties, kCFAllocatorDefault, kNilOptions);
		
		if (kr != KERN_SUCCESS)
			continue;
		
		CFStringRef usbUserClientOwningTaskName = nil;
		
		if (!CFDictionaryGetValueIfPresent(properties, CFSTR("UsbUserClientOwningTaskName"), (const void **)&usbUserClientOwningTaskName))
			continue;
		
		if (CFStringCompare(usbUserClientOwningTaskName, CFSTR("bluetoothd"), 0) != kCFCompareEqualTo)
		{
			CFRelease(usbUserClientOwningTaskName);
			
			continue;
		}

		io_iterator_t parentIterator;
		kern_return_t kr = IORegistryEntryCreateIterator(childDevice, kIOServicePlane, kIORegistryIterateRecursively | kIORegistryIterateParents, &parentIterator);
		
		if (kr != KERN_SUCCESS)
			continue;
		
		for (io_service_t parentDevice; IOIteratorIsValid(parentIterator) && (parentDevice = IOIteratorNext(parentIterator)); IOObjectRelease(parentDevice))
		{
			if (!IOObjectConformsTo(parentDevice, "IOUSBDevice"))
				continue;
			
			CFMutableDictionaryRef parentProperties = NULL;
			kr = IORegistryEntryCreateCFProperties(parentDevice, &parentProperties, kCFAllocatorDefault, kNilOptions);
			
			if (kr != KERN_SUCCESS)
				continue;
			
			bool skipDevice = NO;
			CFStringRef usbProductString = nil;

			if (CFDictionaryGetValueIfPresent(parentProperties, CFSTR(kUSBProductString), (const void **)&usbProductString))
			{
				if (CFStringCompare(usbProductString, CFSTR("Bluetooth USB Host Controller"), 0) == kCFCompareEqualTo)
				{
					skipDevice = YES;
				}
				
				CFRelease(usbProductString);
			}
			
			CFNumberRef builtIn = nil;

			if (CFDictionaryGetValueIfPresent(parentProperties, CFSTR("Built-in"), (const void **)&builtIn))
			{
				if ([(__bridge NSNumber *)builtIn boolValue])
				{
					// Built-in
				}
				
				CFRelease(builtIn);
			}
			
			if (skipDevice)
				continue;

			CFMutableDictionaryRef parentPropertyDictionaryRef = 0;
			
			kr = IORegistryEntryCreateCFProperties(parentDevice, &parentPropertyDictionaryRef, kCFAllocatorDefault, kNilOptions);
			
			if (kr != KERN_SUCCESS)
				continue;
			
			NSMutableDictionary *parentPropertyDictionary = (__bridge NSMutableDictionary *)parentPropertyDictionaryRef;
			
			[*propertyArray addObject:parentPropertyDictionary];
			
			IOObjectRelease(parentDevice);
			
			break;
		}
		
		IOObjectRelease(parentIterator);
		CFRelease(usbUserClientOwningTaskName);
	}
	
	IOObjectRelease(iterator);
	
	return ([*propertyArray count] > 0);
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
				uint32_t platformID = propertyToUInt32([parentPropertyDictionary objectForKey:@"AAPL,snb-platform-id"]);
				
				if (!platformID)
					platformID = propertyToUInt32([parentPropertyDictionary objectForKey:@"AAPL,ig-platform-id"]);
				
				NSMutableDictionary *graphicsDictionary = [graphicsDictionaryDictionary objectForKey:modelString];
				
				if (graphicsDictionary == nil)
				{
					graphicsDictionary = [NSMutableDictionary dictionary];
					
					[graphicsDictionary setObject:modelString forKey:@"Model"];
					[graphicsDictionary setObject:[NSString stringWithUTF8String:name] forKey:@"Framebuffer"];
					
					if (platformID != 0)
						[graphicsDictionary setObject:[NSString stringWithFormat:@"0x%08X", platformID] forKey:@"Framebuffer"];
					
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

bool getIORegPropertyDictionaryArrayWithChild(NSString *serviceName, NSString *childName, NSMutableArray **propertyArray)
{
	*propertyArray = [NSMutableArray array];
	io_iterator_t iterator;
	
	kern_return_t kr = IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching([serviceName UTF8String]), &iterator);
	
	if (kr != KERN_SUCCESS)
		return false;
	
	for (io_service_t device; IOIteratorIsValid(iterator) && (device = IOIteratorNext(iterator)); IOObjectRelease(device))
	{
		io_service_t childDevice;
		
		if (getIORegChild(device, childName, &childDevice, true))
		{
			CFMutableDictionaryRef childPropertyDictionaryRef = 0;
			
			kr = IORegistryEntryCreateCFProperties(childDevice, &childPropertyDictionaryRef, kCFAllocatorDefault, kNilOptions);
			
			if (kr == KERN_SUCCESS)
			{
				NSMutableDictionary *childPropertyDictionary = (__bridge NSMutableDictionary *)childPropertyDictionaryRef;
				
				[*propertyArray addObject:childPropertyDictionary];
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
	CGDirectDisplayID directDisplayIDArray[10] { 0 };
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
	
		if (!displayInfo)
			continue;

		CFNumberRef vendorIDRef = nil;
		CFNumberRef productIDRef = nil;
		CFNumberRef serialNumberRef = nil;
		SInt32 vendorID = 0, productID = 0, serialNumber = 0;

		if (CFDictionaryGetValueIfPresent(displayInfo, CFSTR(kDisplayVendorID), (const void **)&vendorIDRef))
		{
			CFNumberGetValue(vendorIDRef, kCFNumberSInt32Type, &vendorID);
		}
		
		if (CFDictionaryGetValueIfPresent(displayInfo, CFSTR(kDisplayProductID), (const void **)&productIDRef))
		{
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
	}
	
	return retval;
}

void getScreenInfoForDisplay(io_service_t service, NSString **displayName, uint32_t *vendorID, uint32_t *productID, uint32_t *serialNumber, NSData **edid, NSString **prefsKey)
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
				
				port = propertyToUInt32([framebufferProperties objectForKey:@"port-number"]);
				
				CFRelease(framebufferPropertiesRef);
			}
			
			CFMutableDictionaryRef videoDevicePropertiesRef = 0;
			kr = IORegistryEntryCreateCFProperties(videoDevice, &videoDevicePropertiesRef, kCFAllocatorDefault, kNilOptions);
			
			if (kr == KERN_SUCCESS)
			{
				NSDictionary *videoDeviceProperties = (__bridge NSDictionary *)videoDevicePropertiesRef;
				
				videoDeviceID = propertyToUInt32([videoDeviceProperties objectForKey:@"device-id"]);
				videoVendorID = propertyToUInt32([videoDeviceProperties objectForKey:@"vendor-id"]);
				
				videoID = (videoDeviceID << 16) | videoVendorID;
				
				CFRelease(videoDevicePropertiesRef);
			}
			
			NSString *screenName = [NSString string];
			bool isInternal = [[NSString stringWithUTF8String:name] isEqualToString:@"AppleBacklightDisplay"];
			uint32_t vendorID = 0, productID = 0, serialNumber = 0;
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

NSString *getASPMString(uint32_t aspm)
{
	// http://www.lttconn.com/res/lttconn/pdres/201402/20140218105502619.pdf
	// https://composter.com.ua/documents/PCIe_Protocol_Updates_2011.pdf
	//
	// Hex  Binary  Meaning
	// -------------------------
	// 0    0b00    L0 only
	// 1    0b01    L0s only
	// 2    0b10    L1 only
	// 3    0b11    L1 and L0s
	
	NSArray *aspmArray = @[GetLocalizedString(@"Disabled"), @"L0s", @"L1", @"L0s+L1"];
	
	return [aspmArray objectAtIndex:aspm & 0x3];
}
