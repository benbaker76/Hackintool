//
//  FBUtilities.m
//  Hackintool
//
//  Created by Ben Baker on 7/29/18.
//  Copyright © 2018 Ben Baker. All rights reserved.
//

// https://github.com/opensource-apple/IOKitTools/blob/master/ioreg.tproj/ioreg.c

#include "FBUtilities.h"
#include "AudioDevice.h"
#include <Foundation/Foundation.h>

bool getIntelGenString(NSDictionary *fbDriversDictionary, NSString **intelGenString)
{
	*intelGenString = @"???";
	NSString *framebufferName = nil;
	
	if (!getIORegString(@"AppleIntelMEIDriver", @"CFBundleIdentifier", &framebufferName))
		if (!getIORegString(@"AppleIntelAzulController", @"CFBundleIdentifier", &framebufferName))
			if (!getIORegString(@"AppleIntelFBController", @"CFBundleIdentifier", &framebufferName)) // AppleMEClientController
				if (!getIORegString(@"AppleIntelFramebufferController", @"CFBundleIdentifier", &framebufferName))
					return false;
	
	int intelGen = IGSandyBridge;
	
	for (int i = 0; i < IGCount; i++)
	{
		NSString *kextName = [fbDriversDictionary objectForKey:g_fbNameArray[i]];
		
		if ([framebufferName containsString:kextName])
		{
			intelGen = i;
			break;
		}
	}
	
	*intelGenString = g_fbNameArray[intelGen];
	
	return true;
}

void getConfigDictionary(AppDelegate *appDelegate, NSMutableDictionary *configDictionary, bool forceAll)
{
	Settings settings = [appDelegate settings];
	
	if (settings.PatchGraphicDevice || forceAll)
	{
		NSInteger intelGen = [appDelegate.intelGenComboBox indexOfSelectedItem];
		
		switch (intelGen)
		{
			case IGUnknown:
				break;
			case IGSandyBridge:
				getIGPUProperties<FramebufferSNB>(appDelegate, configDictionary);
				break;
			case IGIvyBridge:
				getIGPUProperties<FramebufferIVB>(appDelegate, configDictionary);
				break;
			case IGHaswell:
				getIGPUProperties<FramebufferHSW>(appDelegate, configDictionary);
				break;
			case IGBroadwell:
				getIGPUProperties<FramebufferBDW>(appDelegate, configDictionary);
				break;
			case IGSkylake:
			case IGKabyLake:
				getIGPUProperties<FramebufferSKL>(appDelegate, configDictionary);
				break;
			case IGCoffeeLake:
				getIGPUProperties<FramebufferCFL>(appDelegate, configDictionary);
				break;
			case IGCannonLake:
				getIGPUProperties<FramebufferCNL>(appDelegate, configDictionary);
				break;
			case IGIceLakeLP:
				getIGPUProperties<FramebufferICLLP>(appDelegate, configDictionary);
				break;
			case IGIceLakeHP:
				getIGPUProperties<FramebufferICLHP>(appDelegate, configDictionary);
				break;
		}
	}
	
	if (settings.PatchAudioDevice || forceAll)
	{
		NSArray *audioArray = @[@"HDEF", @"ALZA", @"AZAL", @"HDAS", @"CAVS"];
		
		for (NSString *name in audioArray)
			getAudioProperties(appDelegate, name, configDictionary);
	}
		
	if (settings.PatchPCIDevices || forceAll)
		getPCIProperties(appDelegate, configDictionary);
	
	injectUseIntelHDMI(appDelegate, configDictionary);
	injectWLAN(appDelegate, configDictionary);
}

