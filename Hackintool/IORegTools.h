//
//  IORegTools.h
//  Hackintool
//
//  Created by Ben Baker on 1/29/19.
//  Copyright © 2019 Ben Baker. All rights reserved.
//

#ifndef IORegTools_h
#define IORegTools_h

#import "AppDelegate.h"
#include <sys/types.h>

#define PNP_EISA_ID_MASK          0xffff
#define PNP_EISA_ID_CONST         0x41d0
#define EISA_ID_TO_NUM(_Id)       ((_Id) >> 16)

bool getDevicePath(NSString *search, NSString **devicePath);
bool getIORegChild(io_service_t device, NSString *name, io_service_t *foundDevice, bool recursive);
bool getIORegChild(io_service_t device, NSArray *nameArray, io_service_t *foundDevice, uint32_t *foundIndex, bool recursive);
bool getIORegParent(io_service_t device, NSString *name, io_service_t *foundDevice, bool recursive);
bool getIORegParent(io_service_t device, NSArray *nameArray, io_service_t *foundDevice, uint32_t *foundIndex, bool useClass, bool recursive);
bool getIORegParent(io_service_t device, NSArray *nameArray, io_service_t *foundDevice, bool useClass, bool recursive);
bool getAPFSPhysicalStoreBSDName(NSString *mediaUUID, NSString **bsdName);
bool getIORegUSBPortsPropertyDictionaryArray(NSMutableArray **propertyDictionaryArray);
bool getIORegUSBControllersPropertyDictionaryArray(NSMutableArray **propertyDictionaryArray);
bool getUSBControllerInfoForUSBDevice(uint64_t idRegistry, uint32_t *usbControllerID, uint32_t *usbControllerLocationID, uint32_t *port);
bool getUSBControllerInfoForUSBDevice(uint32_t idLocation, uint32_t idVendor, uint32_t idProduct, uint32_t *usbControllerID, uint32_t *usbControllerLocationID, uint32_t *port);
bool getIORegAudioDeviceArray(NSMutableArray **propertyDictionaryArray);
NSString *propertyToString(id value);
uint32_t propertyToUInt32(id value);
uint32_t nameToUInt32(NSString *name);
bool getIORegPCIDeviceArray(NSMutableArray **pciDeviceArray);
bool getIORegNetworkArray(NSMutableArray **networkInterfacesArray);
bool getIORegBluetoothArray(NSMutableArray **propertyArray);
bool getIORegGraphicsArray(NSMutableArray **graphicsArray);
bool getIORegStorageArray(NSMutableArray **storageArray);
bool getIORegPropertyDictionaryArrayWithParent(NSString *serviceName, NSString *parentName, NSMutableArray **propertyArray);
bool getIORegPropertyDictionaryArrayWithChild(NSString *serviceName, NSString *childName, NSMutableArray **propertyArray);
bool getIORegPropertyDictionary(NSString *serviceName, NSArray *entryNameArray, NSMutableDictionary **propertyDictionary, uint32_t *foundIndex);
bool getIORegPropertyDictionary(NSString *serviceName, NSString *entryName, NSMutableDictionary **propertyDictionary);
bool getIORegPropertyDictionary(NSString *serviceName, NSString *entryName, NSArray *classNameArray, NSMutableDictionary **propertyDictionary);
//bool getIORegPropertyDictionaryArray(NSString *serviceName, NSMutableArray **propertyDictionaryArray, bool recursive);
bool getIORegPropertyDictionaryArray(NSString *serviceName, NSMutableArray **propertyDictionaryArray);
bool getIORegPropertyDictionary(NSString *serviceName, NSString *entryName, NSMutableDictionary **propertyDictionary);
bool hasACPIEntry(NSString *name);
bool hasIORegEntry(NSString *path);
bool getIORegProperty(NSString *path, NSString *propertyName, CFTypeRef *property);
bool getIORegProperties(NSString *path, NSMutableDictionary **propertyDictionary);
bool getIORegProperty(NSString *serviceName, NSString *entryName, NSString *propertyName, CFTypeRef *property);
bool getIGPUModelAndVRAM(NSString **gpuModel, uint32_t &gpuDeviceID, uint32_t &gpuVendorID, mach_vm_size_t &vramSize, mach_vm_size_t &vramFree);
bool getDisplayArray(NSMutableArray **displayArray);
bool hasIORegClassEntry(NSString *findClassName);
bool getIORegString(NSString *service, NSString *name, NSString **value);
bool getIORegArray(NSString *service, NSString *name, NSArray **value);
bool getIORegDictionary(NSString *service, NSString *name, NSDictionary **value);
bool getIORegPCIDeviceUInt32(NSString *pciName, NSString *propertyName, uint32_t *propertyValue);
bool getIORegPCIDeviceNSData(NSString *pciName, NSString *propertyName, NSData **propertyValue);
bool getPlatformTableNative(NSData **nativePlatformTable);
bool getPlatformTablePatched(NSData **patchedPlatformTable);
bool getPlatformID(uint32_t *platformID);
NSString *getASPMString(uint32_t aspm);

#endif /* IORegTools_hpp */