bool appendFramebufferInfoDSL(AppDelegate *appDelegate, uint32_t tab, NSMutableDictionary *configDictionary, NSString *name, NSMutableString **outputString)
{
	NSMutableDictionary *pciDeviceDictionary;

	if (![appDelegate tryGetPCIDeviceDictionaryFromIORegName:name pciDeviceDictionary:&pciDeviceDictionary])
		return false;
	
	NSString *ioregName = [pciDeviceDictionary objectForKey:@"IORegName"];
	NSString *devicePath = [pciDeviceDictionary objectForKey:@"DevicePath"];
	uint32_t address = [[pciDeviceDictionary objectForKey:@"Address"] unsignedIntValue];
	NSString *acpiPath;
	
	if (![appDelegate tryGetACPIPath:ioregName acpiPath:&acpiPath])
		return false;
	
	[appDelegate appendDSLString:tab + 0 outputString:*outputString value:[NSString stringWithFormat:@"External (_SB_.%@, DeviceObj)", acpiPath]];
	[appDelegate appendDSLString:tab + 0 outputString:*outputString value:[NSString stringWithFormat:@"Device (_SB.%@)", acpiPath]];
	[appDelegate appendDSLString:tab + 0 outputString:*outputString value:@"{"];
	[appDelegate appendDSLString:tab + 1 outputString:*outputString value:[NSString stringWithFormat:@"Name (_ADR, 0x%08x)", address]];
	[appDelegate appendDSLString:tab + 1 outputString:*outputString value:@"Method (_DSM, 4, NotSerialized)"];
	[appDelegate appendDSLString:tab + 1 outputString:*outputString value:@"{"];
	[appDelegate appendDSLString:tab + 2 outputString:*outputString value:@"If (LEqual (Arg2, Zero)) { Return (Buffer() { 0x03 } ) }"];
	[appDelegate appendDSLString:tab + 2 outputString:*outputString value:@"Return (Package ()"];
	[appDelegate appendDSLString:tab + 2 outputString:*outputString value:@"{"];
	
	NSMutableDictionary *devicesPropertiesDictionary = ([appDelegate isBootloaderOpenCore] ? [OpenCore getDevicePropertiesDictionaryWith:configDictionary typeName:@"Add"] : [Clover getDevicesPropertiesDictionaryWith:configDictionary]);
	NSMutableDictionary *deviceDictionary = [devicesPropertiesDictionary objectForKey:devicePath];
	
	for (NSString *deviceKey in deviceDictionary)
	{
		id deviceValue = deviceDictionary[deviceKey];
		
		if ([deviceValue isKindOfClass:[NSData class]])
			[appDelegate appendDSLValue:tab + 3 outputString:*outputString name:deviceKey value:deviceValue];
		else if ([deviceValue isKindOfClass:[NSString class]])
			[appDelegate appendDSLValue:tab + 3 outputString:*outputString name:deviceKey value:deviceValue];
	}
	
	[appDelegate appendDSLString:tab + 2 outputString:*outputString value:@"})"];
	[appDelegate appendDSLString:tab + 1 outputString:*outputString value:@"}"];
	[appDelegate appendDSLString:tab + 0 outputString:*outputString value:@"}"];
	
	return true;
}

void appendFramebufferInfoDSL(AppDelegate *appDelegate)
{
	// "AAPL,ig-platform-id", Buffer() { 0x00, 0x00, 0x16, 0x59 },
	// "model", Buffer() { "Intel UHD Graphics 620" },
	// "hda-gfx", Buffer() { "onboard-1" },
	// "device-id", Buffer() { 0x16, 0x59, 0x00, 0x00 },
	// "framebuffer-patch-enable", Buffer() { 0x01, 0x00, 0x00, 0x00 },
	// "framebuffer-unifiedmem", Buffer() {0x00, 0x00, 0x00, 0x80},
	
	Settings settings = [appDelegate settings];
	
	NSMutableDictionary *configDictionary = [NSMutableDictionary dictionary];
	NSMutableString *outputString = [NSMutableString string];
	
	getConfigDictionary(appDelegate, configDictionary, false);
	
	if (settings.PatchPCIDevices)
	{
		[appDelegate appendDSLString:0 outputString:outputString value:@"DefinitionBlock (\"\", \"SSDT\", 2, \"Hackintool\", \"PCI Devices\", 0x00000000)"];
		[appDelegate appendDSLString:0 outputString:outputString value:@"{"];
		
		for (int i = 0; i < [appDelegate.pciDevicesArray count]; i++)
		{
			NSMutableDictionary *pciDeviceDictionary = appDelegate.pciDevicesArray[i];
			NSString *ioregName = [pciDeviceDictionary objectForKey:@"IORegName"];
			
			appendFramebufferInfoDSL(appDelegate, 1, configDictionary, ioregName, &outputString);
		}
		
		[appDelegate appendDSLString:0 outputString:outputString value:@"}"];
	}
	else
	{
		if (settings.PatchGraphicDevice)
			appendFramebufferInfoDSL(appDelegate, 0, configDictionary, @"IGPU", &outputString);
		
		if (settings.PatchAudioDevice)
		{
			NSArray *audioArray = @[@"HDEF", @"ALZA", @"AZAL", @"HDAS", @"CAVS"];
			
			for (NSString *name in audioArray)
				appendFramebufferInfoDSL(appDelegate, 0, configDictionary, name, &outputString);
		}
	}
	
	[appDelegate appendTextView:appDelegate.patchOutputTextView text:outputString];
}

void getPCIProperties(AppDelegate *appDelegate, NSMutableDictionary *configDictionary)
{
	[appDelegate getPCIConfigDictionary:configDictionary];
}

bool getAudioProperties(AppDelegate *appDelegate, NSString *name, NSMutableDictionary *configDictionary)
{
	Settings settings = [appDelegate settings];
	
	NSMutableDictionary *devicesPropertiesDictionary = ([appDelegate isBootloaderOpenCore] ? [OpenCore getDevicePropertiesDictionaryWith:configDictionary typeName:@"Add"] : [Clover getDevicesPropertiesDictionaryWith:configDictionary]);
	NSMutableDictionary *pciDeviceDictionary;
	
	if (![appDelegate tryGetPCIDeviceDictionaryFromIORegName:name pciDeviceDictionary:&pciDeviceDictionary])
		return false;
	
	NSNumber *vendorID = [pciDeviceDictionary objectForKey:@"VendorID"];
	NSNumber *deviceID = [pciDeviceDictionary objectForKey:@"DeviceID"];
	NSString *deviceName = [pciDeviceDictionary objectForKey:@"DeviceName"];
	NSString *className = [pciDeviceDictionary objectForKey:@"ClassName"];
	NSString *subClassName = [pciDeviceDictionary objectForKey:@"SubClassName"];
	NSString *devicePath = [pciDeviceDictionary objectForKey:@"DevicePath"];
	NSString *slotName = [pciDeviceDictionary objectForKey:@"SlotName"];
	
	NSMutableDictionary *audioDictionary = [NSMutableDictionary dictionary];
	
	[devicesPropertiesDictionary setObject:audioDictionary forKey:devicePath];
	
	[audioDictionary setObject:deviceName forKey:@"model"];
	[audioDictionary setObject:([subClassName isEqualToString:@"???"] ? className : subClassName) forKey:@"device_type"];
	[audioDictionary setObject:slotName forKey:@"AAPL,slot-name"];
	
	if (settings.SpoofAudioDeviceID)
	{
		uint32_t currentDeviceID = ([vendorID unsignedIntValue] << 16) | [deviceID unsignedIntValue];
		uint32_t newDeviceID = 0;
		
		if ([appDelegate spoofAudioDeviceID:currentDeviceID newDeviceID:&newDeviceID])
			[audioDictionary setObject:getNSDataUInt32(newDeviceID) forKey:@"device-id"];
	}
	
	AudioDevice *audioDevice = nil;
	
	if ([appDelegate tryGetAudioController:deviceID vendorID:vendorID audioDevice:audioDevice])
		[audioDictionary setObject:getNSDataUInt32(appDelegate.alcLayoutID) forKey:@"layout-id"];
	
	return true;
}

void injectUseIntelHDMI(AppDelegate *appDelegate, NSMutableDictionary *configDictionary)
{
	// UseIntelHDMI
	// If TRUE, hda-gfx=onboard-1 will be injected into the GFX0 and HDEF devices. Also, if an ATI or Nvidia HDMI device is present, they'll be assigned to onboard-2.
	// If FALSE, then ATI or Nvidia devices will get onboard-1 as well as the HDAU device if present.
	
	Settings settings = [appDelegate settings];
	
	NSMutableDictionary *devicesPropertiesDictionary = ([appDelegate isBootloaderOpenCore] ? [OpenCore getDevicePropertiesDictionaryWith:configDictionary typeName:@"Add"] : [Clover getDevicesPropertiesDictionaryWith:configDictionary]);
	NSMutableDictionary *igpuDeviceDictionary;
	
	if (![appDelegate tryGetGPUDeviceDictionary:&igpuDeviceDictionary])
		return;
	
	NSString *devicePath = [igpuDeviceDictionary objectForKey:@"DevicePath"];
	NSMutableDictionary *deviceDictionary = [devicesPropertiesDictionary objectForKey:devicePath];
	
	if (settings.UseIntelHDMI)
		[deviceDictionary setObject:@"onboard-1" forKey:@"hda-gfx"];
	else if ([appDelegate hasGFX0])
		[deviceDictionary setObject:@"onboard-2" forKey:@"hda-gfx"];
	
	NSMutableDictionary *hdefDeviceDictionary;
	
	if ([appDelegate tryGetPCIDeviceDictionaryFromIORegName:@"HDEF" pciDeviceDictionary:&hdefDeviceDictionary])
	{
		NSString *devicePath = [hdefDeviceDictionary objectForKey:@"DevicePath"];
		NSMutableDictionary *deviceDictionary = [devicesPropertiesDictionary objectForKey:devicePath];
		
		if (settings.UseIntelHDMI)
			[deviceDictionary setObject:@"onboard-1" forKey:@"hda-gfx"];
		else if ([appDelegate hasGFX0])
			[deviceDictionary setObject:@"onboard-2" forKey:@"hda-gfx"];
	}
	
	NSMutableDictionary *gfx0DeviceDictionary;
	
	if ([appDelegate tryGetPCIDeviceDictionaryFromIORegName:@"GFX0" pciDeviceDictionary:&gfx0DeviceDictionary])
	{
		NSString *devicePath = [gfx0DeviceDictionary objectForKey:@"DevicePath"];
		NSMutableDictionary *deviceDictionary = [devicesPropertiesDictionary objectForKey:devicePath];
		
		if (settings.UseIntelHDMI)
			[deviceDictionary setObject:@"onboard-2" forKey:@"hda-gfx"];
		else
			[deviceDictionary setObject:@"onboard-1" forKey:@"hda-gfx"];
	}
	
	NSMutableDictionary *hdauDeviceDictionary;
	
	if ([appDelegate tryGetPCIDeviceDictionaryFromIORegName:@"HDAU" pciDeviceDictionary:&hdauDeviceDictionary])
	{
		NSString *devicePath = [hdefDeviceDictionary objectForKey:@"DevicePath"];
		NSMutableDictionary *deviceDictionary = [devicesPropertiesDictionary objectForKey:devicePath];
		
		if (settings.UseIntelHDMI)
			[deviceDictionary setObject:@"onboard-2" forKey:@"hda-gfx"];
		else
			[deviceDictionary setObject:@"onboard-1" forKey:@"hda-gfx"];
	}
}

bool injectWLAN(AppDelegate *appDelegate, NSMutableDictionary *configDictionary)
{
	// https://blog.daliansky.net/DW1820A_BCM94350ZAE-driver-inserts-the-correct-posture.html
	
	NSMutableDictionary *devicesPropertiesDictionary = ([appDelegate isBootloaderOpenCore] ? [OpenCore getDevicePropertiesDictionaryWith:configDictionary typeName:@"Add"] : [Clover getDevicesPropertiesDictionaryWith:configDictionary]);
	NSMutableDictionary *pciDeviceDictionary;
	
	if (![appDelegate tryGetPCIDeviceDictionaryFromClassCode:@(0x28000) pciDeviceDictionary:&pciDeviceDictionary])
		return false;
	
	NSNumber *vendorID = [pciDeviceDictionary objectForKey:@"VendorID"];
	NSNumber *deviceID = [pciDeviceDictionary objectForKey:@"DeviceID"];
	NSNumber *subVendorID = [pciDeviceDictionary objectForKey:@"SubVendorID"];
	NSNumber *subDeviceID = [pciDeviceDictionary objectForKey:@"SubDeviceID"];
	NSString *deviceName = [pciDeviceDictionary objectForKey:@"DeviceName"];
	NSString *devicePath = [pciDeviceDictionary objectForKey:@"DevicePath"];
	
	// Vendor: 0x14E4
	// Device: 0x43A3
	//	 Sub Vendor: 1028 or 106B
	//	 Sub Device: 0021 0022 0023 075a
	
	if (vendorID.unsignedIntValue != 0x14E4 ||
		deviceID.unsignedIntValue != 0x43A3)
		return false;
	
	if (subVendorID.unsignedIntValue != 0x1028 &&
		subVendorID.unsignedIntValue != 0x106B)
		return false;
	
	if (subDeviceID.unsignedIntValue != 0x0021 &&
		subDeviceID.unsignedIntValue != 0x0022 &&
		subDeviceID.unsignedIntValue != 0x0023 &&
		subDeviceID.unsignedIntValue != 0x075a)
		return false;
	
	NSMutableDictionary *wlanDictionary = [NSMutableDictionary dictionary];
	
	[devicesPropertiesDictionary setObject:wlanDictionary forKey:devicePath];
	
	// <key>AAPL,slot-name</key>
	// <string>WLAN</string>
	// <key>compatible</key>
	// <string>pci14e4,4331</string>
	// <key>device_type</key>
	// <string>Airport Extreme</string>
	// <key>model</key>
	// <string>DW1820A (BCM4350) 802.11ac Wireless</string>
	// <key>name</key>
	// <string>Airport</string>
	// <key>pci-aspm-default</key>
	// <integer>0</integer>
	
	[wlanDictionary setObject:@"WLAN" forKey:@"AAPL,slot-name"];
	[wlanDictionary setObject:@"pci14e4,4331" forKey:@"compatible"];
	[wlanDictionary setObject:@"Airport Extreme" forKey:@"device_type"];
	[wlanDictionary setObject:deviceName forKey:@"model"];
	[wlanDictionary setObject:@"Airport" forKey:@"name"];
	[wlanDictionary setObject:@(0) forKey:@"pci-aspm-default"];

	return true;
}
