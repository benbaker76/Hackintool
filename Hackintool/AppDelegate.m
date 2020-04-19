//
//  AppDelegate.m
//  Hackintool
//
//  Created by Ben Baker on 6/19/18.
//  Copyright (c) 2018 Ben Baker. All rights reserved.
//

#import "AppDelegate.h"
#import "Localizer.h"
#import "Authorization.h"
#import "IntelFramebuffer.h"
#import "IORegTools.h"
#import "FBUtilities.h"
#import "USB.h"
#import "DiskUtilities.h"
#import "Disk.h"
#import "FixEDID.h"
#import "AudioDevice.h"
#import "AudioNode.h"
#import "Resolution.h"
#import "Config.h"
#import "Clover.h"
#import "OpenCore.h"
#import "NVRAMXmlParser.h"
#import "BarTableRowView.h"
#import "NSPinCellView.h"
#import "NSString+Pin.h"
#import "VDADecoderChecker.h"
#import <IOKit/graphics/IOGraphicsLib.h>
#import <IOKit/kext/KextManager.h>
extern "C" {
#include "efidevp.h"
#include "macserial.h"
#include "modelinfo.h"
}
#include <sys/sysctl.h>
#include <cstddef>

#define MyPrivateTableViewDataType	@"MyPrivateTableViewDataType"
#define BluetoothPath1				@"com.apple.Bluetoothd.plist"
#define BluetoothPath2				@"blued.plist"
#define PCIIDsUrl					@"https://pci-ids.ucw.cz/pci.ids"
#define PCIIDsPath					[[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent:@"pci.ids"]
#define GitSubmoduleUpdate          @"/usr/bin/git submodule update --init --recursive"
#define COLOR_ALPHA					0.3f

uint32_t const FIND_AND_REPLACE_COUNT = 20;

//#define USE_ALTERNATING_BACKGROUND_COLOR
#define SWAPSHORT(n)	((n & 0x0000FFFF) << 16 | (n & 0xFFFF0000) >> 16)

@implementation NSData (NSDataEx)

-(NSComparisonResult)compare:(NSData *)otherData
{
	uint32_t valueA, valueB;
	
	memcpy(&valueA, self.bytes, MIN(self.length, 4));
	memcpy(&valueB, otherData.bytes, MIN(otherData.length, 4));
	
	if (valueA < valueB)
		return NSOrderedAscending;
	else if (valueA > valueB)
		return NSOrderedDescending;

	return NSOrderedSame;
}

@end

@implementation IntConvert

-(id) init:(uint32_t )index name:(NSString *)name stringValue:(NSString *)stringValue
{
	if (self = [super init])
	{
		Index = index;
		Name = name;
		StringValue = stringValue;
	}
	
	return self;
}

@end

#define GetLocalizedString(key) \
[[NSBundle mainBundle] localizedStringForKey:(key) value:@"" table:nil]

void authorizationGrantedCallback(AuthorizationRef authorization, OSErr status, void *context)
{
	AppDelegate *appDelegate = (AppDelegate *)context;
	
	[appDelegate updateAuthorization];
}

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	NSMutableDictionary *chosenDictionary;
	
	if (getIORegProperties(@"IODeviceTree:/chosen", &chosenDictionary))
	{
		NSData *bootDevicePathData = [chosenDictionary objectForKey:@"boot-device-path"];
		
		if (bootDevicePathData != nil)
		{
			const unsigned char *bootDeviceBytes = (const unsigned char *)bootDevicePathData.bytes;
			CHAR8 *devicePath = ConvertHDDDevicePathToText((const EFI_DEVICE_PATH *)bootDeviceBytes);
			NSString *devicePathString = [NSString stringWithUTF8String:devicePath];
			[self setEfiBootDeviceUUID:devicePathString];
		}
	}
	
	_gatekeeperDisabled = NO;
	
	NSBundle *mainBundle = [NSBundle mainBundle];
	NSDictionary *infoDictionary = [mainBundle infoDictionary];
	NSString *version = [infoDictionary objectForKey:@"CFBundleShortVersionString"];
	[_window setTitle:[NSString stringWithFormat:@"Hackintool v%@", version]];
	
	NSLog(@"Hackintool v%@", version);
	
	_tableViewArray = [@[_infoOutlineView, _generateSerialInfoTableView, _modelInfoTableView, _selectedFBInfoTableView, _currentFBInfoTableView, _vramInfoTableView, _framebufferInfoTableView, _framebufferFlagsTableView, _connectorInfoTableView, _connectorFlagsTableView, _audioDevicesTableView1, _audioInfoTableView, _usbControllersTableView, _usbPortsTableView, _efiPartitionsTableView, _partitionSchemeTableView, _displaysTableView, _resolutionsTableView, _bootloaderInfoTableView, _bootloaderPatchTableView, _nvramTableView, _kextsTableView, _pciDevicesTableView, _networkInterfacesTableView, _bluetoothDevicesTableView, _graphicDevicesTableView, _audioDevicesTableView2, _storageDevicesTableView, _powerSettingsTableView] retain];
	
	for (NSTableView *tableView in _tableViewArray)
	{
		for (NSTableColumn *tableColumn in tableView.tableColumns)
		{
			NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:tableColumn.identifier ascending:YES selector:@selector(compare:)];
			[tableColumn setSortDescriptorPrototype:sortDescriptor];
		}

#ifdef USE_ALTERNATING_BACKGROUND_COLOR
		[tableView setUsesAlternatingRowBackgroundColors:YES];
#endif
		
		[tableView sizeToFit];
	}
	
	[Localizer localizeView:_window];
	[Localizer localizeView:_window.menu];
	[Localizer localizeView:_toolbar];
	[Localizer localizeView:_infoWindow];
	[Localizer localizeView:_importKextsToPatchWindow];
	[Localizer localizeView:_hasUpdateWindow];
	[Localizer localizeView:_noUpdatesWindow];
	[Localizer localizeView:_progressWindow];
	
	for (NSToolbarItem *item in [_toolbar items])
		[item setMinSize:NSMakeSize(128, 128)];
	
	[_connectorInfoTableView registerForDraggedTypes:[NSArray arrayWithObject:MyPrivateTableViewDataType]];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateScreens:) name:NSApplicationDidChangeScreenParametersNotification object:NSApp];
	
	//[self resetDefaults];
	[self setDefaults];
	[self loadSettings];
	
	initAuthorization(authorizationGrantedCallback, self);
	
	[self initBundleData];
	[self getBootLog];
	[self initPCI];
	[self initDisplays];
	[self initGeneral];
	[self initNVRAM];
	[self initSettings];
	[self initMenus];
	[self initBootloader];
	[self initAudio];
	[self initUSB];
	[self initDisks];
	[self initInfo];
	[self initTools];
	[self initLogs];
	[self initInstalled];
	[self initSystemConfigs];
	
	for (NSToolbarItem *toolbarItem in [_toolbar items])
		if ([_tabView indexOfTabViewItem:[_tabView selectedTabViewItem]] == [toolbarItem.itemIdentifier intValue])
			[_toolbar setSelectedItemIdentifier:toolbarItem.itemIdentifier];
	
	_greenColor = [getColorAlpha([NSColor systemGreenColor], COLOR_ALPHA) retain];
	_redColor = [getColorAlpha([NSColor systemRedColor], COLOR_ALPHA) retain];
	_orangeColor = [getColorAlpha([NSColor systemOrangeColor], COLOR_ALPHA) retain];
	
	NSLog(@"Initialization Done");
}

- (void)dealloc
{
	freeAuthorization();
	
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	
	[self clearDisplays];
	
	usbUnRegisterEvents();
	[self clearAll];
	
	[_tableViewArray release];
	[_bootLog release];
	[_modelIdentifier release];
	[_intelGenString release];
	[_systemInfoArray release];
	[_serialInfoArray release];
	[_iMessageKeysArray release];
	[_gpuInfoDictionary release];
	[_infoArray release];
	[_modelInfoArray release];
	[_selectedFBInfoArray release];
	[_currentFBInfoArray release];
	[_vramInfoArray release];
	[_framebufferInfoArray release];
	[_framebufferFlagsArray release];
	[_connectorFlagsArray release];
	[_displayInfoArray release];
	[_bootloaderPatchArray release];
	[_systemConfigsArray release];
	[_gpuModel release];
	[_systemsArray release];
	[_intelDeviceIDsDictionary release];
	[_fbDriversDictionary release];
	[_intelGPUsDictionary release];
	[_intelModelsDictionary release];
	[_intelSpoofAudioDictionary release];
	[_audioCodecsArray release];
	[_audioVendorsDictionary release];
	[_usbControllersArray release];
	[_usbConfigurationDictionary release];
	[_audioInfoArray release];
	[_usbPortsArray release];
	[_displaysArray release];
	[_kextsArray release];
	[_installedKextsArray release];
	[_installedKextVersionDictionary release];
	[_fileName release];
	[_intelPlatformIDsDictionary_10_13_6 release];
	[_intelPlatformIDsDictionary_10_14 release];
	[_disksArray release];
	[_efiBootDeviceUUID	release];
	[_nvramDictionary release];
	[_pciVendorsDictionary release];
	[_pciClassesDictionary release];
	[_pciDevicesArray release];
	[_systemWidePowerSettings release];
	[_currentPowerSettings release];
	[_networkInterfacesArray release];
	[_bluetoothDevicesArray release];
	[_graphicDevicesArray release];
	[_audioDevicesArray release];
	[_nodeArray release];
	[_storageDevicesArray release];
	[_connection release];
	[_download release];
	[_pciMonitor release];
	[_bootloaderDeviceUUID release];
	[_bootloaderDirPath release];
	[_greenColor release];
	[_redColor release];
	[_orangeColor release];
	
	[super dealloc];
}

- (void)initGeneral
{
	// https://github.com/cylonbrain/VDADecoderCheck
	// /System/Library/Extensions/AppleGraphicsControl.kext/Contents/MacOS/AGDCDiagnose -a
	
	NSLog(@"Initializing General");
	
	[self createPlatformIDArray];

	NSProcessInfo *pInfo = [NSProcessInfo processInfo];
	NSString *version = [pInfo operatingSystemVersionString];
	
	NSLog(@"macOS Version: %@", version);
	
	if (getIORegString(@"IOPlatformExpertDevice", @"model", &_modelIdentifier))
		NSLog(@"Model Identifier: %@", _modelIdentifier);
	else
		NSLog(@"Failed Getting Model Identifier");
		
	if (getIntelGenString(_fbDriversDictionary, &_intelGenString))
		NSLog(@"IntelGen: %@", _intelGenString);
	else
		NSLog(@"Failed Getting IntelGen");
		
	if (getPlatformID(&_platformID))
		NSLog(@"PlatformID: 0x%08X", _platformID);
	else
		NSLog(@"Failed Getting PlatformID");
	
	if (getIGPUModelAndVRAM(&_gpuModel, _gpuDeviceID, _gpuVendorID, _vramSize, _vramFree))
		NSLog(@"IGPU: %@ (0x%08X)", _gpuModel, (_gpuDeviceID << 16) | _gpuVendorID);
	else
		NSLog(@"Failed Getting IGPU and VRAM Info");
	
	_infoArray = [[NSMutableArray array] retain];
	_systemInfoArray = [[NSMutableArray array] retain];
	_serialInfoArray = [[NSMutableArray array] retain];
	_iMessageKeysArray = [[NSMutableArray array] retain];
	_gpuInfoDictionary = [[NSMutableDictionary dictionary] retain];
	_selectedFBInfoArray = [[NSMutableArray array] retain];
	_currentFBInfoArray = [[NSMutableArray array] retain];
	_vramInfoArray = [[NSMutableArray array] retain];
	_framebufferInfoArray = [[NSMutableArray array] retain];
	_framebufferFlagsArray = [[NSMutableArray array] retain];
	_connectorFlagsArray = [[NSMutableArray array] retain];
	_displayInfoArray = [[NSMutableArray array] retain];
	
	NSArray *bootloaderArray = @[@"Auto Detect", @"Clover", @"OpenCore"];
	[_bootloaderComboBox addItemsWithObjectValues:translateArray(bootloaderArray)];

	[_selectedFBInfoArray removeAllObjects];
	[_currentFBInfoArray removeAllObjects];
	
	[self initModelInfo];
	[self selectModelInfo];
	[self updateSystemInfo];
	[self initGenerateSerialInfo];
	[self updateGenerateSerialInfo];
	[self updateModelInfo];
	
	[_selectedFBInfoTableView reloadData];
	[_currentFBInfoTableView reloadData];
	
	[self initScrollableTextView:_patchOutputTextView];
}

- (void)getSerialInfo:(NSString *)serialNumber serialInfoArray:(NSMutableArray *)serialInfoArray
{
	SERIALINFO info =
	{
		.modelIndex  = -1,
		.decodedYear = -1,
		.decodedWeek = -1,
		.decodedCopy = -1,
		.decodedLine = -1
	};
	
	get_serial_info([serialNumber UTF8String], &info, false);
	
	if (info.legacyCountryIdx >= 0)
		[self addToList:serialInfoArray name:@"Country" value:[NSString stringWithUTF8String:AppleLegacyLocationNames[info.legacyCountryIdx]]];
	else if (info.modernCountryIdx >= 0)
		[self addToList:serialInfoArray name:@"Country" value:[NSString stringWithUTF8String:AppleLocationNames[info.modernCountryIdx]]];
	
	[self addToList:serialInfoArray name:@"Year" value:[NSString stringWithFormat:@"%d", info.decodedYear]];
	
	char buffer[512] {};
	
	if (info.decodedYear > 0 && info.decodedWeek > 0)
	{
		struct tm startd =
		{
			.tm_isdst = -1,
			.tm_year = info.decodedYear - 1900,
			.tm_mday = 1 + 7 * (info.decodedWeek-1),
			.tm_mon = 0
		};
		if (mktime(&startd) >= 0)
		{
			sprintf(buffer, "%02d.%02d.%04d", startd.tm_mon+1, startd.tm_mday, startd.tm_year+1900);
			if (info.decodedWeek == 53 && startd.tm_mday != 31)
				strfcat(buffer, "12.31.%04d", startd.tm_year+1900);
			else if (info.decodedWeek < 53)
			{
				startd.tm_mday += 6;
				
				if (mktime(&startd))
					strfcat(buffer, "-%02d.%02d.%04d", startd.tm_mon+1, startd.tm_mday, startd.tm_year+1900);
			}
		}
		
		[self addToList:serialInfoArray name:@"Week" value:[NSString stringWithUTF8String:buffer]];
	}
	
	[self addToList:serialInfoArray name:@"Line" value:[NSString stringWithFormat:@"%d (copy %d)", info.decodedLine, (info.decodedCopy >= 0 ? info.decodedCopy + 1 : -1)]];
	[self addToList:serialInfoArray name:@"Model" value:(info.appleModel ? [NSString stringWithUTF8String:info.appleModel] : @"???")];
	[self addToList:serialInfoArray name:@"Model Identifier" value:(info.modelIndex >= 0 ? [NSString stringWithUTF8String:ApplePlatformData[info.modelIndex].productName] : @"???")];
	[self addToList:serialInfoArray name:@"Valid" value:(info.valid ? GetLocalizedString(@"Possibly") : GetLocalizedString(@"Unlikely"))];
}

- (void)updateSystemInfo
{
	[_infoArray removeAllObjects];
	[_systemInfoArray removeAllObjects];
	[_serialInfoArray removeAllObjects];
	[_iMessageKeysArray removeAllObjects];
	[_gpuInfoDictionary removeAllObjects];
	
	[self addToList:_systemInfoArray name:@"Host" value:getHostName()];
	[self addToList:_systemInfoArray name:@"OS" value:getOSName()];
	[self addToList:_systemInfoArray name:@"Kernel" value:getKernelName()];
	[self addToList:_systemInfoArray name:@"RAM" value:getMemSize()];
	[self addToList:_systemInfoArray name:@"Model Identifier" value:(_modelIdentifier != nil ? _modelIdentifier : @"???")];
	[self addToList:_systemInfoArray name:@"CPU" value:getCPUInfo()];
	[self addToList:_systemInfoArray name:@"Intel Generation" value:_intelGenString];
	[self addToList:_systemInfoArray name:@"Platform ID" value:[NSString stringWithFormat:@"0x%08X", _platformID]];
	
	NSMutableDictionary *platformDictionary;
	
	if (getIORegProperties(@"IODeviceTree:/", &platformDictionary))
	{
		_serialNumber = propertyToString([platformDictionary objectForKey:@"IOPlatformSerialNumber"]);
		
		[self addToList:_systemInfoArray name:@"Board ID" value:propertyToString([platformDictionary objectForKey:@"board-id"])];
		
		NSMutableDictionary *romDictionary;
		
		if (getIORegProperties(@"IODeviceTree:/rom", &romDictionary))
			[self addToList:_systemInfoArray name:@"FW Version" value:propertyToString([romDictionary objectForKey:@"version"])];
		
		[self addToList:_systemInfoArray name:@"Serial Number" value:_serialNumber];
		[self addToList:_systemInfoArray name:@"Hardware UUID" value:propertyToString([platformDictionary objectForKey:@"IOPlatformUUID"])];

		[self getSerialInfo:_serialNumber serialInfoArray:_serialInfoArray];
	}
	
	NSMutableDictionary *efiPlatformDictionary;
	
	if (getIORegProperties(@"IODeviceTree:/efi/platform", &efiPlatformDictionary))
	{
		NSMutableData *systemIDData = [efiPlatformDictionary objectForKey:@"system-id"];

		if (systemIDData != nil && systemIDData.length == 16)
		{
			NSMutableString *systemIDString = getByteString(systemIDData, @"", @"", false, true);
			
			[systemIDString insertString:@"-" atIndex:20];
			[systemIDString insertString:@"-" atIndex:16];
			[systemIDString insertString:@"-" atIndex:12];
			[systemIDString insertString:@"-" atIndex:8];
			
			[self addToList:_systemInfoArray name:@"System ID" value:systemIDString];
		}
		else
			[self addToList:_systemInfoArray name:@"System ID" value:@"???"];
	}
	else
		[self addToList:_systemInfoArray name:@"System ID" value:@"???"];
	
	CFTypeRef property = nil;
	
	if (getIORegProperty(@"IODeviceTree:/options", @"4D1EDE05-38C7-4A6A-9CC6-4BCCA8B38C14:ROM", &property))
	{
		NSData *valueData = (__bridge NSData *)property;
		NSMutableString *valueString = getByteString(valueData, @"", @"", false, true);
		
		[self addToList:_systemInfoArray name:@"ROM" value:valueString != nil ? valueString : @"???"];
		
		CFRelease(property);
	}
	else
		[self addToList:_systemInfoArray name:@"ROM" value:@"???"];
	
	if (getIORegProperty(@"IODeviceTree:/options", @"4D1EDE05-38C7-4A6A-9CC6-4BCCA8B38C14:MLB", &property))
	{
		NSData *valueData = (__bridge NSData *)property;
		NSString *valueString = [[[NSString alloc] initWithData:valueData encoding:NSASCIIStringEncoding] autorelease];
		
		[self addToList:_systemInfoArray name:@"Board Serial Number" value:valueString != nil ? valueString : @"???"];
		
		CFRelease(property);
	}
	else
		[self addToList:_systemInfoArray name:@"Board Serial Number" value:@"???"];
	
	// ----------------------------------------------
	
	OSStatus decoderStatus = CreateDecoder();
	
	switch (decoderStatus)
	{
		case kVDADecoderNoErr:
			[self addToList:_systemInfoArray name:@"VDA Decoder" value:GetLocalizedString(@"Fully Supported")];
			break;
		case kVDADecoderHardwareNotSupportedErr:
			[self addToList:_systemInfoArray name:@"VDA Decoder" value:GetLocalizedString(@"Not Supported")];
			break;
		case kVDADecoderConfigurationError:
			[self addToList:_systemInfoArray name:@"VDA Decoder" value:GetLocalizedString(@"Configuration Error")];
			break;
		case kVDADecoderDecoderFailedErr:
			[self addToList:_systemInfoArray name:@"VDA Decoder" value:GetLocalizedString(@"Decoder Failed")];
			break;
		default:
			[self addToList:_systemInfoArray name:@"VDA Decoder" value:[NSString stringWithFormat:GetLocalizedString(@"Unknown Status (%@)"), decoderStatus]];
			break;
	}
	
	[_infoArray addObject:@{@"Parent": GetLocalizedString(@"System Info"), @"Children": _systemInfoArray}];
	[_infoArray addObject:@{@"Parent": GetLocalizedString(@"Serial Info"), @"Children": _serialInfoArray}];
	
	// ----------------------------------------------
	
	for (int i = 0; i < [_pciDevicesArray count]; i++)
	{
		NSMutableDictionary *pciDeviceDictionary = _pciDevicesArray[i];
		NSString *deviceName = [pciDeviceDictionary objectForKey:@"DeviceName"];
		NSString *ioregName = [self getIORegName:[pciDeviceDictionary objectForKey:@"IORegName"]];
		NSString *ioregPath = [pciDeviceDictionary objectForKey:@"IORegPath"];
		NSString *ioregIOName = [pciDeviceDictionary objectForKey:@"IORegIOName"];
		NSNumber *vendorID = [pciDeviceDictionary objectForKey:@"VendorID"];
		NSNumber *deviceID = [pciDeviceDictionary objectForKey:@"DeviceID"];
		
		if (![ioregIOName isEqualToString:@"display"])
			continue;
		
		NSMutableArray *gpuInfoArray = [NSMutableArray array];

		[self addToList:gpuInfoArray name:@"GPU Name" value:deviceName];
		[self addToList:gpuInfoArray name:@"GPU Device ID" value:[NSString stringWithFormat:@"0x%08X", ([deviceID unsignedIntValue] << 16) | [vendorID unsignedIntValue]]];
	
		for (Display *display in _displaysArray)
		{
			if (![display.videoPath isEqualToString:ioregPath])
				continue;

			NSString *metalName = nil;
			bool isDefault = false, isLowPower = false, isHeadless = false;
			bool usesQuartzExtreme = CGDisplayUsesOpenGLAcceleration(display.directDisplayID);
			bool usesMetal = getMetalInfo(display.directDisplayID, &metalName, isDefault, isLowPower, isHeadless);
			
			if ([vendorID unsignedIntValue] == VEN_INTEL_ID && [ioregName isEqualToString:@"IGPU"])
			{
				[self addToList:gpuInfoArray name:@"Total VRAM" value:[NSString stringWithFormat:@"%llu MB", _vramSize]];
				[self addToList:gpuInfoArray name:@"Free VRAM" value:[NSString stringWithFormat:@"%llu MB", _vramFree / (1024 * 1024)]];
			}
			
			[self addToList:gpuInfoArray name:@"Quartz Extreme (QE/CI)" value:GetLocalizedString(usesQuartzExtreme ? @"Yes" : @"No")];
			[self addToList:gpuInfoArray name:@"Metal Supported" value:GetLocalizedString(usesMetal ? @"Yes" : @"No")];
			[self addToList:gpuInfoArray name:@"Metal Device Name" value:metalName];
			[self addToList:gpuInfoArray name:@"Metal Default Device" value:GetLocalizedString(isDefault ? @"Yes" : @"No")];
			[self addToList:gpuInfoArray name:@"Metal Low Power" value:GetLocalizedString(isLowPower ? @"Yes" : @"No")];
			[self addToList:gpuInfoArray name:@"Metal Headless" value:GetLocalizedString(isHeadless ? @"Yes" : @"No")];
			
			break;
		}
		
		[_infoArray addObject:@{@"Parent": ioregName, @"Children": gpuInfoArray}];
		
		[_gpuInfoDictionary setValue:gpuInfoArray forKey:ioregName];
	}
	
	// ----------------------------------------------
	
	if (getIORegProperty(@"IOPower:/", @"Gq3489ugfi", &property))
	{
		NSData *valueData = (__bridge NSData *)property;
		NSMutableString *valueString = getByteString(valueData, @"", @"", false, true);
		
		[self addToList:_iMessageKeysArray name:@"Gq3489ugfi" value:valueString != nil ? valueString : @"???"];
		
		CFRelease(property);
	}
	else
		[self addToList:_iMessageKeysArray name:@"Gq3489ugfi" value:@"???"];
	
	if (getIORegProperty(@"IOPower:/", @"Fyp98tpgj", &property))
	{
		NSData *valueData = (__bridge NSData *)property;
		NSMutableString *valueString = getByteString(valueData, @"", @"", false, true);
		
		[self addToList:_iMessageKeysArray name:@"Fyp98tpgj" value:valueString != nil ? valueString : @"???"];
		
		CFRelease(property);
	}
	else
		[self addToList:_iMessageKeysArray name:@"Fyp98tpgj" value:@"???"];
	
	if (getIORegProperty(@"IOPower:/", @"kbjfrfpoJU", &property))
	{
		NSData *valueData = (__bridge NSData *)property;
		NSMutableString *valueString = getByteString(valueData, @"", @"", false, true);
		
		[self addToList:_iMessageKeysArray name:@"kbjfrfpoJU" value:valueString != nil ? valueString : @"???"];
		
		CFRelease(property);
	}
	else
		[self addToList:_iMessageKeysArray name:@"kbjfrfpoJU" value:@"???"];
	
	if (getIORegProperty(@"IOPower:/", @"oycqAZloTNDm", &property))
	{
		NSData *valueData = (__bridge NSData *)property;
		NSMutableString *valueString = getByteString(valueData, @"", @"", false, true);
		
		[self addToList:_iMessageKeysArray name:@"oycqAZloTNDm" value:valueString != nil ? valueString : @"???"];
		
		CFRelease(property);
	}
	else
		[self addToList:_iMessageKeysArray name:@"oycqAZloTNDm" value:@"???"];
	
	if (getIORegProperty(@"IOPower:/", @"abKPld1EcMni", &property))
	{
		NSData *valueData = (__bridge NSData *)property;
		NSMutableString *valueString = getByteString(valueData, @"", @"", false, true);
		
		[self addToList:_iMessageKeysArray name:@"abKPld1EcMni" value:valueString != nil ? valueString : @"???"];
		
		CFRelease(property);
	}
	else
		[self addToList:_iMessageKeysArray name:@"abKPld1EcMni" value:@"???"];
	
	[_infoArray addObject:@{@"Parent": GetLocalizedString(@"iMessage Keys"), @"Children": _iMessageKeysArray}];
	
	// ----------------------------------------------
	
	[_infoOutlineView reloadData];
	[_infoOutlineView expandItem:nil expandChildren:YES];
}

- (void)initModelInfo
{
	_modelInfoArray = [[NSMutableArray array] retain];
	
	NSMutableArray *modelArray = [NSMutableArray array];
	
	for (NSDictionary *systemDictionary in _systemsArray)
	{
		NSString *model = [systemDictionary objectForKey:@"Model"];
		NSString *modelIdentifier = [systemDictionary objectForKey:@"Model Identifier"];
		NSString *modelEntry = [NSString stringWithFormat:@"%@ (%@)", model, modelIdentifier];
		
		if ([modelIdentifier isEqualToString:@"N/A"])
			continue;
		
		[modelArray addObject:modelEntry];
	}
	
	[_modelInfoComboBox addItemsWithObjectValues:modelArray];
}

- (void)selectModelInfo
{
	uint32_t systemCount = 0;
	uint32_t selectedIndex = 0;
	
	for (NSDictionary *systemDictionary in _systemsArray)
	{
		NSString *modelIdentifier = [systemDictionary objectForKey:@"Model Identifier"];
		
		if ([modelIdentifier isEqualToString:@"N/A"])
			continue;
		
		if (selectedIndex == 0 && [_modelIdentifier isEqualToString:modelIdentifier])
			selectedIndex = systemCount;

		systemCount++;
	}
	
	[_modelInfoComboBox selectItemAtIndex:selectedIndex];
}

- (uint32_t)getModelIndex:(NSString *)modelName
{
	for (int i = 0; i < _systemsArray.count; i++)
	{
		NSDictionary *systemDictionary = _systemsArray[i];
		NSString *model = [systemDictionary objectForKey:@"Model"];
		NSString *modelIdentifier = [systemDictionary objectForKey:@"Model Identifier"];
		NSString *modelEntry = [NSString stringWithFormat:@"%@ (%@)", model, modelIdentifier];
		
		if (![modelName isEqualToString:modelEntry])
			continue;
		
		return i;
	}
	
	return -1;
}

- (void)initGenerateSerialInfo
{
	_generateSerialInfoArray = [[NSMutableArray array] retain];
	
	for (int32_t i = 0; i < APPLE_MODEL_MAX; i++)
		[_generateSerialModelInfoComboBox addItemWithObjectValue:[NSString stringWithUTF8String:ApplePlatformData[i].productName]];
	
	[_generateSerialModelInfoComboBox selectItemWithObjectValue:_modelIdentifier];
}

- (void)updateGenerateSerialInfo
{
	[_generateSerialInfoArray removeAllObjects];
	
	SERIALINFO info =
	{
		.modelIndex  = -1,
		.decodedYear = -1,
		.decodedWeek = -1,
		.decodedCopy = -1,
		.decodedLine = -1
	};
	
	info.modelIndex = (uint32_t)[_generateSerialModelInfoComboBox indexOfSelectedItem];
	
	char mlb[MLB_MAX_SIZE];
	
	if (get_serial(&info))
	{
		get_mlb(&info, mlb, MLB_MAX_SIZE);
		
		_generateSerialNumber = [NSString stringWithFormat:@"%s%s%s%s%s", info.country, info.year, info.week, info.line, info.model];
		
		NSString *smUUID = getUUID();
		
		[self addToList:_generateSerialInfoArray name:@"Serial Number" value:_generateSerialNumber];
		[self addToList:_generateSerialInfoArray name:@"Board Serial Number" value:[NSString stringWithUTF8String:mlb]];
		[self addToList:_generateSerialInfoArray name:@"SmUUID" value:smUUID];
		
		[self getSerialInfo:_generateSerialNumber serialInfoArray:_generateSerialInfoArray];
	}

	[_generateSerialInfoTableView reloadData];
}

- (void)updateModelInfo
{
	[_modelInfoArray removeAllObjects];

	for (NSDictionary *systemDictionary in _systemsArray)
	{
		NSString *model = [systemDictionary objectForKey:@"Model"];
		NSString *modelIdentifier = [systemDictionary objectForKey:@"Model Identifier"];
		NSString *modelEntry = [NSString stringWithFormat:@"%@ (%@)", model, modelIdentifier];
		
		if ([_modelInfoComboBox.stringValue isEqualToString:modelEntry])
		{
			NSArray *sortedKeys = [systemDictionary.allKeys sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"self" ascending:YES]]];
			
			for (NSString *key in sortedKeys)
				[self addToList:_modelInfoArray name:key value:[systemDictionary objectForKey:key]];
			
			break;
		}
	}
	
	[_modelInfoTableView reloadData];
}

- (void)initBootloader
{
	NSLog(@"Initializing Bootloader");
	
	_bootloaderInfoArray = [[NSMutableArray array] retain];
	_bootloaderPatchArray = [[NSMutableArray array] retain];

	_cloverInfo.Name = @"Clover";
	_cloverInfo.LastVersionDownloaded = kCloverLastVersionDownloaded;
	_cloverInfo.LastDownloadWarned = kCloverLastDownloadWarned;
	_cloverInfo.LastCheckTimestamp = kCloverLastCheckTimestamp;
	_cloverInfo.ScheduledCheckInterval = kCloverScheduledCheckInterval;
	_cloverInfo.LatestReleaseURL = kCloverLatestReleaseURL;
	_cloverInfo.IconName = @"IconClover";
	_cloverInfo.FileNameMatch = @"Clover_";
	
	_openCoreInfo.Name = @"OpenCore";
	_openCoreInfo.LastVersionDownloaded = kOpenCoreLastVersionDownloaded;
	_openCoreInfo.LastDownloadWarned = kOpenCoreLastDownloadWarned;
	_openCoreInfo.LastCheckTimestamp = kOpenCoreLastCheckTimestamp;
	_openCoreInfo.ScheduledCheckInterval = kOpenCoreScheduledCheckInterval;
	_openCoreInfo.LatestReleaseURL = kOpenCoreLatestReleaseURL;
	_openCoreInfo.IconName = @"IconOpenCore";
	_openCoreInfo.FileNameMatch = @"OpenCore";
	
	NSBundle *mainBundle = [NSBundle mainBundle];
	NSString *filePath = nil;
	
	if ((filePath = [mainBundle pathForResource:@"config_patches" ofType:@"plist" inDirectory:@"Clover"]))
	{
		NSMutableDictionary *configDictionary = [NSMutableDictionary dictionaryWithContentsOfFile:filePath];
		NSMutableArray *kernelToPatchArray = [Clover getKernelAndKextPatchArrayWith:configDictionary kernelAndKextName:@"KernelToPatch"];
		NSMutableArray *kextToPatchArray = [Clover getKernelAndKextPatchArrayWith:configDictionary kernelAndKextName:@"KextsToPatch"];
		
		for (NSMutableDictionary *patchDictionary in kernelToPatchArray)
		{
			NSString *matchOS = [patchDictionary objectForKey:@"MatchOS"];

			if (![Config doesMatchOS:matchOS])
				continue;
			
			[patchDictionary setObject:@"KernelToPatch" forKey:@"Type"];
			[patchDictionary setObject:@(YES) forKey:@"Disabled"];
			
			[_bootloaderPatchArray addObject:patchDictionary];
		}
		
		for (NSMutableDictionary *patchDictionary in kextToPatchArray)
		{
			NSString *matchOS = [patchDictionary objectForKey:@"MatchOS"];
			
			if (![Config doesMatchOS:matchOS])
				continue;
			
			[patchDictionary setObject:@"KextsToPatch" forKey:@"Type"];
			[patchDictionary setObject:@(YES) forKey:@"Disabled"];
			
			[_bootloaderPatchArray addObject:patchDictionary];
		}
	}
	
	if ((filePath = [mainBundle pathForResource:@"config_patches" ofType:@"plist" inDirectory:@"USB"]))
	{
		NSMutableDictionary *configDictionary = [NSMutableDictionary dictionaryWithContentsOfFile:filePath];
		NSMutableArray *kextToPatchArray = [Clover getKernelAndKextPatchArrayWith:configDictionary kernelAndKextName:@"KextsToPatch"];
		
		for (NSMutableDictionary *patchDictionary in kextToPatchArray)
		{
			NSString *matchOS = [patchDictionary objectForKey:@"MatchOS"];
			
			if (![Config doesMatchOS:matchOS])
				continue;
			
			[patchDictionary setObject:@"KextsToPatch" forKey:@"Type"];
			[patchDictionary setObject:@(YES) forKey:@"Disabled"];
			
			[_bootloaderPatchArray addObject:patchDictionary];
		}
	}
	
	if ((filePath = [mainBundle pathForResource:@"config_renames" ofType:@"plist" inDirectory:@"Clover"]))
	{
		NSMutableDictionary *configDictionary = [NSMutableDictionary dictionaryWithContentsOfFile:filePath];
		NSMutableArray *dsdtRenameArray = [Clover getACPIDSDTPatchesArrayWith:configDictionary];
		
		for (NSMutableDictionary *patchDictionary in dsdtRenameArray)
		{
			NSData *findData = [patchDictionary objectForKey:@"Find"];
			NSData *replaceData = [patchDictionary objectForKey:@"Replace"];
			NSString *findString = [NSString stringWithUTF8String:(const char *)findData.bytes];
			NSString *replaceString = [NSString stringWithUTF8String:(const char *)replaceData.bytes];
			bool foundACPI = (findString != nil ? hasACPIEntry(findString) : false);
			
			if (foundACPI)
			{
				if ([findString isEqualToString:@"GFX0"] && [replaceString isEqualToString:@"IGPU"])
				{
					NSMutableDictionary *pciDeviceDictionary;
					
					if ([self tryGetPCIDeviceDictionaryFromIORegName:@"GFX0" pciDeviceDictionary:&pciDeviceDictionary])
					{
						NSString *ioregIOName = [pciDeviceDictionary objectForKey:@"IORegIOName"];
						NSNumber *vendorID = [pciDeviceDictionary objectForKey:@"VendorID"];
						
						if ([ioregIOName isEqualToString:@"display"])
						{
							switch([vendorID unsignedIntValue])
							{
								case VEN_INTEL_ID:
									break;
								case VEN_NVIDIA_ID:
								case VEN_AMD_ID:
									foundACPI = NO;
									break;
							}
						}
					}
				}
			}
			
			[patchDictionary setObject:@"DSDT Rename" forKey:@"Type"];
			//[patchDictionary setObject:@(!foundACPI) forKey:@"Disabled"];
			[patchDictionary setObject:@(YES) forKey:@"Disabled"];
			
			[_bootloaderPatchArray addObject:patchDictionary];
		}
	}
	
	[self setBootloaderInfo];
	
	[_bootloaderPatchTableView reloadData];
}

- (void)initNVRAM
{
	if (getIORegProperties(@"IODeviceTree:/options", &_nvramDictionary))
	{
		//NSLog(@"%@", _nvramDictionary);
	}
	
	[self initScrollableTextView:_nvramValueTextView];
	
	[_nvramTableView reloadData];
}

- (void)initBundleData
{
	NSLog(@"Initializing Bundle Data");
	
	NSBundle *mainBundle = [NSBundle mainBundle];
	NSString *filePath = nil;
	
	if ((filePath = [mainBundle pathForResource:@"Systems" ofType:@"plist" inDirectory:@"EveryMac"]))
		_systemsArray = [[NSArray arrayWithContentsOfFile:filePath] retain];
	
	if ((filePath = [mainBundle pathForResource:@"DeviceIDs" ofType:@"plist" inDirectory:@"Intel"]))
		_intelDeviceIDsDictionary = [[NSDictionary dictionaryWithContentsOfFile:filePath] retain];
	
	if ((filePath = [mainBundle pathForResource:@"FBDrivers" ofType:@"plist" inDirectory:@"Intel"]))
		_fbDriversDictionary = [[NSDictionary dictionaryWithContentsOfFile:filePath] retain];
	
	if ((filePath = [mainBundle pathForResource:@"GPUs" ofType:@"plist" inDirectory:@"Intel"]))
		_intelGPUsDictionary = [[NSDictionary dictionaryWithContentsOfFile:filePath] retain];
	
	if ((filePath = [mainBundle pathForResource:@"Models" ofType:@"plist" inDirectory:@"Intel"]))
		_intelModelsDictionary = [[NSDictionary dictionaryWithContentsOfFile:filePath] retain];
	
	if ((filePath = [mainBundle pathForResource:@"SpoofAudio" ofType:@"plist" inDirectory:@"Intel"]))
		_intelSpoofAudioDictionary = [[NSDictionary dictionaryWithContentsOfFile:filePath] retain];
	
	if ((filePath = [mainBundle pathForResource:@"AudioCodecs" ofType:@"plist" inDirectory:@"Intel"]))
		_audioCodecsArray = [[NSArray arrayWithContentsOfFile:filePath] retain];
	
	if ((filePath = [mainBundle pathForResource:@"Vendors" ofType:@"plist" inDirectory:@"Audio"]))
		_audioVendorsDictionary = [[NSDictionary dictionaryWithContentsOfFile:filePath] retain];
}

- (void)initSettings
{
	NSLog(@"Initializing Settings");
	
	[_dpcdMaxLinkRateComboBox addItemsWithObjectValues:@[@"RBR", @"HBR", @"HBR2", @"HBR3"]];
	
	[_fbPortLimitComboBox addItemsWithObjectValues:@[@"1", @"2", @"3"]];
	
	[_lspconConnectorComboBox addItemsWithObjectValues:@[@"0", @"1", @"2", @"3"]];
	[_lspconPreferredModeComboBox addItemsWithObjectValues:@[GetLocalizedString(@"LS (DP to HDMI 1.4)"), GetLocalizedString(@"PCON (DP to HDMI 2.0)")]];
	
	[self updateSettingsGUI];
	
	[_intelGenComboBox removeAllItems];
	
	for (int i = 0; i < IGCount; i++)
		[_intelGenComboBox addItemWithObjectValue:g_fbNameArray[i]];
	
	[_intelGenComboBox selectItemWithObjectValue:_settings.IntelGen];
}

- (void)updateSettingsGUI
{
	[_applyCurrentPatchesMenuItem setState:_settings.ApplyCurrentPatches];
	[_kextsToPatchHexPatchRadioButton setState:_settings.KextsToPatchHex];
	[_kextsToPatchBase64PatchRadioButton setState:_settings.KextsToPatchBase64];
	[_devicePropertiesPatchRadioButton setState:_settings.DeviceProperties];
	[_iASLDSLSourcePatchRadioButton setState:_settings.iASLDSLSource];
	[_bootloaderComboBox selectItemAtIndex:_settings.SelectedBootloader];
	[_autoDetectChangesButton setState:_settings.AutoDetectChanges];
	[_useAllDataMethodButton setState:_settings.UseAllDataMethod];
	[_allPatchButton setState:_settings.PatchAll];
	[_connectorsPatchButton setState:_settings.PatchConnectors];
	[_vramPatchButton setState:_settings.PatchVRAM];
	[_graphicDevicePatchButton setState:_settings.PatchGraphicDevice];
	[_audioDevicePatchButton setState:_settings.PatchAudioDevice];
	[_pciDevicesPatchButton setState:_settings.PatchPCIDevices];
	[_edidPatchButton setState:_settings.PatchEDID];
	[_dvmtPrealloc32MB setState:_settings.DVMTPrealloc32MB];
	[_vram2048MB setState:_settings.VRAM2048MB];
	[_disableeGPUButton setState:_settings.DisableeGPU];
	[_enableHDMI20Button setState:_settings.EnableHDMI20];
	[_dptoHDMIButton setState:_settings.DPtoHDMI];
	[_useIntelHDMIButton setState:_settings.UseIntelHDMI];
	[_gfxYTileFixButton setState:_settings.GfxYTileFix];
	[_hotplugRebootFixButton setState:_settings.HotplugRebootFix];
	[_hdmiInfiniteLoopFixButton setState:_settings.HDMIInfiniteLoopFix];
	[_dpcdMaxLinkRateButton setState:_settings.DPCDMaxLinkRateFix];
	[_dpcdMaxLinkRateComboBox selectItemAtIndex:_settings.DPCDMaxLinkRate];
	[_fbPortLimitButton setState:_settings.FBPortLimit];
	[_fbPortLimitComboBox selectItemAtIndex:(_settings.FBPortCount > 0 ? _settings.FBPortCount - 1 : 0)];
	[_injectDeviceIDButton setState:_settings.InjectDeviceID];
	[_spoofAudioDeviceIDButton setState:_settings.SpoofAudioDeviceID];
	[_injectFakeIGPUButton setState:_settings.InjectFakeIGPU];
	[_usbPortLimitButton setState:_settings.USBPortLimit];
	[_showInstalledOnlyButton setState:_settings.ShowInstalledOnly];
	[_lspconEnableDriverButton setState:_settings.LSPCON_Enable];
	[_lspconAutoDetectRadioButton setState:_settings.LSPCON_AutoDetect];
	[_lspconConnectorRadioButton setState:_settings.LSPCON_Connector];
	[_lspconConnectorComboBox selectItemAtIndex:_settings.LSPCON_ConnectorIndex];
	[_lspconPreferredModeButton setState:_settings.LSPCON_PreferredMode];
	[_lspconPreferredModeComboBox selectItemAtIndex:_settings.LSPCON_PreferredModeIndex];
}

- (bool)getAudioVendorName:(uint32_t)codecID vendorName:(NSString **)vendorName
{
	*vendorName = GetLocalizedString(@"Unknown");
	
	for (NSString *key in [_audioVendorsDictionary allKeys])
	{
		NSNumber *vid = [_audioVendorsDictionary objectForKey:key];
		
		if ([vid unsignedIntValue]  == (codecID >> 16))
		{
			*vendorName = key;
			
			return true;
		}
	}
	
	return false;
}

- (bool)getAudioCodecName:(uint32_t)deviceID revisionID:(uint16_t)revisionID name:(NSString **)name
{
	*name = @"???";
	
	if (deviceID == 0)
		return false;
	
	for (NSDictionary *codecDictionary in _audioCodecsArray)
	{
		NSNumber *findDeviceID = [codecDictionary objectForKey:@"DeviceID"];
		NSNumber *findRevisionID = [codecDictionary objectForKey:@"RevisionID"];
		NSString *findName = [codecDictionary objectForKey:@"Name"];
		
		if (deviceID == [findDeviceID unsignedIntValue] && revisionID == [findRevisionID unsignedIntValue])
		{
			*name = findName;
			
			return true;
		}
	}
	
	for (NSDictionary *codecDictionary in _audioCodecsArray)
	{
		NSNumber *findDeviceID = [codecDictionary objectForKey:@"DeviceID"];
		NSString *findName = [codecDictionary objectForKey:@"Name"];
		
		if (deviceID == [findDeviceID unsignedIntValue])
		{
			*name = findName;
			
			return true;
		}
	}
	
	return false;
}

- (void)initAudio
{
	// https://www.tonymacx86.com/threads/release-intel-fb-patcher-v1-6-4.254559/page-31#post-1849314
	// https://www.tonymacx86.com/threads/release-intel-fb-patcher-v1-6-4.254559/page-31#post-1849287
	//
	// UseIntelHDMI
	// <key>UseIntelHDMI</key>
	// <false/>
	// If TRUE, hda-gfx=onboard-1 will be injected into the GFX0 and HDEF devices. Also, if an ATI or Nvidia HDMI device is present, they'll be assigned to onboard-2. If FALSE, then ATI or Nvidia devices will get onboard-1 as well as the HDAU device if present.
	//
	// ------//----------------------------
	// Yes... and no-controller-patch=1 (to avoid default AppleALC patching for unsupported HDA controllers).
	// Added ability to disable controller patching by injecting property 'no-controller-patch' (for use of FakePCIID_Intel_HDMI_Audio)
	
	_audioInfoArray = [[NSMutableArray array] retain];
	_nodeArray = [[NSMutableArray array] retain];
	
	if (!getIORegAudioDeviceArray(&_audioDevicesArray))
		return;
	
	[self updateAudioCodecInfo];
		
	int selectedAudioDevice = -1;
	
	for (int i = 0; i < [_audioDevicesArray count]; i++)
	{
		AudioDevice *audioDevice = _audioDevicesArray[i];
		
		NSNumber *vendorID = [NSNumber numberWithInt:audioDevice.deviceID >> 16];
		NSNumber *deviceID = [NSNumber numberWithInt:audioDevice.deviceID & 0xFFFF];
		NSNumber *subVendorID = [NSNumber numberWithInt:audioDevice.subDeviceID >> 16];
		NSNumber *subDeviceID = [NSNumber numberWithInt:audioDevice.subDeviceID & 0xFFFF];
		//NSNumber *audioVendorID = [NSNumber numberWithInt:audioDevice.audioDeviceModelID >> 16];
		//NSNumber *audioDeviceID = [NSNumber numberWithInt:audioDevice.audioDeviceModelID & 0xFFFF];

		NSString *vendorName = nil, *deviceName = nil;
		NSString *subVendorName = nil, *subDeviceName = nil;
		NSString *codecVendorName = nil, *codecName = nil;
		//NSString *audioVendorName = nil, *audioDeviceName = nil;
		
		[self getPCIDeviceInfo:vendorID deviceID:deviceID vendorName:&vendorName deviceName:&deviceName];
		[self getPCIDeviceInfo:subVendorID deviceID:subDeviceID vendorName:&subVendorName deviceName:&subDeviceName];
		//[self getPCIDeviceInfo:audioVendorID deviceID:audioDeviceID vendorName:&audioVendorName deviceName:&audioDeviceName];
		
		audioDevice.deviceName = deviceName;
		audioDevice.vendorName = vendorName;
		audioDevice.subDeviceName = subDeviceName;
		audioDevice.subVendorName = subVendorName;
		//audioDevice.audioDeviceName = audioDeviceName;
		//audioDevice.audioVendorName = audioVendorName;
		
		if ([self getAudioVendorName:audioDevice.codecID vendorName:&codecVendorName])
			audioDevice.codecVendorName = codecVendorName;
		
		if ([self getAudioCodecName:audioDevice.codecID revisionID:audioDevice.codecRevisionID name:&codecName] || audioDevice.codecName == nil)
			audioDevice.codecName = codecName;
			
		if ([self isAppleHDAAudioDevice:audioDevice])
		{
			selectedAudioDevice = i;
			_alcLayoutID = audioDevice.alcLayoutID;
		}
	}
	
	[_audioDevicesTableView1 reloadData];
	
	NSIndexSet *indexSet = [NSIndexSet indexSetWithIndex:selectedAudioDevice];
	[_audioDevicesTableView1 selectRowIndexes:indexSet byExtendingSelection:NO];
	
	[self updateAudioInfo];
	[self updatePinConfiguration];
}

- (void)initMenus
{
	NSLog(@"Initializing Menus");
	
	NSData *nativePlatformTable = nil;
	
	if (getPlatformTableNative(&nativePlatformTable))
		[_importIORegNativeMenuItem setEnabled:YES];
	
	NSData *patchedPlatformTable = nil;
	
	if (getPlatformTablePatched(&patchedPlatformTable))
		[_importIORegPatchedMenuItem setEnabled:YES];
}

- (void)initUSB
{
	// https://www.tonymacx86.com/threads/xhc-usb-kext-creation-guideline.242999/
	// https://github.com/KGP/XHC-USB-Kext-Library
	
	NSLog(@"Initializing USB");
	
	NSBundle *mainBundle = [NSBundle mainBundle];
	NSString *filePath = nil;
	
	if (!(filePath = [mainBundle pathForResource:@"USBInjectAll-Info" ofType:@"plist" inDirectory:@"USB"]))
		return;
	
	NSDictionary *usbPlist = [NSDictionary dictionaryWithContentsOfFile:filePath];
	
	_usbConfigurationDictionary = [[[[usbPlist objectForKey:@"IOKitPersonalities"] objectForKey:@"ConfigurationData"] objectForKey:@"Configuration"] retain];
	
	[_usbPortsTableView setAllowsMultipleSelection:true];
	
	_usbControllersArray = [[NSMutableArray array] retain];
	_usbPortsArray = [[NSMutableArray array] retain];
	
	[self loadUSBPorts];
	[self refreshUSBPorts];
	[self refreshUSBControllers];
	
	for (NSMutableDictionary *usbControllersDictionary in _usbControllersArray)
	{
		NSString *usbControllerType = [usbControllersDictionary objectForKey:@"Type"];
		NSString *usbControllerName = [usbControllersDictionary objectForKey:@"Name"];
		NSString *usbControllerSeries = [usbControllersDictionary objectForKey:@"Series"];
		NSNumber *usbControllerID = [usbControllersDictionary objectForKey:@"DeviceID"];
		
		NSLog(@"Found USB Controller: %@ %@ (%@-series) Controller (0x%08X)", usbControllerType, usbControllerName, usbControllerSeries, [usbControllerID unsignedIntValue]);
	}
}

- (void)initDisks
{
	NSLog(@"Initializing Disks");
	
	// The NVRAM information cited by Mark Setchell is available from IOKit, too, at path IOService:/AppleACPIPlatformExpert/AppleEFIRuntime/AppleEFINVRAM.
	// There's a property efi-boot-device. Its value is a property list including a service matching dictionary. As you can see, it looks for an entry with
	// provider class of IOMedia whose UUID property is a certain UUID.
	
	//self.arrayOfDisks = [[NSMutableArray alloc]init];
	
	[self getEfiBootDevice];
	
	_disksArray = [[NSMutableArray array] retain];
	
	registerDiskCallbacks(self);
}

- (void)parsePCIIDs
{
	// https://pci-ids.ucw.cz/
	// 14e4  Broadcom Inc. and subsidiaries
	//	0576  BCM43224 802.11a/b/g/n
	//		1028 01c1  Precision 490
	
	_pciVendorsDictionary = [[NSMutableDictionary dictionary] retain];
	_pciClassesDictionary = [[NSMutableDictionary dictionary] retain];
	
	NSMutableDictionary *pciDeviceDictionary = nil;
	NSMutableDictionary *pciSubclassesDictionary = nil;
	NSMutableDictionary *pciSubsystemsDictionary = nil;
	NSMutableDictionary *pciProgrammingInterfacesDictionary = nil;
	NSBundle *mainBundle = [NSBundle mainBundle];
	NSString *filePath = nil;
	bool isReadingDevices = true;
	
	if (!(filePath = [mainBundle pathForResource:@"pci" ofType:@"ids" inDirectory:@"PCI"]))
		return;
	
	NSString *pciString = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:nil];
	NSArray *pciArray = [pciString componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
	
	for (NSString *pciLine in pciArray)
	{
		if ([pciLine isEqualToString:@"# List of known device classes, subclasses and programming interfaces"])
		{
			isReadingDevices = false;
			continue;
		}
		
		if ([pciLine isEqualToString:@""] || [pciLine hasPrefix:@"#"])
			continue;
		
		if (isReadingDevices)
		{
			if ([pciLine hasPrefix:@"\t\t"])
			{
				NSArray *subsystemArray = [pciLine componentsSeparatedByString:@"  "];
				NSArray *subsystemIDArray = [subsystemArray[0] componentsSeparatedByString:@" "];
				NSNumber *subsystemID = [NSNumber numberWithInt:(getHexInt(subsystemIDArray[0]) << 16) | getHexInt(subsystemIDArray[1])];
				NSString *subsystemName = subsystemArray[1];
				
				[pciSubsystemsDictionary setObject:subsystemName forKey:subsystemID];
			}
			else if ([pciLine hasPrefix:@"\t"])
			{
				NSArray *deviceArray = [pciLine componentsSeparatedByString:@"  "];
				NSNumber *deviceID = [NSNumber numberWithInt:getHexInt(deviceArray[0])];
				NSString *deviceName = deviceArray[1];
				
				[pciDeviceDictionary setObject:deviceName forKey:deviceID];
			}
			else
			{
				NSArray *vendorArray = [pciLine componentsSeparatedByString:@"  "];
				NSNumber *vendorID = [NSNumber numberWithInt:getHexInt(vendorArray[0])];
				NSString *vendorName = vendorArray[1];
				NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
				[dictionary setObject:vendorID forKey:@"VendorID"];
				[dictionary setObject:vendorName forKey:@"VendorName"];
				
				pciDeviceDictionary = [NSMutableDictionary dictionary];
				[dictionary setObject:pciDeviceDictionary forKey:@"Devices"];
				
				pciSubsystemsDictionary = [NSMutableDictionary dictionary];
				[dictionary setObject:pciSubsystemsDictionary forKey:@"Subsystems"];
				
				[_pciVendorsDictionary setObject:dictionary forKey:vendorID];
			}
		}
		else
		{
			if ([pciLine hasPrefix:@"\t\t"])
			{
				NSArray *progammingInterfaceArray = [pciLine componentsSeparatedByString:@"  "];
				NSNumber *progammingInterfaceID = [NSNumber numberWithInt:getHexInt(progammingInterfaceArray[0])];
				NSString *progammingInterfaceName = progammingInterfaceArray[1];
				
				[pciProgrammingInterfacesDictionary setObject:progammingInterfaceName forKey:progammingInterfaceID];
			}
			else if ([pciLine hasPrefix:@"\t"])
			{
				NSArray *subclassArray = [pciLine componentsSeparatedByString:@"  "];
				NSNumber *subclassID = [NSNumber numberWithInt:getHexInt(subclassArray[0])];
				NSString *subclassName = subclassArray[1];
				
				[pciSubclassesDictionary setObject:subclassName forKey:subclassID];
			}
			else if ([pciLine hasPrefix:@"C "])
			{
				pciLine = [pciLine substringFromIndex:1];
				NSArray *classArray = [pciLine componentsSeparatedByString:@"  "];
				NSNumber *classID = [NSNumber numberWithInt:getHexInt(classArray[0])];
				NSString *className = classArray[1];
				NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
				[dictionary setObject:classID forKey:@"ClassID"];
				[dictionary setObject:className forKey:@"ClassName"];
				
				pciSubclassesDictionary = [NSMutableDictionary dictionary];
				[dictionary setObject:pciSubclassesDictionary forKey:@"SubClasses"];
				
				pciProgrammingInterfacesDictionary = [NSMutableDictionary dictionary];
				[dictionary setObject:pciProgrammingInterfacesDictionary forKey:@"ProgrammingInterfaces"];
				
				[_pciClassesDictionary setObject:dictionary forKey:classID];
			}
		}
	}
	
	// NSLog(@"%@", _pciVendorsDictionary);
	// NSLog(@"%@", _pciClassesDictionary);
}

- (void)initPCI
{
	NSLog(@"Initializing PCI");
	
	_pciMonitor = [[PCIMonitor alloc] init];
	_pciMonitor.delegate = self;
	[_pciMonitor registerForPCINotifications];
	
	NSError *error;
	NSString *pciIDsCachePath = PCIIDsPath;
	NSString *pciIDsBundlePath = [NSBundle.mainBundle pathForResource:@"pci" ofType:@"ids" inDirectory:@"PCI"];
	NSFileManager *fileManager = [NSFileManager defaultManager];
	
	if (![fileManager fileExistsAtPath:pciIDsCachePath])
	{
		[fileManager copyItemAtPath:pciIDsBundlePath toPath:pciIDsCachePath error:&error];
		NSDate *fileModificationDate = [[fileManager attributesOfItemAtPath:pciIDsBundlePath error:&error] fileModificationDate];
		[fileManager setAttributes:@{ NSFileModificationDate:fileModificationDate } ofItemAtPath:pciIDsCachePath error:&error];
	}
	
	[self parsePCIIDs];
	[self updatePCIIDs];
}

- (void)pciDeviceName:(NSString*)deviceName added:(BOOL)added
{
	[self updatePCIIDs];
}

- (bool)getPCIDeviceInfo:(NSNumber *)vendorID deviceID:(NSNumber *)deviceID vendorName:(NSString **)vendorName deviceName:(NSString **)deviceName
{
	NSMutableDictionary *vendorDictionary = [_pciVendorsDictionary objectForKey:vendorID];
	
	if (vendorDictionary != nil)
	{
		*vendorName = [vendorDictionary objectForKey:@"VendorName"];
		NSMutableDictionary *deviceDictionary = [vendorDictionary objectForKey:@"Devices"];
		*deviceName = [deviceDictionary objectForKey:deviceID];
	}
	
	bool result = (*deviceName != nil);
	
	if (*vendorName == nil)
		*vendorName = @"???";
	
	if (*deviceName == nil)
		*deviceName = @"???";
	
	return result;
}

- (bool)getPCIDeviceInfo:(NSNumber *)vendorID deviceID:(NSNumber *)deviceID classCode:(NSNumber *)classCode vendorName:(NSString **)vendorName deviceName:(NSString **)deviceName className:(NSString **)className subclassName:(NSString **)subclassName
{
	bool result = [self getPCIDeviceInfo:vendorID deviceID:deviceID vendorName:vendorName deviceName:deviceName];
	
	NSNumber *pciClass = @((classCode.intValue >> 16) & 0xFF);
	NSNumber *pciSubClass = @((classCode.intValue >> 8) & 0xFF);
	
	NSMutableDictionary *classDictionary = [_pciClassesDictionary objectForKey:pciClass];
	
	if (classDictionary != nil)
	{
		*className = [classDictionary objectForKey:@"ClassName"];
		NSMutableDictionary *subclassesDictionary = [classDictionary objectForKey:@"SubClasses"];
		*subclassName = [subclassesDictionary objectForKey:pciSubClass];
	}
	
	if (*className == nil)
		*className = @"???";
	
	if (*subclassName == nil)
		*subclassName = @"???";
	
	return result;
}

- (bool)downloadPCIIDs
{
	NSError *error;
	NSData *pciIDsData = [NSData dataWithContentsOfURL:[NSURL URLWithString:PCIIDsUrl] options:NSDataReadingUncached error:&error];
	
	if (pciIDsData == nil)
		return false;
	
	[pciIDsData writeToFile:PCIIDsPath atomically:YES];
	
	return true;
}

- (void)updatePCIIDs
{
	[_pciDevicesArray release];
	
	if (!getIORegPCIDeviceArray(&_pciDevicesArray))
		return;
	
	for (NSMutableDictionary *pciDeviceDictionary in _pciDevicesArray)
	{
		NSString *ioregIOName = [pciDeviceDictionary objectForKey:@"IORegIOName"];
		NSNumber *vendorID = [pciDeviceDictionary objectForKey:@"VendorID"];
		NSNumber *deviceID = [pciDeviceDictionary objectForKey:@"DeviceID"];
		NSNumber *classCode = [pciDeviceDictionary objectForKey:@"ClassCode"];
		
		NSString *vendorName = nil, *deviceName = nil, *className = nil, *subclassName = nil;
		
		[self getPCIDeviceInfo:vendorID deviceID:deviceID classCode:classCode vendorName:&vendorName deviceName:&deviceName className:&className subclassName:&subclassName];
		
		[pciDeviceDictionary setObject:vendorName forKey:@"VendorName"];
		[pciDeviceDictionary setObject:deviceName forKey:@"DeviceName"];
		[pciDeviceDictionary setObject:className forKey:@"ClassName"];
		[pciDeviceDictionary setObject:subclassName forKey:@"SubClassName"];
		
		if ([vendorID unsignedIntValue] == VEN_INTEL_ID && [ioregIOName isEqualToString:@"display"])
		{
			// Intel Power Gadget requires "model" entry to start with Intel
			if (![deviceName hasPrefix:@"Intel"])
				[pciDeviceDictionary setObject:[@"Intel " stringByAppendingString:deviceName] forKey:@"DeviceName"];
		}
		
		//NSLog(@"%@ (%@, %@)", deviceName, className, subclassName);
		//NSLog(@"%04X %04X %04X %04X %@ %@ %@", [vendorID unsignedIntValue], [deviceID unsignedIntValue], [subVendorID unsignedIntValue], [subDeviceID unsignedIntValue], vendorName, deviceName, bundleID);
	}
	
	[_pciDevicesTableView reloadData];
}

- (void)writePCIDevicesTable
{
	NSMutableString *outputString = [NSMutableString string];

	[outputString appendString:@"DEBUG   VID  DID  SVID SDID ASPM   Vendor Name                    Device Name                                        Class Name           SubClass Name        IOReg Name      IOReg IOName    Device Path\n"];
	[outputString appendString:@"----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------\n"];
	
	for (int i = 0; i < [_pciDevicesArray count]; i++)
	{
		NSMutableDictionary *pciDeviceDictionary = _pciDevicesArray[i];
		NSString *pciDebug = [pciDeviceDictionary objectForKey:@"PCIDebug"];
		NSNumber *vendorID = [pciDeviceDictionary objectForKey:@"VendorID"];
		NSNumber *deviceID = [pciDeviceDictionary objectForKey:@"DeviceID"];
		NSNumber *subVendorID = [pciDeviceDictionary objectForKey:@"SubVendorID"];
		NSNumber *subDeviceID = [pciDeviceDictionary objectForKey:@"SubDeviceID"];
		NSString *aspm = [pciDeviceDictionary objectForKey:@"ASPM"];
		//NSNumber *aspm = [pciDeviceDictionary objectForKey:@"ASPM"];
		NSString *vendorName = [pciDeviceDictionary objectForKey:@"VendorName"];
		NSString *deviceName = [pciDeviceDictionary objectForKey:@"DeviceName"];
		NSString *className = [pciDeviceDictionary objectForKey:@"ClassName"];
		NSString *subclassName = [pciDeviceDictionary objectForKey:@"SubClassName"];
		NSString *ioregName = [pciDeviceDictionary objectForKey:@"IORegName"];
		NSString *ioregIOName = [pciDeviceDictionary objectForKey:@"IORegIOName"];
		NSString *devicePath = [pciDeviceDictionary objectForKey:@"DevicePath"];
		//NSString *bundleID = [pciDeviceDictionary objectForKey:@"BundleID"];
		
		pciDebug = [pciDebug substringToIndex:min((int)pciDebug.length, 8)];
		aspm = [aspm substringToIndex:min((int)aspm.length, 6)];
		vendorName = [vendorName substringToIndex:min((int)vendorName.length, 30)];
		deviceName = [deviceName substringToIndex:min((int)deviceName.length, 50)];
		className = [className substringToIndex:min((int)className.length, 20)];
		subclassName = [subclassName substringToIndex:min((int)subclassName.length, 20)];
		ioregName = [ioregName substringFromIndex:ioregName.length - min((int)ioregName.length, 15)];
		ioregIOName = [ioregIOName substringToIndex:min((int)ioregIOName.length, 15)];
		
		[outputString appendFormat:@"%-7s ", [pciDebug UTF8String]];
		[outputString appendFormat:@"%04X ", [vendorID unsignedIntValue]];
		[outputString appendFormat:@"%04X ", [deviceID unsignedIntValue]];
		[outputString appendFormat:@"%04X ", [subVendorID unsignedIntValue]];
		[outputString appendFormat:@"%04X ", [subDeviceID unsignedIntValue]];
		[outputString appendFormat:@"%-6s ", [aspm UTF8String]];
		//[outputString appendFormat:@"%04X ", [aspm unsignedIntValue]];
		[outputString appendFormat:@"%-30s ", [vendorName UTF8String]];
		[outputString appendFormat:@"%-50s ", [deviceName UTF8String]];
		[outputString appendFormat:@"%-20s ", [className UTF8String]];
		[outputString appendFormat:@"%-20s ", [subclassName UTF8String]];
		[outputString appendFormat:@"%15s ", [ioregName UTF8String]];
		[outputString appendFormat:@"%-15s ", [ioregIOName UTF8String]];
		[outputString appendFormat:@"%@ ", devicePath];
		[outputString appendString:@"\n"];
	}
	
	NSError *error;
	NSString *desktopPath = [NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES) objectAtIndex:0];
	NSString *pciDevicesPath = [desktopPath stringByAppendingPathComponent:@"pcidevices.txt"];
	
	if ([outputString writeToFile:pciDevicesPath atomically:YES encoding:NSUTF8StringEncoding error:&error])
	{
		NSArray *fileURLs = [NSArray arrayWithObjects:[NSURL fileURLWithPath:pciDevicesPath], nil];
		[[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:fileURLs];
	}
}

- (void)writePCIDevicesJSON
{
	NSError *error;
	
	NSString *desktopPath = [NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES) objectAtIndex:0];
	NSString *pciDevicesJSONPath = [desktopPath stringByAppendingPathComponent:@"pcidevices.json"];
	NSData *jsonData = [NSJSONSerialization dataWithJSONObject:_pciDevicesArray options:NSJSONWritingPrettyPrinted error:&error];
	NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
	
	[jsonString writeToFile:pciDevicesJSONPath atomically:YES encoding:NSUTF8StringEncoding error:&error];
}

- (void)writePCIDevicesConfig
{
	//NSError *error;
	NSString *desktopPath = [NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES) objectAtIndex:0];
	NSString *pciDevicesPlistPath = [desktopPath stringByAppendingPathComponent:@"pcidevices.plist"];
	NSMutableDictionary *configDictionary = [NSMutableDictionary dictionary];
	
	getConfigDictionary(self, configDictionary, true);
	
	[configDictionary writeToFile:pciDevicesPlistPath atomically:YES];
}

- (void)getPCIConfigDictionary:(NSMutableDictionary *)configDictionary
{
	NSMutableDictionary *devicesPropertiesDictionary = ([self isBootloaderOpenCore] ? [OpenCore getDevicePropertiesDictionaryWith:configDictionary typeName:@"Add"] : [Clover getDevicesPropertiesDictionaryWith:configDictionary]);
	
	for (int i = 0; i < [_pciDevicesArray count]; i++)
	{
		NSMutableDictionary *pciDeviceDictionary = _pciDevicesArray[i];
		//NSString *ioregName = [pciDeviceDictionary objectForKey:@"IORegName"];
		NSString *deviceName = [pciDeviceDictionary objectForKey:@"DeviceName"];
		NSString *className = [pciDeviceDictionary objectForKey:@"ClassName"];
		NSString *subClassName = [pciDeviceDictionary objectForKey:@"SubClassName"];
		NSString *devicePath = [pciDeviceDictionary objectForKey:@"DevicePath"];
		NSString *slotName = [pciDeviceDictionary objectForKey:@"SlotName"];
		//bool isIGPU = [ioregName hasSuffix:@"IGPU"];
		//bool isHDEF = [ioregName hasSuffix:@"HDEF"];
		
		NSMutableDictionary *deviceDictionary = [devicesPropertiesDictionary objectForKey:devicePath];
		
		if (deviceDictionary == nil)
			deviceDictionary = [NSMutableDictionary dictionary];
		
		//if (isGPU)
		//	[deviceDictionary setObject:deviceName forKey:@"AAPL,model"];
		
		[deviceDictionary setObject:deviceName forKey:@"model"];
		[deviceDictionary setObject:([subClassName isEqualToString:@"???"] ? className : subClassName) forKey:@"device_type"];
		[deviceDictionary setObject:slotName forKey:@"AAPL,slot-name"];
		
		[devicesPropertiesDictionary setObject:deviceDictionary forKey:devicePath];
	}
}

- (void)appendTabCount:(uint32_t)tabCount outputString:(NSMutableString *)outputString
{
	for (int i = 0; i < tabCount; i++)
		[outputString appendString:@"\t"];
}

- (void)appendDSLString:(uint32_t)tabCount outputString:(NSMutableString *)outputString value:(NSString *)value
{
	[self appendTabCount:tabCount outputString:outputString];
	[outputString appendFormat:@"%@\n", value];
}

- (void)appendDSLValue:(uint32_t)tabCount outputString:(NSMutableString *)outputString name:(NSString *)name value:(id)value
{
	[self appendTabCount:tabCount outputString:outputString];
	[outputString appendFormat:@"\"%@\", ", name];
	
	[outputString appendFormat:@"Buffer () { "];
	
	if ([value isKindOfClass:[NSString class]])
		[outputString appendFormat:@"\"%@\" },\n", value];
	else if ([value isKindOfClass:[NSData class]])
		[outputString appendFormat:@"%@ },\n", getByteString(value)];
}

- (void)appendDSLString:(uint32_t)tabCount outputString:(NSMutableString *)outputString name:(NSString *)name value:(NSString *)value
{
	[self appendTabCount:tabCount outputString:outputString];
	[outputString appendFormat:@"\"%@\", \"%@\" },\n", name, value];
}

- (bool)hasNVIDIAGPU
{
	return [self hasGPU:VEN_NVIDIA_ID];
}

- (bool)hasAMDGPU
{
	return [self hasGPU:VEN_AMD_ID];
}

- (bool)hasIntelGPU
{
	return [self hasGPU:VEN_INTEL_ID];
}

- (bool)hasGFX0
{
	NSMutableDictionary *pciDeviceDictionary;
	
	return [self tryGetPCIDeviceDictionaryFromIORegName:@"GFX0" pciDeviceDictionary:&pciDeviceDictionary];
}

- (bool)hasIGPU
{
	NSMutableDictionary *pciDeviceDictionary;
	
	return [self tryGetPCIDeviceDictionaryFromIORegName:@"IGPU" pciDeviceDictionary:&pciDeviceDictionary];
}

- (bool)hasGPU:(uint32_t)vID
{
	for (int i = 0; i < [_pciDevicesArray count]; i++)
	{
		NSMutableDictionary *pciDeviceDictionary = _pciDevicesArray[i];
		NSString *ioregIOName = [pciDeviceDictionary objectForKey:@"IORegIOName"];
		NSNumber *vendorID = [pciDeviceDictionary objectForKey:@"VendorID"];
		
		if ([vendorID unsignedIntValue] == vID && [ioregIOName isEqualToString:@"display"])
			return true;
	}
	
	return false;
}

- (bool)isBootloaderOpenCore
{
	return ((_settings.SelectedBootloader == kBootloaderAutoDetect && _settings.DetectedBootloader == kBootloaderOpenCore) || (_settings.SelectedBootloader == kBootloaderOpenCore));
}

- (bool)tryGetACPIPath:(NSString *)ioregName acpiPath:(NSString **)acpiPath
{
	if (ioregName == nil)
		return false;
	
	*acpiPath = @"";
	NSArray *ioregArray = [ioregName componentsSeparatedByString:@"/"];
	
	for (int i = 0; i < [ioregArray count]; i++)
	{
		NSString *ioregEntry = ioregArray[i];
		NSRange atRange = [ioregEntry rangeOfString:@"@" options:NSBackwardsSearch];
		
		if (atRange.location != NSNotFound)
			ioregEntry = [ioregEntry substringToIndex:atRange.location];
		
		if ([ioregEntry length] > 4)
			return false;
		
		*acpiPath = [*acpiPath stringByAppendingString:ioregEntry];
		
		if (i > 0 && i < [ioregArray count] - 1)
			*acpiPath = [*acpiPath stringByAppendingString:@"."];
	}
	
	return true;
}

- (NSString *)getIORegName:(NSString *)ioregName
{
	if (ioregName == nil)
		return @"";
	
	NSRange periodRange = [ioregName rangeOfString:@"/" options:NSBackwardsSearch];
	
	if (periodRange.location != NSNotFound)
		ioregName = [ioregName substringFromIndex:periodRange.location + 1];
	
	NSRange atRange = [ioregName rangeOfString:@"@" options:NSBackwardsSearch];
	
	if (atRange.location != NSNotFound)
		ioregName = [ioregName substringToIndex:atRange.location];
	
	return ioregName;
}

- (void)getFakeGPUDeviceDictionary:(NSMutableDictionary **)pciDeviceDictionary
{
	*pciDeviceDictionary = [NSMutableDictionary dictionary];
	
    [*pciDeviceDictionary setObject:@"Disabled" forKey:@"ASPM"];
    [*pciDeviceDictionary setObject:@(0x20000) forKey:@"Address"];
    [*pciDeviceDictionary setObject:@"com.apple.driver.AppleIntelCFLGraphicsFramebuffer" forKey:@"BundleID"];
    [*pciDeviceDictionary setObject:@(0x30000) forKey:@"ClassCode"];
    [*pciDeviceDictionary setObject:@"Display controller" forKey:@"ClassName"];
    [*pciDeviceDictionary setObject:@(0x0000) forKey:@"DeviceID"];
    [*pciDeviceDictionary setObject:@"Intel Graphics (Unknown)" forKey:@"DeviceName"];
    [*pciDeviceDictionary setObject:@"PciRoot(0x0)/Pci(0x2,0x0)" forKey:@"DevicePath"];
    [*pciDeviceDictionary setObject:@"display" forKey:@"IORegIOName"];
    [*pciDeviceDictionary setObject:@"/PCI0@0/IGPU@2" forKey:@"IORegName"];
    [*pciDeviceDictionary setObject:@"IOService:/AppleACPIPlatformExpert/PCI0@0/AppleACPIPCI/IGPU@2" forKey:@"IORegPath"];
    [*pciDeviceDictionary setObject:@"Intel Graphics (Unknown)" forKey:@"Model"];
    [*pciDeviceDictionary setObject:@"00:02.0" forKey:@"PCIDebug"];
    [*pciDeviceDictionary setObject:@(0x0000) forKey:@"ShadowDevice"];
    [*pciDeviceDictionary setObject:@(0x8086) forKey:@"ShadowVendor"];
    [*pciDeviceDictionary setObject:@"Internal@0,2,0" forKey:@"SlotName"];
    [*pciDeviceDictionary setObject:@"VGA compatible controller" forKey:@"SubClassName"];
    [*pciDeviceDictionary setObject:@(0x0000) forKey:@"SubDeviceID"];
    [*pciDeviceDictionary setObject:@(0x0000) forKey:@"SubVendorID"];
    [*pciDeviceDictionary setObject:@(0x8086) forKey:@"VendorID"];
    [*pciDeviceDictionary setObject:@"Intel Corporation" forKey:@"VendorName"];
}

- (bool)tryGetGPUDeviceDictionary:(NSMutableDictionary **)pciDeviceDictionary
{
	if ([self tryGetPCIDeviceDictionaryFromIORegName:@"IGPU" pciDeviceDictionary:pciDeviceDictionary])
		return true;
	
	if (!_settings.InjectFakeIGPU)
		return false;
	
	[self getFakeGPUDeviceDictionary:pciDeviceDictionary];
	
	return true;
}

- (bool)tryGetPCIDeviceDictionaryFromIORegName:(NSString *)name pciDeviceDictionary:(NSMutableDictionary **)pciDeviceDictionary
{
	for (int i = 0; i < [_pciDevicesArray count]; i++)
	{
		*pciDeviceDictionary = _pciDevicesArray[i];
		NSString *ioregName = [*pciDeviceDictionary objectForKey:@"IORegName"];
		
		if ([name isEqualToString:ioregName])
			return true;
	}
	
	for (int i = 0; i < [_pciDevicesArray count]; i++)
	{
		*pciDeviceDictionary = _pciDevicesArray[i];
		NSString *ioregName = [*pciDeviceDictionary objectForKey:@"IORegName"];
		
		if ([[self getIORegName:name] isEqualToString:[self getIORegName:ioregName]])
			return true;
	}
	
	return false;
}

- (bool)tryGetPCIDeviceDictionaryFromClassCode:(NSNumber *)code pciDeviceDictionary:(NSMutableDictionary **)pciDeviceDictionary
{
	for (int i = 0; i < [_pciDevicesArray count]; i++)
	{
		*pciDeviceDictionary = _pciDevicesArray[i];
		NSNumber *classCode = [*pciDeviceDictionary objectForKey:@"ClassCode"];
		
		if ([code isEqualToNumber:classCode])
			return true;
	}
	
	return false;
}

- (bool)tryGetAudioController:(NSNumber *)deviceID vendorID:(NSNumber *)vendorID audioDevice:(AudioDevice *)foundAudioDevice
{
	for (int i = 0; i < [_pciDevicesArray count]; i++)
	{
		NSMutableDictionary *pciDeviceDictionary = _pciDevicesArray[i];
		NSNumber *vendorID = [pciDeviceDictionary objectForKey:@"VendorID"];
		NSNumber *deviceID = [pciDeviceDictionary objectForKey:@"DeviceID"];
		
		for (AudioDevice *audioDevice in _audioDevicesArray)
		{
			NSNumber *audioVendorID = [NSNumber numberWithInt:audioDevice.deviceID >> 16];
			NSNumber *audioDeviceID = [NSNumber numberWithInt:audioDevice.deviceID & 0xFFFF];
			
			if (![vendorID isEqualToNumber:audioVendorID] ||
				![deviceID isEqualToNumber:audioDeviceID] ||
				![self isAppleHDAAudioDevice:audioDevice])
				continue;
			
			foundAudioDevice = audioDevice;
			
			return true;
		}

	}
	
	return false;
}

- (bool)isAppleHDAAudioDevice:(AudioDevice *)audioDevice
{
	return ([audioDevice.deviceClass isEqualToString:@"AppleHDADriver"]);
}

- (bool)isVoodooHDAAudioDevice:(AudioDevice *)audioDevice
{
	return ([audioDevice.deviceClass isEqualToString:@"VoodooHDADevice"]);
}

- (void)writePCIDevicesDSL
{
	NSMutableString *outputString = [NSMutableString string];
	
	NSError *error;
	NSString *desktopPath = [NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES) objectAtIndex:0];
	NSString *pciDevicesDSLPath = [desktopPath stringByAppendingPathComponent:@"pcidevices.dsl"];
	NSMutableDictionary *configDictionary = [NSMutableDictionary dictionary];
	
	getConfigDictionary(self, configDictionary, true);
	
	[self appendDSLString:0 outputString:outputString value:@"DefinitionBlock (\"\", \"SSDT\", 2, \"HACK\", \"PCI\", 0x00000000)"];
	[self appendDSLString:0 outputString:outputString value:@"{"];
	
	for (int i = 0; i < [_pciDevicesArray count]; i++)
	{
		NSMutableDictionary *pciDeviceDictionary = _pciDevicesArray[i];
		NSString *ioregName = [pciDeviceDictionary objectForKey:@"IORegName"];
		
		appendFramebufferInfoDSL(self, 1, configDictionary, ioregName, &outputString);
	}
	
	[self appendDSLString:0 outputString:outputString value:@"}"];
	
	[outputString writeToFile:pciDevicesDSLPath atomically:YES encoding:NSUTF8StringEncoding error:&error];
}

- (void)outputArray:(NSMutableString *)outputString title:(NSString *)title array:(NSMutableArray *)array
{
	[outputString appendString:@"-----------------------------------------------------------------------\n"];
	[outputString appendFormat:@"%@\n", title];
	[outputString appendString:@"-----------------------------------------------------------------------\n"];
	
	for (NSDictionary *dictionary in array)
	{
		NSString *name = [dictionary objectForKey:@"Name"];
		NSString *value = [dictionary objectForKey:@"Value"];
		
		name = [name substringToIndex:min((int)name.length, 30)];
		
		[outputString appendFormat:@"%-30s %@\n", name.UTF8String, value];
	}
}

- (void)writeInfo
{
	NSMutableString *outputString = [NSMutableString string];
	
	NSError *error;
	NSString *desktopPath = [NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES) objectAtIndex:0];
	NSString *infoPath = [desktopPath stringByAppendingPathComponent:@"info.txt"];
	
	[self outputArray:outputString title:@"System Info" array:_systemInfoArray];
	[self outputArray:outputString title:@"Serial Info" array:_serialInfoArray];
	
	for (NSString *gpuName in _gpuInfoDictionary.allKeys)
		[self outputArray:outputString title:gpuName array:[_gpuInfoDictionary objectForKey:gpuName]];
	
	[self outputArray:outputString title:@"iMessage Keys" array:_iMessageKeysArray];
	
	[outputString appendString:@"-----------------------------------------------------------------------\n"];
	
	if ([outputString writeToFile:infoPath atomically:YES encoding:NSUTF8StringEncoding error:&error])
	{
		NSArray *fileURLs = [NSArray arrayWithObjects:[NSURL fileURLWithPath:infoPath], nil];
		[[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:fileURLs];
	}
}

- (void)initInfo
{
	NSLog(@"Initializing Info");
	
	[self updateNetworkInterfaces];
	[self updateBluetoothDevices];
	[_audioDevicesTableView2 reloadData];
	[self updateGraphicDevices];
	[self updateStorageDevices];
}

- (void)updateNetworkInterfaces
{
	[_networkInterfacesArray release];
	
	if (!getIORegNetworkArray(&_networkInterfacesArray))
		return;
	
	for (NSMutableDictionary *networkInterfacesDictionary in _networkInterfacesArray)
	{
		NSNumber *vendorID = [networkInterfacesDictionary objectForKey:@"VendorID"];
		NSNumber *deviceID = [networkInterfacesDictionary objectForKey:@"DeviceID"];
		
		NSString *vendorName = nil, *deviceName = nil;
		
		[self getPCIDeviceInfo:vendorID deviceID:deviceID vendorName:&vendorName deviceName:&deviceName];
		
		[networkInterfacesDictionary setObject:vendorName forKey:@"VendorName"];
		[networkInterfacesDictionary setObject:deviceName forKey:@"DeviceName"];
	}
	
	[_networkInterfacesTableView reloadData];
}

- (void)updateBluetoothDevices
{
	_bluetoothDevicesArray = [[NSMutableArray array] retain];
	
	NSMutableArray *bluetoothArray = nil;
	
	if (getIORegPropertyDictionaryArrayWithParent(@"IOBluetoothHostControllerTransport", @"IOUSBDevice", &bluetoothArray))
	{
		for (NSDictionary *deviceDictionary in bluetoothArray)
		{
			NSString *productName = [deviceDictionary objectForKey:@"USB Product Name"];
			NSString *vendorName = [deviceDictionary objectForKey:@"USB Vendor Name"];
			NSNumber *productID = [deviceDictionary objectForKey:@"idProduct"];
			NSNumber *vendorID = [deviceDictionary objectForKey:@"idVendor"];
			NSNumber *fwLoaded = [deviceDictionary objectForKey:@"FirmwareLoaded"];
			
			// Try legacy entry
			if (fwLoaded == nil)
				fwLoaded = [deviceDictionary objectForKey:@"RM,FirmwareLoaded"];
			
			// PCI device
			if (productID == nil && vendorID == nil)
			{
				uint32_t deviceIDInt = propertyToUInt32([deviceDictionary objectForKey:@"device-id"]);
				uint32_t vendorIDInt = propertyToUInt32([deviceDictionary objectForKey:@"vendor-id"]);
				
				productID = [NSNumber numberWithUnsignedInt:deviceIDInt];
				vendorID = [NSNumber numberWithUnsignedInt:vendorIDInt];
				
				[self getPCIDeviceInfo:vendorID deviceID:productID vendorName:&vendorName deviceName:&productName];
			}
			
			NSMutableDictionary *bluetoothDeviceDictionary = [NSMutableDictionary dictionary];
			
			[bluetoothDeviceDictionary setObject:vendorID forKey:@"VendorID"];
			[bluetoothDeviceDictionary setObject:productID forKey:@"DeviceID"];
			[bluetoothDeviceDictionary setObject:(vendorName != nil ? vendorName : @"???") forKey:@"VendorName"];
			[bluetoothDeviceDictionary setObject:(productName != nil ? productName : @"???") forKey:@"DeviceName"];
			[bluetoothDeviceDictionary setObject:@"com.apple.iokit.IOBluetoothHostControllerTransport" forKey:@"BundleID"];
			
			if (fwLoaded)
				[bluetoothDeviceDictionary setObject:fwLoaded forKey:@"FWLoaded"];
			
			[_bluetoothDevicesArray addObject:bluetoothDeviceDictionary];
		}
	}
	
	NSBundle *mainBundle = [NSBundle mainBundle];
	NSString *filePath = nil;
	
	NSArray *brcmDeviceArray = nil;
	NSArray *atherosDeviceArray = nil;
	
	if ((filePath = [mainBundle pathForResource:@"BRCMDevice" ofType:@"plist" inDirectory:@"BT"]))
		brcmDeviceArray = [NSArray arrayWithContentsOfFile:filePath];
	
	if ((filePath = [mainBundle pathForResource:@"AtherosDevice" ofType:@"plist" inDirectory:@"BT"]))
		atherosDeviceArray = [NSArray arrayWithContentsOfFile:filePath];
	
	NSMutableArray *usbPropertyDictionaryArray = nil;
	
	if (!getIORegPropertyDictionaryArray(@"IOUSBDevice", &usbPropertyDictionaryArray))
		return;
	
	for (NSMutableDictionary *propertyDictionary in usbPropertyDictionaryArray)
	{
		//NSString *productName = [propertyDictionary objectForKey:@"USB Product Name"];
		NSString *vendorName = [propertyDictionary objectForKey:@"USB Vendor Name"];
		NSNumber *idProduct = [propertyDictionary objectForKey:@"idProduct"];
		NSNumber *idVendor = [propertyDictionary objectForKey:@"idVendor"];
		NSNumber *fwLoaded = [propertyDictionary objectForKey:@"RM,FirmwareLoaded"];
		
		bool foundMatch = NO;
		
		if (bluetoothArray != nil)
		{
			for (NSDictionary *bluetoothDeviceDictionary in bluetoothArray)
			{
				NSNumber *productID = [bluetoothDeviceDictionary objectForKey:@"idProduct"];
				NSNumber *vendorID = [bluetoothDeviceDictionary objectForKey:@"idVendor"];
				
				if ([productID isEqualToNumber:idProduct] && [vendorID isEqualToNumber:idVendor])
				{
					foundMatch = YES;
					
					break;
				}
			}
		}
		
		if (foundMatch)
			continue;
		
		for (NSDictionary *brcmDeviceDictionary in brcmDeviceArray)
		{
			NSString *name = [brcmDeviceDictionary objectForKey:@"Name"];
			NSNumber *productID = [brcmDeviceDictionary objectForKey:@"ProductID"];
			NSNumber *vendorID = [brcmDeviceDictionary objectForKey:@"VendorID"];
			
			if ([productID isEqualToNumber:idProduct] && [vendorID isEqualToNumber:idVendor])
			{
				NSMutableDictionary *bluetoothDeviceDictionary = [NSMutableDictionary dictionary];
				
				[bluetoothDeviceDictionary setObject:idVendor forKey:@"VendorID"];
				[bluetoothDeviceDictionary setObject:idProduct forKey:@"DeviceID"];
				[bluetoothDeviceDictionary setObject:(vendorName != nil ? vendorName : @"???") forKey:@"VendorName"];
				[bluetoothDeviceDictionary setObject:name forKey:@"DeviceName"];
				
				if (fwLoaded)
					[bluetoothDeviceDictionary setObject:fwLoaded forKey:@"FWLoaded"];
				
				[_bluetoothDevicesArray addObject:bluetoothDeviceDictionary];
				
				break;
			}
		}
		
		for (NSDictionary *atherosDeviceDictionary in atherosDeviceArray)
		{
			NSString *name = [atherosDeviceDictionary objectForKey:@"Name"];
			NSNumber *productID = [atherosDeviceDictionary objectForKey:@"ProductID"];
			NSNumber *vendorID = [atherosDeviceDictionary objectForKey:@"VendorID"];
			
			if ([productID isEqualToNumber:idProduct] && [vendorID isEqualToNumber:idVendor])
			{
				NSMutableDictionary *bluetoothDeviceDictionary = [NSMutableDictionary dictionary];
				
				[bluetoothDeviceDictionary setObject:idVendor forKey:@"VendorID"];
				[bluetoothDeviceDictionary setObject:idProduct forKey:@"DeviceID"];
				[bluetoothDeviceDictionary setObject:(vendorName != nil ? vendorName : @"???") forKey:@"VendorName"];
				[bluetoothDeviceDictionary setObject:name forKey:@"DeviceName"];
				
				if (fwLoaded)
					[bluetoothDeviceDictionary setObject:fwLoaded forKey:@"FWLoaded"];
				
				[_bluetoothDevicesArray addObject:bluetoothDeviceDictionary];
				
				break;
			}
		}
	}
	
	[_bluetoothDevicesTableView reloadData];
}

- (void)updateGraphicDevices
{
	[_graphicDevicesArray release];
	
	if (!getIORegGraphicsArray(&_graphicDevicesArray))
		return;
	
	[_graphicDevicesTableView reloadData];
}

- (void)updateStorageDevices
{
	[_storageDevicesArray release];
	
	if (!getIORegStorageArray(&_storageDevicesArray))
		return;
	
	[_storageDevicesTableView reloadData];
}

- (void)initTools
{
	_aiiEnableHWP.state = _settings.AII_EnableHWP;
	_aiiLogCStates.state = _settings.AII_LogCStates;
	_aiiLogIGPU.state = _settings.AII_LogIGPU;
	_aiiLogIPGStyle.state = _settings.AII_LogIPGStyle;
	_aiiLogIntelRegs.state = _settings.AII_LogIntelRegs;
	_aiiLogMSRs.state = _settings.AII_LogMSRs;
	
	[self initScrollableTextView:_toolsOutputTextView];
}

- (bool)getEfiBootDevice
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	
	NSString *efiBootDeviceUUID = [defaults objectForKey:@"EFIBootDeviceUUID"];
	
	if (efiBootDeviceUUID)
	{
		[self setEfiBootDeviceUUID:efiBootDeviceUUID];
		
		return true;
	}
	
	if (_bootLog != nil)
	{
		// 0:100  0:000  SelfDevicePath=PciRoot(0x0)\Pci(0x1F,0x2)\Sata(0x0,0xFFFF,0x0)\HD(1,GPT,0FBD5BD2-AE6A-4F30-BDD6-F8ABABD7E795,0x28,0x64000) @B259DB98
		// 0:100  0:000  SelfDirPath = \EFI\BOOT
		
		NSArray *bootArray = [_bootLog componentsSeparatedByString:@"\r"];
		
		for (NSString *bootLine in bootArray)
		{
			NSRange selfDevicePathRange = [bootLine rangeOfString:@"SelfDevicePath="];
			NSRange selfDirPathRange = [bootLine rangeOfString:@"SelfDirPath = "];
			
			if (selfDevicePathRange.location != NSNotFound)
			{
				NSMutableArray *itemArray = nil;
				
				if (getRegExArray(@"HD\\((.*),(.*),(.*),(.*),(.*)\\)", bootLine, 5, &itemArray))
				{
					NSString *uuid = itemArray[2];
					
					_bootloaderDeviceUUID = [uuid retain];
					
					[self setEfiBootDeviceUUID:uuid];
				}
			}
			
			if (selfDirPathRange.location != NSNotFound)
				_bootloaderDirPath = [[[bootLine substringFromIndex:selfDirPathRange.location + selfDirPathRange.length] stringByReplacingOccurrencesOfString:@"\\" withString:@"/"] retain];
		}
	}
	
	if (_nvramDictionary != nil)
	{
		id efiBootDevice = [_nvramDictionary objectForKey:@"efi-boot-device"];
		
		if (efiBootDevice != nil)
		{
			NSString *efiBootDeviceString = ([efiBootDevice isKindOfClass:[NSData class]] ? [NSString stringWithCString:(const char *)[efiBootDevice bytes] encoding:NSASCIIStringEncoding] : efiBootDevice);
			NVRAMXmlParser *nvramXmlParser = [NVRAMXmlParser initWithString:efiBootDeviceString encoding:NSASCIIStringEncoding];
			NSString *uuid = [nvramXmlParser getValue:@[@0, @"IOMatch", @"IOPropertyMatch", @"UUID"]];
			[self setEfiBootDeviceUUID:uuid];
			
			return true;
		}
	}
	
	NSMutableDictionary *chosenDictionary;
	
	if (getIORegProperties(@"IODeviceTree:/chosen", &chosenDictionary))
	{
		NSData *bootDevicePathData = [chosenDictionary objectForKey:@"boot-device-path"];
		
		if (bootDevicePathData != nil)
		{
			const unsigned char *bootDeviceBytes = (const unsigned char *)bootDevicePathData.bytes;
			CHAR8 *devicePath = ConvertHDDDevicePathToText((const EFI_DEVICE_PATH *)bootDeviceBytes);
			NSString *devicePathString = [NSString stringWithUTF8String:devicePath];
			[self setEfiBootDeviceUUID:devicePathString];
			
			return true;
		}
	}
	
	return false;
}

- (void)initScrollableTextView:(NSTextView *)textView
{
	[[textView enclosingScrollView] setHasHorizontalScroller:YES];
	[[textView enclosingScrollView] setHasVerticalScroller:YES];
	
	[textView setMaxSize:CGSizeMake(FLT_MAX, FLT_MAX)];
	[textView setHorizontallyResizable:YES];
	[textView setFont:[NSFont userFixedPitchFontOfSize:textView.font.pointSize]];
	[[textView textContainer] setWidthTracksTextView:NO];
	[[textView textContainer] setContainerSize:CGSizeMake(FLT_MAX, FLT_MAX)];
}

- (void)initLogs
{
	// https://eclecticlight.co/2016/10/17/log-a-primer-on-predicates/
	[_processLogComboBox setStringValue:@"kernel"];
	
	[self initScrollableTextView:_bootLogTextView];
	[self initScrollableTextView:_systemLogTextView];
	
	if (_bootLog != nil)
		[_bootLogTextView setString:_bootLog];
	
	[self initLiluLog];
}

- (void)initLiluLog
{
	[self initScrollableTextView:_liluLogTextView];
	
	NSError *error = nil;
	NSArray *filesArray = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:@"/var/log" error:&error];
	
	if(error != nil)
	{
		NSLog(@"Error in reading files: %@", [error localizedDescription]);
		return;
	}
	
	// sort by creation date
	NSMutableArray *filesAndProperties = [NSMutableArray arrayWithCapacity:[filesArray count]];
	
	for(NSString *file in filesArray)
	{
		if (![file hasPrefix:@"Lilu_"])
			continue;
		
		NSString *filePath = [@"/var/log" stringByAppendingPathComponent:file];
		NSDictionary *properties = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:&error];
		NSDate *modDate = [properties objectForKey:NSFileModificationDate];
		
		if(error == nil)
			[filesAndProperties addObject:[NSDictionary dictionaryWithObjectsAndKeys:file, @"path", modDate, @"lastModDate", nil]];
	}
	
	// sort using a block
	// order inverted as we want latest date first
	NSArray *sortedFiles = [filesAndProperties sortedArrayUsingComparator:^(id path1, id path2)
							{
								// compare
								NSComparisonResult comp = [[path1 objectForKey:@"lastModDate"] compare:[path2 objectForKey:@"lastModDate"]];
								
								// invert ordering
								if (comp == NSOrderedDescending)
									comp = NSOrderedAscending;
								else if(comp == NSOrderedAscending)
									comp = NSOrderedDescending;
								
								return comp;
							}];
	
	if ([sortedFiles count] > 0)
	{
		NSString *logFileName = [@"/var/log" stringByAppendingPathComponent:[sortedFiles[0] objectForKey:@"path"]];
		NSString *logString = [NSString stringWithContentsOfFile:logFileName encoding:NSUTF8StringEncoding error:&error];
		
		if (logString != nil)
			[_liluLogTextView setString:logString];
	}
}

- (void)initDisplays
{
	NSLog(@"Initializing Displays");
	
	_displaysArray = [[NSMutableArray array] retain];
	
	NSArray *iconArray = @[@"Default", @"iMac", @"MacBook", @"MacBook Pro", @"LG Display"];
	[_iconComboBox addItemsWithObjectValues:translateArray(iconArray)];
	
	NSArray *resolutionArray = @[@"1080p", @"2K", @"Manual"];
	[_resolutionComboBox addItemsWithObjectValues:translateArray(resolutionArray)];
	
	[self refreshDisplays];
}

- (void)clearDisplays
{
	for (Display *display in _displaysArray)
		[display.resolutionsArray removeAllObjects];
}

- (bool)getCurrentlySelectedDisplay:(Display **)display
{
	NSInteger index;
	
	return [self getCurrentlySelectedDisplay:display index:index];
}

- (bool)getCurrentlySelectedDisplay:(Display **)display index:(NSInteger &)index
{
	NSIndexSet *indexSex = [_displaysTableView selectedRowIndexes];
	index = [indexSex lastIndex];
	
	if (index == NSNotFound)
		return false;
	
	*display = _displaysArray[index];
	
	return true;
}

- (void)initInstalled
{
	NSLog(@"Initializing Installed");
	
	_installedKextsArray = [[NSMutableArray array] retain];
	
	[self getInstalledKextVersionDictionary];
	
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSArray *kextsArray = [defaults objectForKey:@"Kexts"];
	
	NSBundle *mainBundle = [NSBundle mainBundle];
	NSString *filePath = nil;
	
	if ((filePath = [mainBundle pathForResource:@"kexts" ofType:@"plist" inDirectory:@"Kexts"]))
	{
		_kextsArray = [[NSMutableArray arrayWithContentsOfFile:filePath] retain];
		
		NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"Name" ascending:YES];
		[_kextsArray sortUsingDescriptors:[NSArray arrayWithObjects:sortDescriptor, nil]];

		for (int i = 0; i < _kextsArray.count; i++)
		{
			NSMutableDictionary *kextDictionary = _kextsArray[i];
			NSString *name = [kextDictionary objectForKey:@"Name"];
			NSString *bundleID = [kextDictionary objectForKey:@"BundleID"];
			NSString *downloadUrl = [kextDictionary objectForKey:@"DownloadUrl"];
			NSString *installedVersion = [_installedKextVersionDictionary objectForKey:[(bundleID != nil ? bundleID : name) lowercaseString]];
			
			[kextDictionary setObject:(installedVersion != nil ? installedVersion : @"") forKey:@"InstalledVersion"];
			[kextDictionary setObject:@"" forKey:@"CurrentVersion"];
			[kextDictionary setObject:@"" forKey:@"DownloadVersion"];
			
			if (downloadUrl == nil)
			{
				for (NSMutableDictionary *savedKextDictionary in kextsArray)
				{
					NSString *savedName = [savedKextDictionary objectForKey:@"Name"];
					NSString *savedDownloadUrl = [savedKextDictionary objectForKey:@"DownloadUrl"];
					
					if (savedDownloadUrl == nil)
						continue;
					
					if ([name isEqualToString:savedName])
					{
						[kextDictionary setObject:savedDownloadUrl forKey:@"DownloadUrl"];
						NSString *downloadVersion = nil;
						
						if ([self tryGetGithubDownloadVersion:savedDownloadUrl downloadVersion:&downloadVersion])
							[kextDictionary setObject:downloadVersion forKey:@"DownloadVersion"];
					}
				}
			}
			
			if (installedVersion != nil)
				[_installedKextsArray addObject:kextDictionary];
		
			_kextsArray[i] = kextDictionary;
		}
	}
	
	[self initScrollableTextView:_compileOutputTextView];
	
	[_kextsTableView reloadData];
}

- (void)saveInstalledKexts
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	
	[defaults setObject:_kextsArray forKey:@"Kexts"];
	
	[defaults synchronize];
}

- (void)getInstalledKextVersionDictionary
{
	// Index Refs Address            Size       Wired      Name (Version) UUID <Linked Against>
	// 37    5 0xffffff7f83eb9000 0x7a000    0x7a000    as.vit9696.Lilu (1.3.5) 0549BD9D-468A-377C-AB76-401D911019D0 <8 6 5 3 2 1>
	// 38    0 0xffffff7f83f33000 0x107000   0x107000   as.vit9696.AppleALC (1.3.6) EFFD4C0F-673F-3841-A5A2-3C411BD6BCAA <37 13 8 6 5 3 2 1>
	// 39    0 0xffffff7f8403a000 0x7b000    0x7b000    as.vit9696.WhateverGreen (1.2.8) 590C1D25-9E29-3455-8EF9-0E5E78880242 <37 13 8 6 5 3 2 1>
	// 40    0 0xffffff7f840b5000 0x6000     0x6000     as.lvs1974.AirportBrcmFixup (2.0.0) B2719290-4DE3-36EC-9483-1990086F54F0 <37 16 13 8 6 5 3 2 1>
	// 41    0 0xffffff7f840bb000 0x5000     0x5000     as.lvs1974.HibernationFixup (1.2.4) 605DDBEF-3997-3AF0-9E0F-5D69CBD5AD38 <37 8 6 5 3 2 1>

	// kextstat -l
	
	_installedKextVersionDictionary = [[NSMutableDictionary dictionary] retain];
	
	NSString *stdoutString = nil;
	
	if (!launchCommand(@"/usr/sbin/kextstat", @[@"-l"], &stdoutString))
		return;
	
	NSArray *stdoutArray = [stdoutString componentsSeparatedByString:@"\n"];
	
	for (NSString *stdoutLine in stdoutArray)
	{
		NSMutableArray *kextArray = [[[stdoutLine componentsSeparatedByString:@" "] mutableCopy] autorelease];
		[kextArray removeObject:@""];
		
		if ([kextArray count] < 8)
			continue;
		
		NSString *name = [kextArray objectAtIndex:5];
		NSMutableArray *nameArray = [[[name componentsSeparatedByString:@"."] mutableCopy] autorelease];
		[nameArray removeObject:@"kext"];
		name = [nameArray lastObject];
		NSString *version = [kextArray objectAtIndex:6];
		NSCharacterSet *characterSet = [NSCharacterSet characterSetWithCharactersInString:@"()"];
		version = [version stringByTrimmingCharactersInSet:characterSet];
		
		[_installedKextVersionDictionary setObject:version forKey:[name lowercaseString]];
	}
}

- (bool)tryGetGithubDownloadVersion:(NSString *)downloadUrl downloadVersion:(NSString **)downloadVersion
{
	if (downloadUrl == nil)
		return false;
	
	bool isGithub = [downloadUrl containsString:@"github.com"];
	
	if (!isGithub)
		return false;
	
	*downloadVersion = [[downloadUrl stringByDeletingLastPathComponent] lastPathComponent];
	*downloadVersion = [*downloadVersion stringByReplacingOccurrencesOfString:@"v" withString:@""];
	
	return true;
}

- (Boolean)getGithubLatestDownloadInfo:(NSString *)url fileNameMatch:(NSString *)fileNameMatch browserDownloadUrl:(NSString **)downloadUrl downloadVersion:(NSString **)downloadVersion
{
	NSError *error;
	NSURL *gitHubAPIUrl = [NSURL URLWithString:url];
	NSData *jsonData = [NSData dataWithContentsOfURL:gitHubAPIUrl options:NSDataReadingUncached error:&error];
	
	if (jsonData == nil)
		return false;
	
	NSDictionary *jsonDictionary = [NSJSONSerialization JSONObjectWithData:jsonData options:NSJSONWritingPrettyPrinted error:&error];
	NSArray *assetArray = [jsonDictionary objectForKey:@"assets"];
	
	if (assetArray == nil || [assetArray count] == 0)
		return false;
	
	for (NSDictionary *assetsDictionary in assetArray)
	{
		NSString *browserDownloadUrl = [assetsDictionary objectForKey:@"browser_download_url"];
		NSString *fileName = [browserDownloadUrl lastPathComponent];
		NSString *version = nil;
		
		if (browserDownloadUrl == nil)
			continue;
		
		if ([fileName rangeOfString:@"debug" options:NSCaseInsensitiveSearch].location != NSNotFound)
			continue;
		
		if (fileNameMatch != nil)
		{
			if ([fileName rangeOfString:fileNameMatch options:NSCaseInsensitiveSearch].location == NSNotFound)
				continue;
		}
		
		*downloadUrl = [browserDownloadUrl retain];

		if ([self tryGetGithubDownloadVersion:browserDownloadUrl downloadVersion:&version])
			*downloadVersion = [version retain];
		
		return true;
	}
	
	return false;
}

- (Boolean)getGithubDownloadUrl:(NSMutableDictionary **)kextDictionary
{
	//NSString *name = [*kextDictionary objectForKey:@"Name"];
	NSString *projectUrl = [*kextDictionary objectForKey:@"ProjectUrl"];
	bool isGithub = [projectUrl containsString:@"github.com"];
	NSString *projectName = [projectUrl lastPathComponent];
	NSString *username = [[projectUrl stringByDeletingLastPathComponent] lastPathComponent];
	
	if (!isGithub)
		return false;
	
	NSString *githubUrl = [NSString stringWithFormat:@"https://api.github.com/repos/%@/%@/releases/latest", username, projectName];
	NSString *browserDownloadUrl = nil, *downloadVersion = nil;
	
	if ([self getGithubLatestDownloadInfo:githubUrl fileNameMatch:nil browserDownloadUrl:&browserDownloadUrl downloadVersion:&downloadVersion])
	{
		[*kextDictionary setObject:browserDownloadUrl forKey:@"DownloadUrl"];
		
		if (downloadVersion != nil)
			[*kextDictionary setObject:downloadVersion forKey:@"DownloadVersion"];
	}
	
	return false;
}

- (NSMutableArray *)getSelectedKextsArray
{
	NSMutableArray *kextsArray = (_settings.ShowInstalledOnly ? _installedKextsArray : _kextsArray);
	NSMutableArray *selectedArray = [NSMutableArray array];
	
	for (int i = 0; i < kextsArray.count; i++)
	{
		NSButton *button = [_kextsTableView viewAtColumn:0 row:i makeIfNecessary:NO];
		[selectedArray addObject:[NSNumber numberWithBool:button.state]];
		button.state = NO;
	}
	
	return selectedArray;
}

- (void)appendTextViewWithFormat:(NSTextView *)textView foregroundColor:(NSColor *)foregroundColor backgroundColor:(NSColor *)backgroundColor format:(NSString *)format, ...
{
	va_list args;
	va_start(args, format);
	NSFont *font = [NSFont userFixedPitchFontOfSize:textView.font.pointSize];
	NSDictionary *attributesDictionary = @{ NSForegroundColorAttributeName:foregroundColor, NSBackgroundColorAttributeName:backgroundColor, NSFontAttributeName:font };
	NSString *string = [[NSString alloc] initWithFormat:format arguments:args];
	NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:string attributes:attributesDictionary];
	va_end(args);
	
	[[textView textStorage] appendAttributedString:attributedString];
	[textView scrollRangeToVisible:NSMakeRange([[textView string] length], 0)];
	[attributedString release];
	[string release];
}

- (void)appendTextViewWithFormat:(NSTextView *)textView format:(NSString *)format, ...
{
	va_list args;
	va_start(args, format);
	NSFont *font = [NSFont userFixedPitchFontOfSize:textView.font.pointSize];
	NSDictionary *attributesDictionary = @{ NSForegroundColorAttributeName:[NSColor textColor], NSBackgroundColorAttributeName:[NSColor textBackgroundColor], NSFontAttributeName:font };
	NSString *string = [[NSString alloc] initWithFormat:format arguments:args];
	NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:string attributes:attributesDictionary];
	va_end(args);
	
	[[textView textStorage] appendAttributedString:attributedString];
	[textView scrollRangeToVisible:NSMakeRange([[textView string] length], 0)];
	[attributedString release];
	[string release];
}

- (void)appendTextView:(NSTextView *)textView foregroundColor:(NSColor *)foregroundColor backgroundColor:(NSColor *)backgroundColor text:(NSString *)text
{
	if (text == nil)
		return;
	
	NSFont *font = [NSFont userFixedPitchFontOfSize:textView.font.pointSize];
	NSDictionary *attributesDictionary = @{ NSForegroundColorAttributeName:foregroundColor, NSBackgroundColorAttributeName:backgroundColor, NSFontAttributeName:font };
	NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:text attributes:attributesDictionary];
	[[textView textStorage] appendAttributedString:attributedString];
	[textView scrollRangeToVisible:NSMakeRange([[textView string] length], 0)];
	[attributedString release];
}

- (void)appendTextView:(NSTextView *)textView text:(NSString *)text
{
	[self appendTextView:textView foregroundColor:[NSColor textColor] backgroundColor:[NSColor textBackgroundColor] text:text];
}

- (void)downloadSelectedKexts
{
	[_compileOutputTextView setString:@""];
	[_compileProgressIndicator setDoubleValue:0.0];
	[_compileProgressIndicator setNeedsDisplay:YES];
	
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSArray *pathArray = NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES);
	NSString *desktopPath = [pathArray objectAtIndex:0];
	pathArray = NSSearchPathForDirectoriesInDomains (NSDownloadsDirectory, NSUserDomainMask, YES);
	NSString *downloadsPath = [pathArray objectAtIndex:0];
	
	NSError *error;
	BOOL isDir;
	NSString *kextsPath = [desktopPath stringByAppendingPathComponent:@"Hackintool_Kexts"];
	
	if(![fileManager fileExistsAtPath:kextsPath isDirectory:&isDir])
		[fileManager createDirectoryAtPath:kextsPath withIntermediateDirectories:YES attributes:nil error:&error];

	NSMutableArray *kextsArray = (_settings.ShowInstalledOnly ? _installedKextsArray : _kextsArray);
	NSMutableArray *selectedArray = [self getSelectedKextsArray];
	
	void (^progressBlock)(void);
	progressBlock =
	^{
		for (int i = 0; i < kextsArray.count; i++)
		{
			NSMutableDictionary *kextDictionary = kextsArray[i];
			//NSString *name = [kextDictionary objectForKey:@"Name"];
			NSString *downloadUrl = [kextDictionary objectForKey:@"DownloadUrl"];
			NSString *fileName = [downloadUrl lastPathComponent];
			NSNumber *selectedNumber = selectedArray[i];
			bool isSelected = [selectedNumber boolValue];
			
			if (!isSelected || !downloadUrl)
				continue;
			
			NSError *error;
			NSString *downloadPath = [downloadsPath stringByAppendingPathComponent:fileName];
			NSData *downloadData = [NSData dataWithContentsOfURL:[NSURL URLWithString:downloadUrl] options:NSDataReadingUncached error:&error];
			
			[downloadData writeToFile:downloadPath atomically:YES];
			
			if (downloadData != nil)
			{
				launchCommand(@"/usr/bin/unzip", @[@"-q", @"-o", downloadPath, @"-d", kextsPath], self, @selector(compileOutputNotification:), @selector(compileErrorNotification:), @selector(compileCompleteNotification:));
			
				if ([[NSFileManager defaultManager] fileExistsAtPath:downloadPath])
					[[NSFileManager defaultManager] removeItemAtPath:downloadPath error:&error];
			}
		}
		
		NSArray *fileURLs = [NSArray arrayWithObjects:[NSURL fileURLWithPath:kextsPath], nil];
		[[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:fileURLs];
	};
	
	dispatch_queue_t queue = dispatch_get_global_queue(0, 0);
	dispatch_async(queue,progressBlock);
}

- (void)compileSelectedKexts
{
	[_compileOutputTextView setString:@""];
	[_compileProgressIndicator setDoubleValue:0.0];
	[_compileProgressIndicator setNeedsDisplay:YES];
	
	NSError *error;
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSArray *pathArray = NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES);
	NSString *desktopPath = [pathArray objectAtIndex:0];
	pathArray = NSSearchPathForDirectoriesInDomains (NSDownloadsDirectory, NSUserDomainMask, YES);
	NSString *downloadsPath = [pathArray objectAtIndex:0];
	NSString *stdoutString = nil;
	
	//NSString *xcodePath = @"/Applications/Xcode.app/Contents/Developer";
	//NSString *xcodeBetaPath = @"/Applications/Xcode-beta.app/Contents/Developer";
	NSString *nasmVersion = @"2.13.03";
	NSString *mtocDst1 = @"/usr/local/bin/mtoc";
	NSString *mtocDst2 = @"/usr/local/bin/mtoc.NEW";
	
	//launchCommand(@"/usr/bin/xcode-select", @[@"--print-path"], &stdoutString);
	launchCommand(@"/usr/bin/xcode-select", @[@"--version"], &stdoutString);
	
	//if (![stdoutString containsString:xcodePath] && ![stdoutString containsString:xcodeBetaPath])
	if (![stdoutString hasPrefix:@"xcode-select version"])
	{
		[self showAlert:@"Missing Xcode Tools!" text:@"Open Terminal and run\nxcode-select --install"];
		
		return;
	}
	
	launchCommand(@"/usr/local/bin/nasm", @[@"-v"], &stdoutString);
	
	if (![stdoutString containsString:nasmVersion])
	{
		if ([self showAlert:@"Missing or incompatible nasm!" text:@"Click OK to run installation."])
		{
			NSString *nasmName = [NSString stringWithFormat:@"nasm-%@", nasmVersion];
			NSString *nasmZipName = [NSString stringWithFormat:@"%@-macosx.zip", nasmName];
			NSString *nasmZipSource = [NSString stringWithFormat:@"http://www.nasm.us/pub/nasm/releasebuilds/%@/macosx/%@", nasmVersion, nasmZipName];
			NSString *nasmZipDest = [NSString stringWithFormat:@"%@/%@", downloadsPath, nasmZipName];
			NSString *nasmDest = [NSString stringWithFormat:@"%@/%@", downloadsPath, nasmName];
			NSString *nasmExtract1 = [NSString stringWithFormat:@"%@/nasm", nasmName];
			NSString *nasmExtract2 = [NSString stringWithFormat:@"%@/ndisasm", nasmName];
			NSString *nasmSrc1 = [NSString stringWithFormat:@"%@/nasm", nasmDest];
			NSString *nasmSrc2 = [NSString stringWithFormat:@"%@/ndisasm", nasmDest];
			NSString *nasmDst1 = @"/usr/local/bin/nasm";
			NSString *nasmDst2 = @"/usr/local/bin/ndisasm";
			NSURL *nasmZipUrl = [NSURL URLWithString:nasmZipSource];
			NSData *nasmZipUrlData = [NSData dataWithContentsOfURL:nasmZipUrl options:NSDataReadingUncached error:&error];
			
			if (nasmZipUrlData != nil)
			{
				[nasmZipUrlData writeToFile:nasmZipDest atomically:YES];
				
				launchCommand(@"/usr/bin/unzip", @[@"-q", @"-o", nasmZipDest, nasmExtract1, nasmExtract2, @"-d", downloadsPath], self, @selector(compileOutputNotification:), @selector(compileErrorNotification:), @selector(compileCompleteNotification:));
				
				if ([[NSFileManager defaultManager] fileExistsAtPath:nasmDst1])
					[[NSFileManager defaultManager] removeItemAtPath:nasmDst1 error:&error];
				
				if ([[NSFileManager defaultManager] fileExistsAtPath:nasmDst2])
					[[NSFileManager defaultManager] removeItemAtPath:nasmDst2 error:&error];
				
				[[NSFileManager defaultManager] copyItemAtPath:nasmSrc1 toPath:nasmDst1 error:&error];
				[[NSFileManager defaultManager] copyItemAtPath:nasmSrc2 toPath:nasmDst2 error:&error];
				
				[[NSFileManager defaultManager] removeItemAtPath:nasmDest error:&error];
				[[NSFileManager defaultManager] removeItemAtPath:nasmZipDest error:&error];
			}
		}
		else
			return;
	}
	
	if (![[NSFileManager defaultManager] fileExistsAtPath:mtocDst1] || ![[NSFileManager defaultManager] fileExistsAtPath:mtocDst2])
	{
		if ([self showAlert:@"Missing mtoc or mtoc.NEW!" text:@"Click OK to run installation."])
		{
			NSString *mtocZipSource = @"https://raw.githubusercontent.com/acidanthera/VirtualSMC/master/VirtualSmcPkg/External/mtoc-mac64.zip";
			NSString *mtocZipDest = [NSString stringWithFormat:@"%@/mtoc-mac64.zip", downloadsPath];
			NSURL *mtocZipUrl = [NSURL URLWithString:mtocZipSource];
			NSData *mtocZipUrlData = [NSData dataWithContentsOfURL:mtocZipUrl options:NSDataReadingUncached error:&error];
			NSString *mtocSrc = [NSString stringWithFormat:@"%@/mtoc.NEW", downloadsPath];
			
			[mtocZipUrlData writeToFile:mtocZipDest atomically:YES];
			
			if (mtocZipUrlData != nil)
			{
				launchCommand(@"/usr/bin/unzip", @[@"-q", @"-o", mtocZipDest, @"mtoc.NEW", @"-d", downloadsPath], self, @selector(compileOutputNotification:), @selector(compileErrorNotification:), @selector(compileCompleteNotification:));
				
				if ([[NSFileManager defaultManager] fileExistsAtPath:mtocDst1])
					[[NSFileManager defaultManager] removeItemAtPath:mtocDst1 error:&error];
				
				if ([[NSFileManager defaultManager] fileExistsAtPath:mtocDst2])
					[[NSFileManager defaultManager] removeItemAtPath:mtocDst2 error:&error];
				
				[[NSFileManager defaultManager] copyItemAtPath:mtocSrc toPath:mtocDst1 error:&error];
				[[NSFileManager defaultManager] copyItemAtPath:mtocSrc toPath:mtocDst2 error:&error];
				
				[[NSFileManager defaultManager] removeItemAtPath:mtocSrc error:&error];
				[[NSFileManager defaultManager] removeItemAtPath:mtocZipDest error:&error];
			}
		}
		else
			return;
	}
	
	// VirtualSMC
	// warning: include path for stdlibc++ headers not found; pass '-std=libc++' on the command line to use the libc++ standard library instead [-Wstdlibcxx-not-found]
	// Download the command line tools from https://developer.apple.com/download/more/
	// Install /Library/Developer/CommandLineTools/Packages/macOS_SDK_headers_for_macOS_10.14.pkg
	
	BOOL isDir;
	NSString *buildPath = [desktopPath stringByAppendingPathComponent:@"Hackintool_Build"];
	NSString *debugPath = [buildPath stringByAppendingPathComponent:@"Debug"];
	NSString *releasePath = [buildPath stringByAppendingPathComponent:@"Release"];
	
	if(![fileManager fileExistsAtPath:buildPath isDirectory:&isDir])
		[fileManager createDirectoryAtPath:buildPath withIntermediateDirectories:YES attributes:nil error:&error];
	
	if(![fileManager fileExistsAtPath:debugPath isDirectory:&isDir])
		[fileManager createDirectoryAtPath:debugPath withIntermediateDirectories:YES attributes:nil error:&error];
	
	if(![fileManager fileExistsAtPath:releasePath isDirectory:&isDir])
		[fileManager createDirectoryAtPath:releasePath withIntermediateDirectories:YES attributes:nil error:&error];
	
	NSMutableArray *kextsArray = (_settings.ShowInstalledOnly ? _installedKextsArray : _kextsArray);
	NSMutableArray *selectedArray = [self getSelectedKextsArray];
	int compileCount = 1;
	
	for (int i = 0; i < kextsArray.count; i++)
	{
		NSMutableDictionary *kextDictionary = kextsArray[i];
		NSString *name = [kextDictionary objectForKey:@"Name"];
		NSNumber *selectedNumber = selectedArray[i];
		bool isSelected = [selectedNumber boolValue];
		bool isLilu = [name isEqualToString:@"Lilu"];
		
		if (isLilu)
			continue;
		
		if (isSelected)
			compileCount++;
	}
	
	void (^progressBlock)(void);
	progressBlock =
	^{
		int compileIndex = 0;
		
		for (int i = 0; i < _kextsArray.count; i++)
		{
			NSError *error;
			NSMutableDictionary *kextDictionary = _kextsArray[i];
			NSString *name = [kextDictionary objectForKey:@"Name"];
			//NSString *type = [kextDictionary objectForKey:@"Type"];
			NSString *projectUrl = [kextDictionary objectForKey:@"ProjectUrl"];
			NSString *projectFileUrl = [kextDictionary objectForKey:@"ProjectFileUrl"];
			NSString *outputPath = [buildPath stringByAppendingPathComponent:name];
			NSString *projectFileName = (projectFileUrl != nil ? [[projectFileUrl lastPathComponent] stringByRemovingPercentEncoding] : [name stringByAppendingString:@".xcodeproj"]);
            NSString *updateGitSubmodules = @"cd $(OUTPUT_PATH) && $(SUBMODULE_UPDATE)";
			bool isLilu = [name isEqualToString:@"Lilu"];
			
			if (!isLilu)
				continue;
			
			if ([[NSFileManager defaultManager] fileExistsAtPath:outputPath])
				[[NSFileManager defaultManager] removeItemAtPath:outputPath error:&error];
			
			launchCommand(@"/usr/bin/git", @[@"clone", projectUrl, outputPath], self, @selector(compileOutputNotification:), @selector(compileErrorNotification:), @selector(compileCompleteNotification:));
            updateGitSubmodules = [updateGitSubmodules stringByReplacingOccurrencesOfString:@"$(OUTPUT_PATH)" withString:outputPath];
            updateGitSubmodules = [updateGitSubmodules stringByReplacingOccurrencesOfString:@"$(SUBMODULE_UPDATE)" withString:GitSubmoduleUpdate];
            launchCommand(@"/bin/bash", @[@"-c", updateGitSubmodules], self,  @selector(compileOutputNotification:), @selector(compileErrorNotification:), @selector(compileCompleteNotification:));
			launchCommand(@"/usr/bin/xcodebuild", @[@"-project", [outputPath stringByAppendingPathComponent:projectFileName], @"-configuration", @"Debug", @"clean", @"build", @"ARCHS=x86_64", [NSString stringWithFormat:@"CONFIGURATION_BUILD_DIR=%@", debugPath]], self, @selector(compileOutputNotification:), @selector(compileErrorNotification:), @selector(compileCompleteNotification:));
			launchCommand(@"/usr/bin/xcodebuild", @[@"-project", [outputPath stringByAppendingPathComponent:projectFileName], @"-configuration", @"Release", @"clean", @"build", @"ARCHS=x86_64", [NSString stringWithFormat:@"CONFIGURATION_BUILD_DIR=%@", releasePath]], self, @selector(compileOutputNotification:), @selector(compileErrorNotification:), @selector(compileCompleteNotification:));
			
			double progressPercent = (double)++compileIndex / (double)compileCount;
			
			dispatch_async(dispatch_get_main_queue(), ^{
				[_compileProgressIndicator setDoubleValue:progressPercent];
				[_compileProgressIndicator setNeedsDisplay:YES];
			});
		}
		
		for (int i = 0; i < kextsArray.count; i++)
		{
			NSError *error;
			NSMutableDictionary *kextDictionary = kextsArray[i];
			NSString *name = [kextDictionary objectForKey:@"Name"];
			NSString *scheme = [kextDictionary objectForKey:@"Scheme"];
			NSString *preBuildBash = [kextDictionary objectForKey:@"PreBuildBash"];
			NSString *type = [kextDictionary objectForKey:@"Type"];
			NSString *projectUrl = [kextDictionary objectForKey:@"ProjectUrl"];
			NSString *projectFileUrl = [kextDictionary objectForKey:@"ProjectFileUrl"];
			NSString *superseder = [kextDictionary objectForKey:@"Superseder"];
			NSString *outputPath = [buildPath stringByAppendingPathComponent:name];
			NSString *outputLiluKextPath = [outputPath stringByAppendingPathComponent:@"Lilu.kext"];
			NSString *liluKextPath = [debugPath stringByAppendingPathComponent:@"Lilu.kext"];
			NSString *projectFileName = (projectFileUrl != nil ? [[projectFileUrl lastPathComponent] stringByRemovingPercentEncoding] : [name stringByAppendingString:@".xcodeproj"]);
            NSString *updateGitSubmodules = @"cd $(OUTPUT_PATH) && $(SUBMODULE_UPDATE)";
			NSNumber *selectedNumber = selectedArray[i];
			bool isSelected = [selectedNumber boolValue];
			bool isLilu = [name isEqualToString:@"Lilu"];
			bool isGithub = [projectUrl containsString:@"github.com"];
			bool isSuperseded = (superseder != nil && ![superseder isEqualToString:@""]);
			
			if (isLilu || !isSelected)
				continue;
			
			if (!isGithub)
				continue;
			
			if (isSuperseded)
				continue;
			
			if ([[NSFileManager defaultManager] fileExistsAtPath:outputPath])
				[[NSFileManager defaultManager] removeItemAtPath:outputPath error:&error];
			
			launchCommand(@"/usr/bin/git", @[@"clone", projectUrl, outputPath], self, @selector(compileOutputNotification:), @selector(compileErrorNotification:), @selector(compileCompleteNotification:));
            updateGitSubmodules = [updateGitSubmodules stringByReplacingOccurrencesOfString:@"$(OUTPUT_PATH)" withString:outputPath];
            updateGitSubmodules = [updateGitSubmodules stringByReplacingOccurrencesOfString:@"$(SUBMODULE_UPDATE)" withString:GitSubmoduleUpdate];
            launchCommand(@"/bin/bash", @[@"-c", updateGitSubmodules], self,  @selector(compileOutputNotification:), @selector(compileErrorNotification:), @selector(compileCompleteNotification:));

			if ([type isEqualToString:@"Lilu"])
			{
				if ([[NSFileManager defaultManager] fileExistsAtPath:outputLiluKextPath])
					[[NSFileManager defaultManager] removeItemAtPath:outputLiluKextPath error:&error];
				
				[[NSFileManager defaultManager] copyItemAtPath:liluKextPath toPath:outputLiluKextPath error:&error];
			}
			
			if (preBuildBash != nil)
			{
				preBuildBash = [preBuildBash stringByReplacingOccurrencesOfString:@"$(OUTPUT_PATH)" withString:outputPath];
				
				launchCommand(@"/bin/bash", @[@"-c", preBuildBash], self, @selector(compileOutputNotification:), @selector(compileErrorNotification:), @selector(compileCompleteNotification:));
			}
			
			NSMutableArray *debugArguments = [NSMutableArray arrayWithObjects:@"-project", [outputPath stringByAppendingPathComponent:projectFileName], @"-configuration", @"Debug", @"clean", @"build", @"ARCHS=x86_64", [NSString stringWithFormat:@"CONFIGURATION_BUILD_DIR=%@", debugPath], nil];
			NSMutableArray *releaseArguments = [NSMutableArray arrayWithObjects:@"-project", [outputPath stringByAppendingPathComponent:projectFileName], @"-configuration", @"Release", @"clean", @"build", @"ARCHS=x86_64", [NSString stringWithFormat:@"CONFIGURATION_BUILD_DIR=%@", releasePath], nil];
			
			if (scheme != nil)
			{
				[debugArguments addObjectsFromArray:@[@"-scheme", scheme]];
				[releaseArguments addObjectsFromArray:@[@"-scheme", scheme]];
			}
			
			launchCommand(@"/usr/bin/xcodebuild", debugArguments, self, @selector(compileOutputNotification:), @selector(compileErrorNotification:), @selector(compileCompleteNotification:));
			launchCommand(@"/usr/bin/xcodebuild", releaseArguments, self, @selector(compileOutputNotification:), @selector(compileErrorNotification:), @selector(compileCompleteNotification:));
			
			double progressPercent = (double)++compileIndex / (double)compileCount;
			
			dispatch_async(dispatch_get_main_queue(), ^{
				[_compileProgressIndicator setDoubleValue:progressPercent];
				[_compileProgressIndicator setNeedsDisplay:YES];
			});
		}
		
		NSArray *fileURLs = [NSArray arrayWithObjects:[NSURL fileURLWithPath:buildPath], nil];
		[[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:fileURLs];
	};
	
	dispatch_queue_t queue = dispatch_get_global_queue(0, 0);
	dispatch_async(queue,progressBlock);
}

- (bool)tryGetProjectFileVersion:(NSString *)projectFileName projectVersion:(NSString **)projectVersion
{
	if (![[NSFileManager defaultManager] fileExistsAtPath:projectFileName])
		return false;
	
	NSDictionary *projFileDictionay = [NSDictionary dictionaryWithContentsOfFile:projectFileName];
	
	if (projFileDictionay == nil)
		return false;
	
	NSDictionary *objectsDictionary = [projFileDictionay objectForKey:@"objects"];
	
	if (objectsDictionary == nil)
		return false;
	
	for (NSString *key in objectsDictionary.allKeys)
	{
		NSDictionary *objectDictionary = [objectsDictionary objectForKey:key];
		
		if (objectDictionary == nil)
			continue;
		
		NSDictionary *buildSettingsDictionary = [objectDictionary objectForKey:@"buildSettings"];
		
		if (buildSettingsDictionary == nil)
			continue;
		
		*projectVersion = [buildSettingsDictionary objectForKey:@"CURRENT_PROJECT_VERSION"];
		
		if (*projectVersion == nil || [*projectVersion isEqualToString:@"$(MODULE_VERSION)"] || [*projectVersion isEqualToString:@"$MODULE_VERSION"])
		{
			*projectVersion = [buildSettingsDictionary objectForKey:@"MODULE_VERSION"];
			
			if (*projectVersion == nil || [*projectVersion isEqualToString:@"$(CURRENT_PROJECT_VERSION)"] || [*projectVersion isEqualToString:@"$CURRENT_PROJECT_VERSION"])
				continue;
		}
		
		return true;
	}
	
	return false;
}

- (void)getKextCurrentVersions
{
	void (^progressBlock)(void);
	progressBlock =
	^{
		dispatch_async(dispatch_get_main_queue(), ^{
			[_showInstalledOnlyButton setEnabled:NO];
		});
		
		NSError *error;
		NSMutableArray *kextsArray = (_settings.ShowInstalledOnly ? _installedKextsArray : _kextsArray);
		NSString *tempPath = getTempPath();
		
		for (int i = 0; i < kextsArray.count; i++)
		{
			NSMutableDictionary *kextDictionary = kextsArray[i];
			NSString *name = [kextDictionary objectForKey:@"Name"];
			NSString *projectUrl = [kextDictionary objectForKey:@"ProjectUrl"];
			NSString *projectFileUrl = [kextDictionary objectForKey:@"ProjectFileUrl"];
			bool isGithub = [projectUrl containsString:@"github.com"];
			bool isSourceForge = [projectUrl containsString:@"sourceforge.net"];
			NSString *projectName = [projectUrl lastPathComponent];
			NSString *username = [[projectUrl stringByDeletingLastPathComponent] lastPathComponent];
			NSURL *projFileUrl = [[NSURL URLWithString:projectFileUrl] URLByAppendingPathComponent:@"project.pbxproj"];
			NSURL *gitProjFile1Url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/raw/master/%@.xcodeproj/project.pbxproj", projectUrl, name]];
			NSURL *gitProjFile2Url = [NSURL URLWithString:[NSString stringWithFormat:@"https://raw.githubusercontent.com/%@/%@/master/%@.xcodeproj/project.pbxproj", username, projectName, name]];
			NSURL *gitProjFile3Url = [NSURL URLWithString:[NSString stringWithFormat:@"https://raw.githubusercontent.com/%@/%@/master/%@/%@.xcodeproj/project.pbxproj", username, projectName, name, name]];
			NSURL *sfProjFile1Url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/code/HEAD/tree/%@/%@.xcodeproj/project.pbxproj?format=raw", projectUrl, name, name]];
			NSString *projFileDest = [NSString stringWithFormat:@"%@/project.pbxproj", tempPath];
			NSData *projFileData = nil;
			
			[self getGithubDownloadUrl:&kextDictionary];
			
			if ([[NSFileManager defaultManager] fileExistsAtPath:projFileDest])
				[[NSFileManager defaultManager] removeItemAtPath:projFileDest error:&error];
			
			if (projFileUrl != nil)
			{
				projFileData = [NSData dataWithContentsOfURL:projFileUrl options:NSDataReadingUncached error:&error];
			}
			else
			{
				if (isGithub)
				{
					projFileData = [NSData dataWithContentsOfURL:gitProjFile1Url options:NSDataReadingUncached error:&error];
					
					if (projFileData == nil)
						projFileData = [NSData dataWithContentsOfURL:gitProjFile2Url options:NSDataReadingUncached error:&error];
					
					if (projFileData == nil)
						projFileData = [NSData dataWithContentsOfURL:gitProjFile3Url options:NSDataReadingUncached error:&error];
				}
				else if (isSourceForge)
				{
					projFileData = [NSData dataWithContentsOfURL:sfProjFile1Url options:NSDataReadingUncached error:&error];
				}
			}
			
			if (projFileData == nil)
				continue;
			
			[projFileData writeToFile:projFileDest atomically:YES];
			
			NSString *projectVersion;
			
			if ([self tryGetProjectFileVersion:projFileDest projectVersion:&projectVersion])
				[kextDictionary setObject:projectVersion forKey:@"CurrentVersion"];
			
			double progressPercent = (double)(i + 1) / (double)kextsArray.count;
			
			dispatch_async(dispatch_get_main_queue(), ^{
				[_compileProgressIndicator setDoubleValue:progressPercent];
				[_compileProgressIndicator setNeedsDisplay:YES];
				[_kextsTableView scrollRowToVisible:i];
				[_kextsTableView reloadData];
			});
		}
		
		NSString *stdoutString = nil;
		
		launchCommand(@"/bin/rm", @[@"-Rf", tempPath], &stdoutString);
		
		dispatch_async(dispatch_get_main_queue(), ^{
			[_showInstalledOnlyButton setEnabled:YES];
		});
	};
	
	dispatch_queue_t queue = dispatch_get_global_queue(0, 0);
	dispatch_async(queue,progressBlock);
}

- (void)initSystemConfigs
{
	NSLog(@"Initializing System Configs");
	
	[_systemConfigsMenu removeAllItems];
	
	_systemConfigsArray = [[NSMutableArray array] retain];
	
	NSBundle *mainBundle = [NSBundle mainBundle];
	NSString *resourcePath = [mainBundle resourcePath];
	NSString *dataPath = [resourcePath stringByAppendingPathComponent:@"Intel/SystemConfigs"];
	NSString *filePath = nil;
	uint32_t index = 0;
	
	NSMutableArray *fileArray = [NSMutableArray array];
	NSFileManager *fileManager = [[NSFileManager alloc] init];
	NSDirectoryEnumerator *directoryEnumerator = [fileManager enumeratorAtURL:[NSURL fileURLWithPath:dataPath]
												   includingPropertiesForKeys:@[NSURLNameKey, NSURLIsDirectoryKey]
																	  options:NSDirectoryEnumerationSkipsHiddenFiles
																 errorHandler:nil];
	
	if (directoryEnumerator != nil)
	{
		for (NSURL *url in directoryEnumerator)
			 [fileArray addObject:url];
		
		NSArray *sortedFileArray = [fileArray sortedArrayUsingComparator:
		 ^(NSURL *file1, NSURL *file2)
		 {
			 return [[file1 path] compare:[file2 path]];
		 }];

		NSMenuItem *categoryMenuItem = nil;
		NSMenu *categoryMenu = nil;
		
		for (NSURL *url in sortedFileArray)
		{
			NSNumber *isDirectory;
			[url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:NULL];
			
			if ([isDirectory boolValue])
			{
				NSString *categoryName = [url lastPathComponent];
				categoryMenuItem = [[[NSMenuItem alloc] initWithTitle:categoryName action:nil keyEquivalent:@""] autorelease];
				categoryMenu = [[[NSMenu alloc] initWithTitle:categoryName] autorelease];
				[_systemConfigsMenu addItem:categoryMenuItem];
				[_systemConfigsMenu setSubmenu:categoryMenu forItem:categoryMenuItem];
			}
			else
			{
				NSString *name = [[url lastPathComponent] stringByDeletingPathExtension];
				NSString *category = [[url URLByDeletingLastPathComponent] lastPathComponent];
				NSArray *nameArray = [name componentsSeparatedByString:@", "];
				nameArray = [nameArray sortedArrayUsingSelector:@selector(compare:)];
				
				for (NSString *subName in nameArray)
				{
					if (!(filePath = [mainBundle pathForResource:name ofType:@"plist" inDirectory:[@"Intel/SystemConfigs" stringByAppendingPathComponent:category]]))
						continue;
					
					NSMutableDictionary *configDictionary = [NSMutableDictionary dictionaryWithContentsOfFile:filePath];
					NSMutableDictionary *propertyDictionary = [Clover getDevicesPropertiesDictionaryWith:configDictionary];
					[_systemConfigsArray addObject:propertyDictionary.allValues[0]];
					
					NSMenuItem *menuItem = [[[NSMenuItem alloc] initWithTitle:subName action:@selector(systemConfigsClicked:) keyEquivalent:@""] autorelease];
					[menuItem setTag:index];
					[categoryMenu addItem:menuItem];
					
					index++;
				}
			}
		}
	}
	
	[fileManager release];
}

- (void)refreshDisks
{
	[_efiPartitionsTableView reloadData];
	[_partitionSchemeTableView reloadData];
	
	[self updateStorageDevices];
}

- (void)addUSBDevice:(uint32_t)controllerID controllerLocationID:(uint32_t)controllerLocationID locationID:(uint32_t)locationID port:(uint32_t)port deviceName:(NSString *)deviceName devSpeed:(uint8_t)devSpeed
{
	uint32_t foundIndex = -1;
	
	for (int i = 0; i < [_usbPortsArray count]; i++)
	{
		NSMutableDictionary *usbEntryDictionary = _usbPortsArray[i];
		uint32_t usbEntryUsbControllerID = propertyToUInt32([usbEntryDictionary objectForKey:@"UsbControllerID"]);
		uint32_t usbEntryUsbControllerLocationID = propertyToUInt32([usbEntryDictionary objectForKey:@"UsbControllerLocationID"]);
		uint32_t usbEntryLocationID = propertyToUInt32([usbEntryDictionary objectForKey:@"locationID"]);
		uint32_t usbEntryPort = propertyToUInt32([usbEntryDictionary objectForKey:@"port"]);
		
		if ((usbEntryUsbControllerID != controllerID) || (usbEntryUsbControllerLocationID != controllerLocationID) || (usbEntryLocationID != locationID) || (usbEntryPort != port))
			continue;
		
		[usbEntryDictionary setObject:deviceName forKey:@"Device"];
		[usbEntryDictionary setObject:@(YES) forKey:@"IsActive"];
		[usbEntryDictionary setObject:@(devSpeed) forKey:@"DevSpeed"];
		
		foundIndex = i;
	}
	
	[_usbPortsTableView reloadData];
	[_usbPortsTableView scrollRowToVisible:foundIndex];
}

- (void)removeUSBDevice:(uint32_t)controllerID controllerLocationID:(uint32_t)controllerLocationID locationID:(uint32_t)locationID port:(uint32_t)port
{
	uint32_t foundIndex = -1;
	
	for (int i = 0; i < [_usbPortsArray count]; i++)
	{
		NSMutableDictionary *usbEntryDictionary = _usbPortsArray[i];
		uint32_t usbEntryUsbControllerID = propertyToUInt32([usbEntryDictionary objectForKey:@"UsbControllerID"]);
		uint32_t usbEntryUsbControllerLocationID = propertyToUInt32([usbEntryDictionary objectForKey:@"UsbControllerLocationID"]);
		uint32_t usbEntryLocationID = propertyToUInt32([usbEntryDictionary objectForKey:@"locationID"]);
		uint32_t usbEntryPort = propertyToUInt32([usbEntryDictionary objectForKey:@"port"]);
		
		if ((usbEntryUsbControllerID != controllerID) || (usbEntryUsbControllerLocationID != controllerLocationID) || (usbEntryLocationID != locationID) || (usbEntryPort != port))
			continue;
		
		[usbEntryDictionary setObject:@"" forKey:@"Device"];
		
		foundIndex = i;
	}

	[_usbPortsTableView reloadData];
	[_usbPortsTableView scrollRowToVisible:foundIndex];
}

- (void)copyUSBPorts:(NSMutableDictionary *)fromUSBPortsDictionary toUSBPorts:(NSMutableDictionary *)toUSBPortsDictionary
{
	NSArray *fieldArray = @[@"name", @"locationID", @"port", @"portType", @"UsbConnector", @"UsbController", @"UsbControllerID", @"UsbControllerLocationID", @"UsbControllerIOClass", @"HubName", @"HubLocation", @"IsActive", @"Device", @"Comment"];
	
	for (NSString *key in fromUSBPortsDictionary.allKeys)
	{
		if ([fieldArray indexOfObject:key] == NSNotFound)
			continue;
		
		[toUSBPortsDictionary setObject:[fromUSBPortsDictionary objectForKey:key] forKey:key];
	}
	
	[toUSBPortsDictionary setObject:@"" forKey:@"Device"];
}

- (bool)isInternalHubPort:(NSString *)hubName
{
	return ([hubName isEqualToString:@"AppleUSB20InternalHub"] || [hubName isEqualToString:@"AppleUSB20InternalIntelHub"]);
}

- (void)refreshUSBPorts
{
	// https://www.tonymacx86.com/threads/guide-creating-a-custom-ssdt-for-usbinjectall-kext.211311/
	// https://www.tonymacx86.com/threads/guide-10-11-usb-changes-and-solutions.173616/
	// https://raw.githubusercontent.com/RehabMan/OS-X-USB-Inject-All/master/SSDT-UIAC-ALL.dsl
	// https://www.insanelymac.com/forum/topic/306777-guide-usb-fix-el-capitan-1011/
	
	// AppleUSBEHCIPCI (USB 2.0)
	// AppleUSBXHCIPCI (USB 3.0)

	// Renames
	// EHC1->EH01
	// EHC2->EH02
	// XHC (leave alone, it doesn't match against Apple's XHC1)
	// If you have...
	// XHC1->XHC (or XH01)
	
	// HPxx - hub ports
	// PRxx - EHCI ports
	// HSxx - HS on xHCI
	// SSxx - SS on xHCI
	
	// Hubs are typically connected to EH01.PR11, EH02.PR21
	
	// PRxx on EH0x are of type AppleUSBEHCIPort
	// HPxx on the hubs are of type AppleUSB20InternalHubPort
	// But that's only if the PRxx it is attached to is marked internal (UsbConnector=255)
	// Non internal hub ports would be AppleUSB20HubPort
	
	// USB2 = 0x00
	// USB3 = 0x03
	// TypeC+Sw = 0x09
	// TypeC = 0x0A
	// Internal = 0xFF
	
	// portType=0 seems to indicate normal external USB2 port (as seen in MacBookPro8,1)
	// portType=2 seems to indicate "internal device" (as seen in MacBookPro8,1)
	// portType=4 is used by MacBookPro8,3 (reason/purpose unknown)
	
	// FakePCIID_XHCIMux.kext This kext will attach to 8086:1e31, 8086:9c31, 8086:9cb1, 8086:9c31, and 8086:8cb1
	// This injector is a bit of an extension to normal FakePCIID duties. It doesn't actually fake any PCI IDs.
	// Rather, it forces certain values to XUSB2PR (PCI config offset 0xD0) on the Intel XHCI USB3 controller.
	// The effect is to route any USB2 devices attached to the USB2 pins on the XHC ports to EHC1. In other words,
	// handle USB2 devices with the USB2 drivers instead of the USB3 drivers (AppleUSBEHCI vs. AppleUSBXHCI).

	NSMutableArray *propertyDictionaryArray = nil;

	getIORegUSBPortsPropertyDictionaryArray(&propertyDictionaryArray);
	
	//[_usbPortsArray removeAllObjects];
	
	for (NSMutableDictionary *propertyDictionary in propertyDictionaryArray)
	{
		NSString *name = [propertyDictionary objectForKey:@"name"];
		uint32_t locationID = propertyToUInt32([propertyDictionary objectForKey:@"locationID"]);
		uint32_t port = propertyToUInt32([propertyDictionary objectForKey:@"port"]);
		NSNumber *portType = [propertyDictionary objectForKey:@"portType"];
		NSNumber *usbConnector = [propertyDictionary objectForKey:@"UsbConnector"];
		NSString *usbController = [propertyDictionary objectForKey:@"UsbController"];
		uint32_t usbControllerID = propertyToUInt32([propertyDictionary objectForKey:@"UsbControllerID"]);
		uint32_t usbControllerLocationID = propertyToUInt32([propertyDictionary objectForKey:@"UsbControllerLocationID"]);
		NSString *hubName = [propertyDictionary objectForKey:@"HubName"];
		uint32_t hubLocationID = propertyToUInt32([propertyDictionary objectForKey:@"HubLocation"]);
		//NSNumber *hubIsInternal = [propertyDictionary objectForKey:@"HubIsInternal"];
		uint32_t index = 0;
		
		if (usbConnector == nil && portType == nil)
		{
			//[self createUSBPortConnector:propertyDictionary];

			continue;
		}
		
		if (hubName != nil)
		{
			//if (![hubIsInternal boolValue])
			//	 continue;
			
			// Only include hub ports for EH* controllers
			//if (![usbController hasPrefix:@"EH"])
			//	continue;
			
			if (![self isInternalHubPort:hubName])
				continue;
		}
		
		// See if we have the port already via controller / port
		if ([self containsUSBPort:usbController controllerLocationID:usbControllerLocationID hub:hubName port:port index:&index])
		{
			NSMutableDictionary *usbEntryDictionary = _usbPortsArray[index];
			
			NSString *oldName = [usbEntryDictionary objectForKey:@"name"];
			
			if (oldName != nil)
				[propertyDictionary setObject:oldName forKey:@"name"];
			
			[self copyUSBPorts:propertyDictionary toUSBPorts:usbEntryDictionary];
			
			continue;
		}
		
		NSMutableDictionary *usbPortsDictionary = [NSMutableDictionary dictionary];
		
		[self copyUSBPorts:propertyDictionary toUSBPorts:usbPortsDictionary];
		
		if (name == nil)
		{
			name = [self generateUSBPortName:usbControllerID hubLocationID:hubLocationID locationID:locationID portNumber:port];
			
			[usbPortsDictionary setObject:name forKey:@"name"];
		}
		
		[usbPortsDictionary setObject:@(NO) forKey:@"IsActive"];
		
		//NSLog(@"Port Name: %@ LocationID: 0x%08x UsbController: %@ (0x%08x) Hub: %@ (0x%08x)", ![name isEqualToString:newName] ? [NSString stringWithFormat:@"%@->%@", name, newName] : name, locationID, usbController, usbControllerID, hubName, hubLocationID);
		
		[_usbPortsArray addObject:usbPortsDictionary];
	}
	
	[_usbPortsArray sortUsingFunction:usbPortSort context:nil];
	[_usbPortsTableView reloadData];
	
	usbRegisterEvents(self);
}

- (void)injectUSBPorts:(NSDictionary *)portsDictionary usbController:(NSString *)usbController usbControllerID:(uint32_t)usbControllerID usbControllerLocationID:(uint32_t)usbControllerLocationID hubName:(NSString *)hubName hubLocationID:(uint32_t)hubLocationID
{
	for (NSString *usbPortEntry in portsDictionary.allKeys)
	{
		NSMutableDictionary *usbPortDictionary = [[[portsDictionary objectForKey:usbPortEntry] mutableCopy] autorelease];
		
		uint32_t port = propertyToUInt32([usbPortDictionary objectForKey:@"port"]);
		
		[usbPortDictionary setValue:usbPortEntry forKey:@"name"];
		[usbPortDictionary setValue:@((usbControllerLocationID << 24) | (port << 16)) forKey:@"locationID"];
		[usbPortDictionary setValue:usbController forKey:@"UsbController"];
		[usbPortDictionary setValue:@(usbControllerID) forKey:@"UsbControllerID"];
		[usbPortDictionary setValue:@(usbControllerLocationID) forKey:@"UsbControllerLocationID"];
		
		if (hubName != nil)
		{
			[usbPortDictionary setValue:@(hubLocationID | (port << 16)) forKey:@"locationID"];
			[usbPortDictionary setValue:hubName forKey:@"HubName"];
			[usbPortDictionary setValue:@(hubLocationID) forKey:@"HubLocation"];
		}
		
		[_usbPortsArray addObject:usbPortDictionary];
	}
}

- (void)injectUSBPorts
{
	// https://github.com/Sniki/OS-X-USB-Inject-All/blob/master/USBInjectAll/USBInjectAll-Info.plist
	//
	// PR11 = 0x1D100000 (HUB1)
	// PR21 = 0x1A100000 (HUB2)
	// PR11 = 0x1D1x0000 (HPxx)
	// PR21 = 0x1A1x0000 (HPxx)
	// XHCx - 0x14xx0000 (HSxx, SSxx)
	// EHx1 - 0x1Dxx0000 (PRxx)
	// EHx2 - 0x1Axx0000 (PRxx)
	//
	// 1. Enumerate IOPCIDevice's
	// - Read device-id, vendor-id
	//
	// 2. Intel only
	// - vendor-id != 0x8086 continue
	//
	// 3. device-id == 0x1c26
	// * EHx1:
	// - name: PR11, PR12, PR13, PR14, PR15, PR16, PR17, PR18
	// - port (Data): 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8
	// - UsbConnector: 255 (PR11), 0 (PR12 - PR18)
	// - locationID: 0x1Dxx0000
	// - IOProviderClass: AppleUSBEHCIPCI
	//
	// * HUB1:
	// - name: HP11, HP12, HP13, HP14, HP15, HP16, HP17, HP18
	// - port (Data): 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8
	// - portType: 0
	// - locationID: 0x1D1x0000
	// - IOProviderClass: AppleUSB20InternalHub
	//
	// 4. device-id == 0x1c2d
	// * EHx2:
	// - name: PR21, PR22, PR23, PR24, PR25, PR26
	// - port (Data): 0x1, 0x2, 0x3, 0x4, 0x5, 0x6
	// - UsbConnector: 255 (PR21), 0 (PR22 - PR26)
	// - locationID: 0x1Axx0000
	// - IOProviderClass: AppleUSBEHCIPCI
	//
	// * HUB2:
	// - name: HP21, HP22, HP23, HP24, HP25, HP26, HP27, HP28
	// - port (Data): 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8
	// - portType: 0
	// - locationID: 0x1A1x0000
	// - IOProviderClass: AppleUSB20InternalHub
	//
	// 5. device-id == 0x1e31, 0x8xxx, 0x9cb1, 0x9dxx, 0x9xxx, 0xa12f, 0xa2af, 0xa36d
	// * XHCx:
	// - 8086_1e31: HS01, HS02, HS03, HS04, SS01, SS02, SS03, SS04
	// - 8086_8xxx: HS01, HS02, HS03, HS04, HS05, HS06, HS07, HS08, HS09, HS10, HS11, HS12, HS13, HS14, SS01, SS02, SS03, SS04, SS05, SS06
	// - 8086_9cb1: HS01, HS02, HS03, HS04, HS05, HS06, HS07, HS08, HS09, HS10, HS11, SS01, SS02, SS03, SS04
	// - 8086_9dxx: HS01, HS02, HS03, HS04, HS05, HS06, HS07, HS08, HS09, HS10, SS01, SS02, SS03, SS04, SS05, SS06, USR1, USR2
	// - 8086_9xxx: HS01, HS02, HS03, HS04, HS05, HS06, HS07, HS08, HS09, SS01, SS02, SS03, SS04
	// - 8086_a12f: HS01, HS02, HS03, HS04, HS05, HS06, HS07, HS08, HS09, HS10, HS11, HS12, HS13, HS14, SS01, SS02, SS03, SS04, SS05, SS06, SS07, SS08, SS09, SS10, USR1, USR2
	// - 8086_a2af: HS01, HS02, HS03, HS04, HS05, HS06, HS07, HS08, HS09, HS10, HS11, HS12, HS13, HS14, SS01, SS02, SS03, SS04, SS05, SS06, SS07, SS08, SS09, SS10, USR1, USR2
	// - 8086_a36d: HS01, HS02, HS03, HS04, HS05, HS06, HS07, HS08, HS09, HS10, HS11, HS12, HS13, HS14, SS01, SS02, SS03, SS04, SS05, SS06, SS07, SS08, SS09, SS10, USR1, USR2
	// - port (Data): 0x1, 0x2, ... n
	// - UsbConnector: 3
	// - locationID: 0x14xx0000
	// - IOProviderClass: AppleUSBXHCIPCI
	
	for (NSMutableDictionary *usbControllersDictionary in _usbControllersArray)
	{
		//NSString *usbControllerType = [usbControllersDictionary objectForKey:@"Type"];
		uint32_t usbControllerID = propertyToUInt32([usbControllersDictionary objectForKey:@"DeviceID"]);
		uint32_t usbControllerLocationID = propertyToUInt32([usbControllersDictionary objectForKey:@"ID"]);
		uint32_t vendorID = (usbControllerID & 0xFFFF);
		uint32_t deviceID = (usbControllerID >> 16);
		
		for (NSString *usbConfigEntry in _usbConfigurationDictionary.allKeys)
		{
			NSMutableDictionary *usbConfigurationDictionary = [_usbConfigurationDictionary objectForKey:usbConfigEntry];
			NSDictionary *portsDictionary = [usbConfigurationDictionary objectForKey:@"ports"];
			
			if ([[NSString stringWithFormat:@"%04x_%04x", vendorID, deviceID] isEqualToString:usbConfigEntry] ||
				[[NSString stringWithFormat:@"%04x_%02xxx", vendorID, (deviceID & 0xFF00) >> 8] isEqualToString:usbConfigEntry] ||
				[[NSString stringWithFormat:@"%04x_%01xxxx", vendorID, (deviceID & 0xF000) >> 12] isEqualToString:usbConfigEntry])
			{
				[self injectUSBPorts:portsDictionary usbController:@"XHC" usbControllerID:usbControllerID usbControllerLocationID:usbControllerLocationID hubName:nil hubLocationID:0];
			}
			else if (isControllerLocationEH1(usbControllerLocationID) && [usbConfigEntry isEqualToString:@"EH01"])
			{
				NSMutableDictionary *hub1ConfigurationDictionary = [_usbConfigurationDictionary objectForKey:@"HUB1"];
				NSDictionary *hub1PortsDictionary = [hub1ConfigurationDictionary objectForKey:@"ports"];
				
				[self injectUSBPorts:portsDictionary usbController:@"EH01" usbControllerID:usbControllerID usbControllerLocationID:usbControllerLocationID hubName:nil hubLocationID:0];
				[self injectUSBPorts:hub1PortsDictionary usbController:@"EH01" usbControllerID:usbControllerID usbControllerLocationID:usbControllerLocationID hubName:@"AppleUSB20InternalHub" hubLocationID:0x1D100000];
			}
			else if (isControllerLocationEH2(usbControllerLocationID) && [usbConfigEntry isEqualToString:@"EH02"])
			{
				NSMutableDictionary *hub2ConfigurationDictionary = [_usbConfigurationDictionary objectForKey:@"HUB2"];
				NSDictionary *hub2PortsDictionary = [hub2ConfigurationDictionary objectForKey:@"ports"];
				
				[self injectUSBPorts:portsDictionary usbController:@"EH02" usbControllerID:usbControllerID usbControllerLocationID:usbControllerLocationID hubName:nil hubLocationID:0];
				[self injectUSBPorts:hub2PortsDictionary usbController:@"EH02" usbControllerID:usbControllerID usbControllerLocationID:usbControllerLocationID hubName:@"AppleUSB20InternalHub" hubLocationID:0x1A100000];
			}
		}
	}
	
	[_usbPortsArray sortUsingFunction:usbPortSort context:nil];
	[_usbPortsTableView reloadData];
}

- (void)refreshUSBControllers
{
	NSMutableArray *propertyDictionaryArray = nil;

	getIORegUSBControllersPropertyDictionaryArray(&propertyDictionaryArray);
	
	[_usbControllersArray removeAllObjects];
	
	for (NSMutableDictionary *propertyDictionary in propertyDictionaryArray)
	{
		NSString *name = [propertyDictionary objectForKey:@"Name"];
		uint32_t controllerID = propertyToUInt32([propertyDictionary objectForKey:@"DeviceID"]);
		NSString *locationID = [propertyDictionary objectForKey:@"ID"];
		
		if (name == nil || controllerID == 0)
			continue;
		
		NSNumber *vendorID = [NSNumber numberWithUnsignedInt:(controllerID & 0xFFFF)];
		NSNumber *deviceID = [NSNumber numberWithUnsignedInt:(controllerID >> 16)];
		NSString *vendorName = nil, *deviceName = nil;
		
		[self getPCIDeviceInfo:vendorID deviceID:deviceID vendorName:&vendorName deviceName:&deviceName];
		
		NSMutableDictionary *usbControllersDictionary = [NSMutableDictionary dictionary];

		[usbControllersDictionary setObject:name forKey:@"Type"];
		[usbControllersDictionary setObject:deviceName forKey:@"Name"];
		[usbControllersDictionary setObject:[self getUSBSeries:controllerID] forKey:@"Series"];
		[usbControllersDictionary setObject:@(controllerID) forKey:@"DeviceID"];
		[usbControllersDictionary setObject:locationID forKey:@"ID"];
		
		[_usbControllersArray addObject:usbControllersDictionary];
	}
	
	[_usbControllersArray sortUsingFunction:usbControllerSort context:nil];
	[_usbControllersTableView reloadData];
}

- (bool)getUSBPortNameWithControllerID:(uint32_t)usbControllerID portNumber:(uint32_t)portNumber portName:(NSString **)portName
{
	if (usbControllerID == 0)
		return false;

	uint32_t vendorID = (usbControllerID & 0xFFFF);
	uint32_t deviceID = (usbControllerID >> 16);
	
	if (vendorID != 0x8086)
		return false;
	
	NSString *controllerName = [NSString stringWithFormat:@"%04x_%04x", vendorID, deviceID];
	
	if ([self getUSBPortNameWithControllerName:controllerName portNumber:portNumber portName:portName])
		return true;
	
	controllerName = [controllerName stringByReplacingCharactersInRange:NSMakeRange(7, 2) withString:@"xx"];
	
	if ([self getUSBPortNameWithControllerName:controllerName portNumber:portNumber portName:portName])
		return true;
	
	controllerName = [controllerName stringByReplacingCharactersInRange:NSMakeRange(6, 3) withString:@"xxx"];
	
	return [self getUSBPortNameWithControllerName:controllerName portNumber:portNumber portName:portName];
}

- (bool)getUSBPortNameWithControllerName:(NSString *)controllerName portNumber:(uint32_t)portNumber portName:(NSString **)portName
{
	NSDictionary *controllerDictionary = [_usbConfigurationDictionary objectForKey:controllerName];
	
	if (controllerDictionary == nil)
		return false;
	
	NSDictionary *portsDictionary = [controllerDictionary objectForKey:@"ports"];
	
	for (NSString *key in portsDictionary.allKeys)
	{
		NSDictionary *propertyDictionary = [portsDictionary objectForKey:key];
		uint32_t port = propertyToUInt32([propertyDictionary objectForKey:@"port"]);
		
		if (port != portNumber)
			continue;
		
		*portName = key;

		return true;
	}
	
	return false;
}

- (void)loadUSBPorts
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSArray *usbPorts = [defaults objectForKey:@"USBPorts"];
	
	for (NSDictionary *usbDictionary in usbPorts)
	{
		NSMutableDictionary *usbEntryDictionary = [[usbDictionary mutableCopy] autorelease];
		NSString *usbController = [usbEntryDictionary objectForKey:@"UsbController"];
		uint32_t usbControllerLocationID = propertyToUInt32([usbEntryDictionary objectForKey:@"UsbControllerLocationID"]);
		NSString *hubName = [usbEntryDictionary objectForKey:@"HubName"];
		uint32_t port = propertyToUInt32([usbEntryDictionary objectForKey:@"port"]);
		uint32_t index = 0;
		
		if ([self containsUSBPort:usbController controllerLocationID:usbControllerLocationID hub:hubName port:port index:&index])
			continue;
		
		NSMutableDictionary *usbPortsDictionary = [NSMutableDictionary dictionary];
		
		[self copyUSBPorts:usbEntryDictionary toUSBPorts:usbPortsDictionary];
		
		[_usbPortsArray addObject:usbPortsDictionary];
	}
}

- (void)saveUSBPorts
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	
	[defaults setObject:_usbPortsArray forKey:@"USBPorts"];
	
	[defaults synchronize];
}

- (bool)containsUSBPort:(NSString *)controller controllerLocationID:(uint32_t)controllerLocationID hub:(NSString *)hub port:(uint32_t)port index:(uint32_t *)index
{
	for (int i = 0; i < [_usbPortsArray count]; i++)
	{
		NSMutableDictionary *usbPortsDictionary = _usbPortsArray[i];
		NSString *usbController = [usbPortsDictionary objectForKey:@"UsbController"];
		uint32_t usbControllerLocationID = propertyToUInt32([usbPortsDictionary objectForKey:@"UsbControllerLocationID"]);
		NSString *hubName = [usbPortsDictionary objectForKey:@"HubName"];
		uint32_t usbPort = propertyToUInt32([usbPortsDictionary objectForKey:@"port"]);
		bool isUsbControllerLocationIDEqual = (usbControllerLocationID == -1) || (usbControllerLocationID == controllerLocationID);
		bool isHubEqual = ((hubName == nil && hub == nil) || ([self isInternalHubPort:hubName] && [self isInternalHubPort:hub]) || [hubName isEqualToString:hub]);
		
		if ([usbController isEqualToString:controller] && isUsbControllerLocationIDEqual && isHubEqual && (usbPort == port))
		{
			*index = i;
			
			return true;
		}
	}
	
	return false;
}

- (void)createUSBPortConnector:(NSMutableDictionary *)propertyDictionary
{
	uint32_t port = propertyToUInt32([propertyDictionary objectForKey:@"port"]);
	uint32_t usbControllerLocationID = propertyToUInt32([propertyDictionary objectForKey:@"UsbControllerLocationID"]);
	uint32_t hubLocationID = propertyToUInt32([propertyDictionary objectForKey:@"HubLocation"]);

	if (isPortLocationHUB1(hubLocationID) || isPortLocationHUB2(hubLocationID))
	{
		[propertyDictionary setObject:@(kTypeA) forKey:@"portType"];
		
		return;
	}
	else if ((isControllerLocationEH1(usbControllerLocationID) || isControllerLocationEH2(usbControllerLocationID)) && port == 0x1)
	{
		// PR11, PR21
		[propertyDictionary setObject:@(kInternal) forKey:@"UsbConnector"];
		
		return;
	}
	
	[propertyDictionary setObject:@(kUSB3StandardA) forKey:@"UsbConnector"];
}

- (NSString *)generateUSBPortName:(uint32_t)usbControllerID hubLocationID:(uint32_t)hubLocationID locationID:(uint32_t)locationID portNumber:(uint32_t)portNumber
{
	// LocationID
	// The value (e.g. 0x14320000) is represented as follows: 0xAABCDEFG
	// AA  — Ctrl number 8 bits (e.g. 0x14, aka XHCI)
	// B   - Port number 4 bits (e.g. 0x3, aka SS03)
	// C~F - Bus number  4 bits (e.g. 0x2, aka IOUSBHostHIDDevice)
	//
	// C~F are filled as many times as many USB Hubs are there on the port.
	//
	// PR11 = 0x1D100000 (HUB1)
	// PR21 = 0x1A100000 (HUB2)
	// PR11 = 0x1D1x0000 (HPxx)
	// PR21 = 0x1A1x0000 (HPxx)
	// XHCx - 0x14xx0000 (HSxx, SSxx)
	// EHx1 - 0x1Dxx0000 (PRxx)
	// EHx2 - 0x1Axx0000 (PRxx)

	uint8_t ctrl = locationID >> 24;
	//uint8_t port = (locationID >> 20) & 0xF;
	//uint8_t bus = locationID & 0xFFFFF;
	NSString *portName = nil;

	switch(ctrl)
	{
		case 0x14: // XHCI
			[self getUSBPortNameWithControllerID:usbControllerID portNumber:portNumber portName:&portName];
			break;
		case 0x1D: // EHx1
			if (isPortLocationHUB1(hubLocationID))
				[self getUSBPortNameWithControllerName:@"HUB1" portNumber:portNumber portName:&portName];
			else
				[self getUSBPortNameWithControllerName:@"EH01" portNumber:portNumber portName:&portName];
			break;
		case 0x1A: // EHx2
			if (isPortLocationHUB2(hubLocationID))
				[self getUSBPortNameWithControllerName:@"HUB2" portNumber:portNumber portName:&portName];
			else
				[self getUSBPortNameWithControllerName:@"EH02" portNumber:portNumber portName:&portName];
			break;
		default:
			break;
	}
	
	return (portName != nil ? portName : [NSString stringWithFormat:@"XX%02d", portNumber]);
}

- (NSString *)getUSBSeries:(uint32_t)usbControllerID
{
	// https://pci-ids.ucw.cz/read/PC/8086
	// EH01: 8-USB2 ports PR11-PR18.
	// EH02: 6-USB2 ports PR21-PR28.
	// EH01 hub: 8-USB2 ports HP11-HP18.
	// EH02 hub: 8-USB2 ports HP21-HP28.
	// XHC, 7-series chipset (8086:1e31): 4-USB2 ports HS01-HS04, 4-USB3 ports SS01-SS04.
	// XHC, 8/9-series chipset (8086:9xxx): 9-USB2 ports HS01-HS09, 6-USB3 ports SS01-SS06.
	// XHC, 8/9-series chipset (8086:8xxx): 14-USB2 ports HS01-HS14, 6-USB3 ports SS01-SS06.
	// XHC, 8/9-series chipset (8086:9cb1): 11-USB ports HS01-HS11, 4-USB3 ports SS01-SS04.
	// XHC, 100-series chipset (8086:a12f): 14-USB2 ports HS01-HS14, 10-USB3 ports SS01-SS10, plus USR1/USR2)
	// XHC, 100-series chipset (8086:9d2f): 10-USB2 ports HS01-HS10, 6-USB3 ports SS01-SS06, plus USR1/USR2)
	// XHC, 200-series/300-series chipset, etc.
	
	uint16_t vendorID = (usbControllerID & 0xFFFF);
	uint16_t deviceID = (usbControllerID >> 16);
	uint16_t subDeviceID = (deviceID & 0xFF);
	NSString *usbControllerIDString = [NSString stringWithFormat:@"%08X", usbControllerID];
	
	if (usbControllerIDString == nil || vendorID != 0x8086)
		return GetLocalizedString(@"Unknown");
	
	switch (deviceID >> 8)
	{
		case 0x1c:
			return @"6/C200";
		case 0x1d:
			return @"C600/X79";
		case 0x1e:
			return @"7/C210";
		case 0x8c:
			if (subDeviceID < 0x80)
				return @"8/C220";
			else
				return @"9";
		case 0x8d:
			return @"C610/X99";
		case 0x9c:
			if (subDeviceID < 0x80)
				return @"8";
			else
				return @"9"; // Wildcat Point
		case 0x9d:
			if (subDeviceID < 0x80)
				return @"100"; // Sunrise Point
			else
				return @"300"; // Cannon Point
		case 0xa1:
			if (subDeviceID < 0x80)
				return @"100/C230";
			else
				return @"C620";
		case 0xa2:
			return @"200/Z370";
		case 0xa3:
			return @"300"; // Cannon Lake
	}

	return GetLocalizedString(@"Unknown");
}

- (bool)getUSBKextRequirements:(NSNumber *)usbControllerID usbRequirements:(NSString **)usbRequirements
{
	NSString *usbControllerIDString = [NSString stringWithFormat:@"%08X", [usbControllerID unsignedIntValue]];
	
	// 8086:8CB1 -> XHCI-9-series.kext
	// 8086:8D31, 8086:A2AF, 8086:A36D or 8086:9DED -> XHCI-unsupported.kext
	// 8086:1E31, 8086:8C31, 8086:8CB1, 8086:8D31, 8086:9C31, 8086:9CB1 -> FakePCIID.kext + FakePCIID_XHCIMux.kext
	
	// As of 10.11.1 no longer needed
	NSOperatingSystemVersion minimumSupportedOSVersion = { .majorVersion = 10, .minorVersion = 11, .patchVersion = 1 };
	BOOL isSupported = [NSProcessInfo.processInfo isOperatingSystemAtLeastVersion:minimumSupportedOSVersion];
	
	if (!isSupported)
	{
		if ([usbControllerIDString isEqualToString:@"80868CB1"])
		{
			*usbRequirements = @"XHCI-9-series.kext";
			return true;
		}
	}
	
	if ([@[@"80868D31", @"8086A2AF", @"8086A36D", @"80869DED"] containsObject:usbControllerIDString])
	{
		*usbRequirements = @"XHCI-unsupported.kext";
		return true;
	}
	
	if ([@[@"80861E31", @"80868C31", @"80868CB1", @"80868D31", @"80869C31", @"80869CB1"] containsObject:usbControllerIDString])
	{
		*usbRequirements = @"FakePCIID.kext + FakePCIID_XHCIMux.kext";
		return true;
	}
	
	*usbRequirements = GetLocalizedString(@"None");
	
	return false;
}

- (void)importUSBPorts
{
	NSOpenPanel *openPanel = [NSOpenPanel openPanel];
	[openPanel setNameFieldStringValue:@"USBPorts.kext"];
	[openPanel setCanChooseFiles:YES];
	[openPanel setAllowsMultipleSelection:NO];
	[openPanel setCanChooseDirectories:NO];
	[openPanel setAllowedFileTypes:@[@"kext"]];
	[openPanel setPrompt:GetLocalizedString(@"Select")];
	
	[openPanel beginSheetModalForWindow:_window completionHandler:^(NSModalResponse returnCode)
	 {
		 [NSApp stopModalWithCode:returnCode];
	 }];
	
	if ([NSApp runModalForWindow:_window] != NSOKButton)
		return;
	
	[_usbPortsArray removeAllObjects];
	
	NSString *infoPath = [NSString stringWithFormat:@"%@/Contents/Info.plist", [[openPanel URL] path]];
	NSDictionary *infoDictionary = [NSDictionary dictionaryWithContentsOfFile:infoPath];
	NSDictionary *ioKitPersonalities = [infoDictionary objectForKey:@"IOKitPersonalities"];
	
	for (NSString *ioKitKey in [ioKitPersonalities allKeys])
	{
		NSArray *ioKitKeyArray = [ioKitKey componentsSeparatedByString:@"-"];
		
		if ([ioKitKeyArray count] < 2)
			continue;
		
		NSString *usbController = (NSString *)[ioKitKeyArray objectAtIndex:1];
		NSDictionary *ioKitPersonalityDictionary = [ioKitPersonalities objectForKey:ioKitKey];
		NSNumber *locationID = [ioKitPersonalityDictionary objectForKey:@"locationID"];
		NSDictionary *ioProviderMergePropertiesDictionary = [ioKitPersonalityDictionary objectForKey:@"IOProviderMergeProperties"];
		NSDictionary *portsDictionary = [ioProviderMergePropertiesDictionary objectForKey:@"ports"];

		for (NSString *portsKey in [portsDictionary allKeys])
		{
			NSMutableDictionary *usbEntryDictionary = [[[portsDictionary objectForKey:portsKey] mutableCopy] autorelease];
			[usbEntryDictionary setObject:portsKey forKey:@"name"];
			[usbEntryDictionary setObject:@(0) forKey:@"locationID"];
			[usbEntryDictionary setObject:@"" forKey:@"Device"];
			[usbEntryDictionary setObject:usbController forKey:@"UsbController"];
			[usbEntryDictionary setObject:@(-1) forKey:@"UsbControllerLocationID"];
			[usbEntryDictionary setObject:[NSNumber numberWithBool:NO] forKey:@"IsActive"];
			
			if ([ioKitKey hasSuffix:@"-internal-hub"])
			{
				[usbEntryDictionary setObject:@"AppleUSB20InternalHub" forKey:@"HubName"];
				[usbEntryDictionary setObject:locationID forKey:@"HubLocation"];
			}
			
			[_usbPortsArray addObject:usbEntryDictionary];
		}
	}
	
	[self refreshUSBPorts];
	[self refreshUSBControllers];
}

- (void)getBootLog
{
	CFTypeRef property = nil;
	
	// IOService:/boot-log
	// IODeviceTree:/efi/platform
	
	if (!getIORegProperty(@"IOService:/", @"boot-log", &property))
		if (!getIORegProperty(@"IODeviceTree:/efi/platform", @"boot-log", &property))
			return;
	
	NSData *valueData = (__bridge NSData *)property;
	_bootLog = [[NSString alloc] initWithData:valueData encoding:NSASCIIStringEncoding];
	
	if (property != nil)
		CFRelease(property);
}

- (bool)tryGetNearestModel:(NSArray *)modelArray modelIdentifier:(NSString *)modelIdentifier nearestModelIdentifier:(NSString **)nearestModelIdentifier
{
	bool modelFound = false;
	NSString *modelName, *modelMajor, *modelMinor;
	NSInteger nearestModelMajor = NSIntegerMax, nearestModelMinor = NSIntegerMax;
	
	if (![self tryGetModelInfo:modelIdentifier name:&modelName major:&modelMajor minor:&modelMinor])
		return false;

	for (NSString *findModelIdentifier in modelArray)
	{
		NSString *findModelName, *findModelMajor, *findModelMinor;
		
		if (![self tryGetModelInfo:findModelIdentifier name:&findModelName major:&findModelMajor minor:&findModelMinor])
			continue;
		
		if (![modelName isEqualToString:findModelName])
			continue;
		
		//NSLog(@"%@ <-> %@", ioUSBHostIOKitKey, _modelIdentifier);
		//NSLog(@"ModelName: %@ ModelMajor: %@ ModelMinor: %@", ioKitModelName, ioKitModelMajor, ioKitModelMinor);
		
		NSInteger nearestModelMajorNumber = ABS([findModelMajor integerValue] - [modelMajor integerValue]);
		NSInteger nearestModelMinorNumber = ABS([findModelMinor integerValue] - [modelMinor integerValue]);
		
		if (nearestModelMajorNumber < nearestModelMajor && nearestModelMinorNumber < nearestModelMinor)
		{
			nearestModelMajor = nearestModelMajorNumber;
			nearestModelMinor = nearestModelMinorNumber;
		
			*nearestModelIdentifier = findModelIdentifier;
			
			modelFound = true;
		}
	}
	
	return modelFound;
}

- (bool)tryGetModelInfo:(NSString *)modelIdentifier name:(NSString **)name major:(NSString **)major minor:(NSString **)minor
{
	NSError *regError = nil;
	NSRegularExpression *regEx = [NSRegularExpression regularExpressionWithPattern:@"(^\\D*)([0-9]+),([0-9]+)" options:NSRegularExpressionCaseInsensitive error:&regError];
	
	if (regError)
		return false;
	
	NSTextCheckingResult *match = [regEx firstMatchInString:modelIdentifier options:0 range:NSMakeRange(0, [modelIdentifier length])];
	
	if (match == nil)
		return false;
	
	if ([match numberOfRanges] != 4)
		return false;

	*name = [modelIdentifier substringWithRange:[match rangeAtIndex:1]];
	*major = [modelIdentifier substringWithRange:[match rangeAtIndex:2]];
	*minor = [modelIdentifier substringWithRange:[match rangeAtIndex:3]];

	return true;
}

NSInteger usbPortSort(id a, id b, void *context)
{
	NSMutableDictionary *first = (NSMutableDictionary *)a;
	NSMutableDictionary *second = (NSMutableDictionary *)b;
	
	NSComparisonResult result = [first[@"UsbController"] compare:second[@"UsbController"]];
	
	if (result != NSOrderedSame)
		return result;
	
	return [first[@"port"] compare:second[@"port"]];
}

NSInteger usbControllerSort(id a, id b, void *context)
{
	NSMutableDictionary *first = (NSMutableDictionary *)a;
	NSMutableDictionary *second = (NSMutableDictionary *)b;
	
	NSComparisonResult result = [first[@"Type"] compare:second[@"Type"]];
	
	if (result != NSOrderedSame)
		return result;
	
	return [first[@"ID"] compare:second[@"ID"]];
}

- (void)refreshDisplays
{
	[_displaysArray removeAllObjects];
	
	getDisplayArray(&_displaysArray);
		
	[_displaysTableView reloadData];
	 
	if ([_displaysArray count] > 0)
	{
		NSIndexSet *indexSet = [NSIndexSet indexSetWithIndex:0];
		[_displaysTableView selectRowIndexes:indexSet byExtendingSelection:NO];
	}
	
	[_resolutionsTableView reloadData];
}

- (bool)spoofAudioDeviceID:(uint32_t)deviceID newDeviceID:(uint32_t *)newDeviceID;
{
	// Intel HDMI Audio - Haswell
	// - 8086:0C0C -> 8086:0A0C
	// Intel HDMI Audio - 100-series (0xA170)
	// - 8086:A170 -> 8086:9D70
	// Intel HDMI Audio - 100-series (0x9D74 0x9D71 0x9D70 0xA171)
	// - 8086:9D70 8086:9D71 8086:9D74 8086:A171 -> 8086:A170
	// Intel HDMI Audio - 200-series (0xA2F0)
	// - 8086:A2F0 -> 8086:A170
	// Intel HDMI Audio - 300-series (0xA348 0x9DC8)
	// - 8086:A348 8086:9DC8 -> 8086:A170
	
	/* *audioDeviceID = 0;
	NSString *deviceID = [NSString stringWithFormat:@"%04X:%04X", _audioVendorID, _audioDeviceID];
	
	// Intel HDMI Audio - Haswell
	if ([@[@"8086:0C0C"] containsObject:deviceID])
		*audioDeviceID = 0x0A0C;
	
	// Intel HDMI Audio - 100-series (0xA170)
	if ([@[@"8086:A170"] containsObject:deviceID])
		*audioDeviceID = 0x9D70;
	
	// Intel HDMI Audio - 100-series (0x9D70 0x9D71 0x9D74 0xA171)
	if ([@[@"8086:9D70", @"8086:9D71", @"8086:9D74", @"8086:A171"] containsObject:deviceID])
		*audioDeviceID = 0xA170;
	
	// Intel HDMI Audio - 200-series (0xA2F0)
	if ([@[@"8086:A2F0"] containsObject:deviceID])
		*audioDeviceID = 0xA170;
	
	// Intel HDMI Audio - 300-series (0xA348 0x9DC8)
	if ([@[@"8086:A348", @"8086:9DC8"] containsObject:deviceID])
		*audioDeviceID = 0xA170; */
	
	*newDeviceID = [[_intelSpoofAudioDictionary objectForKey:[NSString stringWithFormat:@"%08X", deviceID]] unsignedIntValue];
	
	return (*newDeviceID != 0);
}

- (bool)getDeviceIDArray:(NSMutableArray **)deviceIDArray
{
	// Device ID's are located in:
	// /System/Library/Extensions/.../Contents/Info.plist/IOKitPersonalities/AppleIntelFramebufferController/IOPCIPrimaryMatch
	// Eg. /System/Library/Extensions/AppleIntelCFLGraphicsFramebuffer.kext/Contents/Info.plist/IOKitPersonalities/AppleIntelFramebufferController/IOPCIPrimaryMatch
	*deviceIDArray = [NSMutableArray array];
	NSInteger intelGen = [_intelGenComboBox indexOfSelectedItem];
	
	if (intelGen == -1)
		return false;
	
	NSString *intelGenString = [_intelGenComboBox objectValueOfSelectedItem];
	NSString *deviceIDString = [_intelDeviceIDsDictionary objectForKey:intelGenString];
	*deviceIDArray = getHexArrayFromString(deviceIDString);
	
	for (int i = 0; i < [*deviceIDArray count]; i++)
	{
		NSNumber *deviceIDNumber = (*deviceIDArray)[i];
		uint32_t deviceID = [deviceIDNumber unsignedIntValue];
		(*deviceIDArray)[i] = @(deviceID >> 16);
	}
	
	return true;
}

- (void)applyCurrentPatches
{
	NSInteger intelGen = [_intelGenComboBox indexOfSelectedItem];
	NSInteger platformIDIndex = [_platformIDComboBox indexOfSelectedItem];
	
	if (intelGen == -1 || platformIDIndex == -1)
		return;

	NSMutableDictionary *propertyDictionary = nil;
	
	if (!getIORegPropertyDictionary(@"IOPCIDevice", @"IGPU", &propertyDictionary))
		return;
	
	switch (intelGen)
	{
		case IGSandyBridge:
			applyUserPatch<FramebufferSNB>(self, propertyDictionary);
			break;
		case IGIvyBridge:
			applyUserPatch<FramebufferIVB>(self, propertyDictionary);
			break;
		case IGHaswell:
			applyUserPatch<FramebufferHSW>(self, propertyDictionary);
			break;
		case IGBroadwell:
			applyUserPatch<FramebufferBDW>(self, propertyDictionary);
			break;
		case IGSkylake:
		case IGKabyLake:
			applyUserPatch<FramebufferSKL>(self, propertyDictionary);
			break;
		case IGCoffeeLake:
			applyUserPatch<FramebufferCFL>(self, propertyDictionary);
			break;
		case IGCannonLake:
			applyUserPatch<FramebufferCNL>(self, propertyDictionary);
			break;
		case IGIceLakeLP:
			applyUserPatch<FramebufferICLLP>(self, propertyDictionary);
			break;
		case IGIceLakeHP:
			applyUserPatch<FramebufferICLHP>(self, propertyDictionary);
			break;
	}
}

- (void)applyAutoPatching
{
	NSInteger intelGen = [_intelGenComboBox indexOfSelectedItem];
	NSInteger platformIDIndex = [_platformIDComboBox indexOfSelectedItem];
	
	if (intelGen == -1 || platformIDIndex == -1)
		return;
	
	switch (intelGen)
	{
		case IGSandyBridge:
			applyAutoPatching<FramebufferSNB>(self);
			break;
		case IGIvyBridge:
			applyAutoPatching<FramebufferIVB>(self);
			break;
		case IGHaswell:
			applyAutoPatching<FramebufferHSW>(self);
			break;
		case IGBroadwell:
			applyAutoPatching<FramebufferBDW>(self);
			break;
		case IGSkylake:
		case IGKabyLake:
			applyAutoPatching<FramebufferSKL>(self);
			break;
		case IGCoffeeLake:
			applyAutoPatching<FramebufferCFL>(self);
			break;
		case IGCannonLake:
			applyAutoPatching<FramebufferCNL>(self);
			break;
		case IGIceLakeLP:
			applyAutoPatching<FramebufferICLLP>(self);
			break;
		case IGIceLakeHP:
			applyAutoPatching<FramebufferICLHP>(self);
			break;
	}
}

- (void)resetAutoPatching
{
	NSInteger intelGen = [_intelGenComboBox indexOfSelectedItem];
	NSInteger platformIDIndex = [_platformIDComboBox indexOfSelectedItem];
	
	if (intelGen == -1 || platformIDIndex == -1)
		return;
	
	switch (intelGen)
	{
		case IGSandyBridge:
			resetAutoPatching<FramebufferSNB>(self);
			break;
		case IGIvyBridge:
			resetAutoPatching<FramebufferIVB>(self);
			break;
		case IGHaswell:
			resetAutoPatching<FramebufferHSW>(self);
			break;
		case IGBroadwell:
			resetAutoPatching<FramebufferBDW>(self);
			break;
		case IGSkylake:
		case IGKabyLake:
			resetAutoPatching<FramebufferSKL>(self);
			break;
		case IGCoffeeLake:
			resetAutoPatching<FramebufferCFL>(self);
			break;
		case IGCannonLake:
			resetAutoPatching<FramebufferCNL>(self);
			break;
		case IGIceLakeLP:
			resetAutoPatching<FramebufferICLLP>(self);
			break;
		case IGIceLakeHP:
			resetAutoPatching<FramebufferICLHP>(self);
			break;
	}
}

- (uint32_t)getGPUDeviceID:(uint32_t)platformID
{
	NSString *intelGenString = nil;
	
	if (![self getIntelGenMatch:platformID intelGen:&intelGenString])
		return 0;
	
	NSString *intelDeviceIDString = [_intelDeviceIDsDictionary objectForKey:intelGenString];
	NSArray *intelDeviceIDArray = [intelDeviceIDString componentsSeparatedByString:@" "];
	uint32_t deviceID = (platformID & 0xFFFF0000) | 0x8086;
	NSString *deviceIDString = [NSString stringWithFormat:@"0x%08X", deviceID];
	
	if ([intelDeviceIDArray containsObject:deviceIDString])
		return deviceID;

	return 0;
}

- (NSString *)getGPUString:(uint32_t)platformID
{
	uint32_t deviceID = [self getGPUDeviceID:platformID];
	
	if (deviceID == 0)
		return @"???";
	
	NSString *deviceIDString = [NSString stringWithFormat:@"0x%04X", deviceID >> 16];
	NSString *gpuString = [_intelGPUsDictionary objectForKey:deviceIDString];

	if (gpuString == nil)
		return @"???";
	
	return gpuString;
}

- (NSString *)getModelString:(uint32_t)platformID
{
	NSString *platformIDString = [NSString stringWithFormat:@"0x%08X", platformID];
	NSString *modelString = [_intelModelsDictionary objectForKey:platformIDString];
	
	if (modelString == nil)
		return @"";
	
	return modelString;
}

- (void)saveFramebufferText:(NSString *)framebufferTextPath
{
	NSInteger intelGen = [_intelGenComboBox indexOfSelectedItem];
	NSInteger platformIDIndex = [_platformIDComboBox indexOfSelectedItem];
	
	if (intelGen == -1 || platformIDIndex == -1)
		return;
	
	FILE *file;
	file = fopen([framebufferTextPath UTF8String], "w");
	
	if (!file)
		return;
	
	switch (intelGen)
	{
		case IGSandyBridge:
			outputPlatformInformationList(self, file, reinterpret_cast<FramebufferSNB *>(_originalFramebufferList));
			break;
		case IGIvyBridge:
			outputPlatformInformationList(self, file, reinterpret_cast<FramebufferIVB *>(_originalFramebufferList));
			break;
		case IGHaswell:
			outputPlatformInformationList(self, file, reinterpret_cast<FramebufferHSW *>(_originalFramebufferList));
			break;
		case IGBroadwell:
			outputPlatformInformationList(self, file, reinterpret_cast<FramebufferBDW *>(_originalFramebufferList));
			break;
		case IGSkylake:
		case IGKabyLake:
			outputPlatformInformationList(self, file, reinterpret_cast<FramebufferSKL *>(_originalFramebufferList));
			break;
		case IGCoffeeLake:
			outputPlatformInformationList(self, file, reinterpret_cast<FramebufferCFL *>(_originalFramebufferList));
			break;
		case IGCannonLake:
			outputPlatformInformationList(self, file, reinterpret_cast<FramebufferCNL *>(_originalFramebufferList));
			break;
		case IGIceLakeLP:
			outputPlatformInformationList(self, file, reinterpret_cast<FramebufferICLLP *>(_originalFramebufferList));
			break;
		case IGIceLakeHP:
			outputPlatformInformationList(self, file, reinterpret_cast<FramebufferICLHP *>(_originalFramebufferList));
			break;
	}
	
	fclose(file);
}

- (void) saveFramebufferBinary:(NSString *)framebufferTextPath
{
	NSInteger intelGen = [_intelGenComboBox indexOfSelectedItem];
	NSInteger platformIDIndex = [_platformIDComboBox indexOfSelectedItem];
	
	if (intelGen == -1 || platformIDIndex == -1)
		return;
	
	FILE *file;
	file = fopen([framebufferTextPath UTF8String], "wb");
	
	if (!file)
		return;
	
	switch (intelGen)
	{
		case IGSandyBridge:
			fwrite(_originalFramebufferList, sizeof(FramebufferSNB), _framebufferCount, file);
			break;
		case IGIvyBridge:
			fwrite(_originalFramebufferList, sizeof(FramebufferIVB), _framebufferCount, file);
			break;
		case IGHaswell:
			fwrite(_originalFramebufferList, sizeof(FramebufferHSW), _framebufferCount, file);
			break;
		case IGBroadwell:
			fwrite(_originalFramebufferList, sizeof(FramebufferBDW), _framebufferCount, file);
			break;
		case IGSkylake:
		case IGKabyLake:
			fwrite(_originalFramebufferList, sizeof(FramebufferSKL), _framebufferCount, file);
			break;
		case IGCoffeeLake:
			fwrite(_originalFramebufferList, sizeof(FramebufferCFL), _framebufferCount, file);
			break;
		case IGCannonLake:
			fwrite(_originalFramebufferList, sizeof(FramebufferCNL), _framebufferCount, file);
			break;
		case IGIceLakeLP:
			fwrite(_originalFramebufferList, sizeof(FramebufferICLLP), _framebufferCount, file);
			break;
		case IGIceLakeHP:
			fwrite(_originalFramebufferList, sizeof(FramebufferICLHP), _framebufferCount, file);
			break;
	}
	
	fclose(file);
}

- (void) addToList:(NSMutableArray *)list name:(NSString *)name value:(NSString *)value
{
	NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
	
	[dictionary setValue:GetLocalizedString(name) forKey:@"Name"];
	[dictionary setValue:value forKey:@"Value"];
	
	[list addObject:dictionary];
}

- (void) populateFramebufferFlags:(FramebufferFlags)framebufferFlags
{
	for (int i = 0; i < g_framebufferFlagsArray.count; i++)
		[self addToList:_framebufferFlagsArray name:g_framebufferFlagsArray[i] value:framebufferFlags.value & (1 << i) ? @"Yes" : @"No"];
}

- (void) populateConnectorFlags:(ConnectorFlags)connectorFlags
{
	for (int i = 0; i < g_connectorFlagsArray.count; i++)
		[self addToList:_connectorFlagsArray name:g_connectorFlagsArray[i] value:connectorFlags.value & (1 << i) ? @"Yes" : @"No"];
}

- (void) populateFramebufferInfoList
{
	[self updateInfo];
	
	[_framebufferInfoArray removeAllObjects];
	[_framebufferFlagsArray removeAllObjects];
	
	NSInteger intelGen = [_intelGenComboBox indexOfSelectedItem];
	NSInteger platformIDIndex = [_platformIDComboBox indexOfSelectedItem];
	
	if (intelGen == -1 || platformIDIndex == -1)
		return;
	
	switch (intelGen)
	{
		case IGSandyBridge:
		{
			FramebufferSNB &framebufferSNB = reinterpret_cast<FramebufferSNB *>(_modifiedFramebufferList)[platformIDIndex];
			
			[self addToList:_framebufferInfoArray name:@"Mobile" value:framebufferSNB.fMobile ? @"Yes" : @"No"];
			[self addToList:_framebufferInfoArray name:@"PipeCount" value:[NSString stringWithFormat:@"%d", framebufferSNB.fPipeCount]];
			[self addToList:_framebufferInfoArray name:@"PortCount" value:[NSString stringWithFormat:@"%d", framebufferSNB.fPortCount]];
			[self addToList:_framebufferInfoArray name:@"FBMemoryCount" value:[NSString stringWithFormat:@"%d", framebufferSNB.fFBMemoryCount]];
			[self addToList:_framebufferInfoArray name:@"BacklightFrequency" value:[NSString stringWithFormat:@"%d Hz", framebufferSNB.fBacklightFrequency]];
			[self addToList:_framebufferInfoArray name:@"BacklightMax" value:[NSString stringWithFormat:@"%d Hz", framebufferSNB.fBacklightMax]];
			
			break;
		}
		case IGIvyBridge:
		{
			FramebufferIVB &framebufferIVB = reinterpret_cast<FramebufferIVB *>(_modifiedFramebufferList)[platformIDIndex];
			
			[self addToList:_framebufferInfoArray name:@"FramebufferID" value:[NSString stringWithFormat:@"0x%08X", framebufferIVB.framebufferID]];
			[self addToList:_framebufferInfoArray name:@"Mobile" value:framebufferIVB.fMobile ? @"Yes" : @"No"];
			[self addToList:_framebufferInfoArray name:@"PipeCount" value:[NSString stringWithFormat:@"%d", framebufferIVB.fPipeCount]];
			[self addToList:_framebufferInfoArray name:@"PortCount" value:[NSString stringWithFormat:@"%d", framebufferIVB.fPortCount]];
			[self addToList:_framebufferInfoArray name:@"FBMemoryCount" value:[NSString stringWithFormat:@"%d", framebufferIVB.fFBMemoryCount]];
			[self addToList:_framebufferInfoArray name:@"StolenMemorySize" value:bytesToPrintable(framebufferIVB.fStolenMemorySize)];
			[self addToList:_framebufferInfoArray name:@"FramebufferMemorySize" value:bytesToPrintable(framebufferIVB.fFramebufferMemorySize)];
			[self addToList:_framebufferInfoArray name:@"UnifiedMemorySize" value:bytesToPrintable(framebufferIVB.fUnifiedMemorySize)];
			[self addToList:_framebufferInfoArray name:@"BacklightFrequency" value:[NSString stringWithFormat:@"%d Hz", framebufferIVB.fBacklightFrequency]];
			[self addToList:_framebufferInfoArray name:@"BacklightMax" value:[NSString stringWithFormat:@"%d Hz", framebufferIVB.fBacklightMax]];
			
			break;
		}
		case IGHaswell:
		{
			FramebufferHSW &framebufferHWL = reinterpret_cast<FramebufferHSW *>(_modifiedFramebufferList)[platformIDIndex];
			
			[self addToList:_framebufferInfoArray name:@"FramebufferID" value:[NSString stringWithFormat:@"0x%08X", framebufferHWL.framebufferID]];
			[self addToList:_framebufferInfoArray name:@"Mobile" value:framebufferHWL.fMobile ? @"Yes" : @"No"];
			[self addToList:_framebufferInfoArray name:@"PipeCount" value:[NSString stringWithFormat:@"%d", framebufferHWL.fPipeCount]];
			[self addToList:_framebufferInfoArray name:@"PortCount" value:[NSString stringWithFormat:@"%d", framebufferHWL.fPortCount]];
			[self addToList:_framebufferInfoArray name:@"FBMemoryCount" value:[NSString stringWithFormat:@"%d", framebufferHWL.fFBMemoryCount]];
			[self addToList:_framebufferInfoArray name:@"StolenMemorySize" value:bytesToPrintable(framebufferHWL.fStolenMemorySize)];
			[self addToList:_framebufferInfoArray name:@"FramebufferMemorySize" value:bytesToPrintable(framebufferHWL.fFramebufferMemorySize)];
			[self addToList:_framebufferInfoArray name:@"CursorMemorySize" value:bytesToPrintable(framebufferHWL.fCursorMemorySize)];
			[self addToList:_framebufferInfoArray name:@"UnifiedMemorySize" value:bytesToPrintable(framebufferHWL.fUnifiedMemorySize)];
			[self addToList:_framebufferInfoArray name:@"BacklightFrequency" value:[NSString stringWithFormat:@"%d Hz", framebufferHWL.fBacklightFrequency]];
			[self addToList:_framebufferInfoArray name:@"BacklightMax" value:[NSString stringWithFormat:@"%d Hz", framebufferHWL.fBacklightMax]];
			[self addToList:_framebufferInfoArray name:@"Flags" value:[NSString stringWithFormat:@"0x%08X", framebufferHWL.flags.value]];
			[self addToList:_framebufferInfoArray name:@"CamelliaVersion" value:camilliaVersionToString((CamelliaVersion)framebufferHWL.camelliaVersion)];
			[self addToList:_framebufferInfoArray name:@"NumTransactionsThreshold" value:[NSString stringWithFormat:@"%d", framebufferHWL.fNumTransactionsThreshold]];
			[self addToList:_framebufferInfoArray name:@"VideoTurboFreq" value:[NSString stringWithFormat:@"%d", framebufferHWL.fVideoTurboFreq]];
			
			[self populateFramebufferFlags:framebufferHWL.flags];
			
			break;
		}
		case IGBroadwell:
		{
			FramebufferBDW &framebufferBDW = reinterpret_cast<FramebufferBDW *>(_modifiedFramebufferList)[platformIDIndex];
			
			[self addToList:_framebufferInfoArray name:@"FramebufferID" value:[NSString stringWithFormat:@"0x%08X", framebufferBDW.framebufferID]];
			[self addToList:_framebufferInfoArray name:@"Mobile" value:framebufferBDW.fMobile ? @"Yes" : @"No"];
			[self addToList:_framebufferInfoArray name:@"PipeCount" value:[NSString stringWithFormat:@"%d", framebufferBDW.fPipeCount]];
			[self addToList:_framebufferInfoArray name:@"PortCount" value:[NSString stringWithFormat:@"%d", framebufferBDW.fPortCount]];
			[self addToList:_framebufferInfoArray name:@"FBMemoryCount" value:[NSString stringWithFormat:@"%d", framebufferBDW.fFBMemoryCount]];
			[self addToList:_framebufferInfoArray name:@"StolenMemorySize" value:bytesToPrintable(framebufferBDW.fStolenMemorySize)];
			[self addToList:_framebufferInfoArray name:@"FramebufferMemorySize" value:bytesToPrintable(framebufferBDW.fFramebufferMemorySize)];
			[self addToList:_framebufferInfoArray name:@"UnifiedMemorySize" value:bytesToPrintable(framebufferBDW.fUnifiedMemorySize)];
			[self addToList:_framebufferInfoArray name:@"BacklightFrequency" value:[NSString stringWithFormat:@"%d Hz", framebufferBDW.fBacklightFrequency]];
			[self addToList:_framebufferInfoArray name:@"BacklightMax" value:[NSString stringWithFormat:@"%d Hz", framebufferBDW.fBacklightMax]];
			[self addToList:_framebufferInfoArray name:@"Flags" value:[NSString stringWithFormat:@"0x%08X", framebufferBDW.flags.value]];
			[self addToList:_framebufferInfoArray name:@"CamelliaVersion" value:camilliaVersionToString((CamelliaVersion)framebufferBDW.camelliaVersion)];
			[self addToList:_framebufferInfoArray name:@"NumTransactionsThreshold" value:[NSString stringWithFormat:@"%d", framebufferBDW.fNumTransactionsThreshold]];
			[self addToList:_framebufferInfoArray name:@"VideoTurboFreq" value:[NSString stringWithFormat:@"%d", framebufferBDW.fVideoTurboFreq]];
			
			[self populateFramebufferFlags:framebufferBDW.flags];
			
			break;
		}
		case IGSkylake:
		case IGKabyLake:
		{
			FramebufferSKL &framebufferSKL = reinterpret_cast<FramebufferSKL *>(_modifiedFramebufferList)[platformIDIndex];
			
			addFramebufferToList(self, framebufferSKL);
			
			[self populateFramebufferFlags:framebufferSKL.flags];
			
			break;
		}
		case IGCoffeeLake:
		{
			FramebufferCFL &framebufferCFL = reinterpret_cast<FramebufferCFL *>(_modifiedFramebufferList)[platformIDIndex];
			
			addFramebufferToList(self, framebufferCFL);

			[self populateFramebufferFlags:framebufferCFL.flags];
			
			break;
		}
		case IGCannonLake:
		{
			FramebufferCNL &framebufferCNL = reinterpret_cast<FramebufferCNL *>(_modifiedFramebufferList)[platformIDIndex];
			
			addFramebufferToList(self, framebufferCNL);
			
			[self populateFramebufferFlags:framebufferCNL.flags];
			
			break;
		}
		case IGIceLakeLP:
		{
			FramebufferICLLP &framebufferICLLP = reinterpret_cast<FramebufferICLLP *>(_modifiedFramebufferList)[platformIDIndex];
			
			addFramebufferToList(self, framebufferICLLP);
			
			[self populateFramebufferFlags:framebufferICLLP.flags];
			
			break;
		}
		case IGIceLakeHP:
		{
			FramebufferICLHP &framebufferICLHP = reinterpret_cast<FramebufferICLHP *>(_modifiedFramebufferList)[platformIDIndex];
			
			addFramebufferToList(self, framebufferICLHP);
			
			[self populateFramebufferFlags:framebufferICLHP.flags];
			
			break;
		}
	}
	
	[_framebufferInfoTableView reloadData];
	[_framebufferFlagsTableView reloadData];
}

- (void) setStolenMem:(uint32_t)stolenMem FBMem:(uint32_t)fbMem UnifiedMem:(uint32_t)unifiedMem
{
	NSInteger intelGen = [_intelGenComboBox indexOfSelectedItem];
	NSInteger platformIDIndex = [_platformIDComboBox indexOfSelectedItem];
	
	if (intelGen == -1 || platformIDIndex == -1)
		return;
	
	switch (intelGen)
	{
		case IGSandyBridge:
			break;
		case IGIvyBridge:
			setMemory(reinterpret_cast<FramebufferIVB *>(_modifiedFramebufferList)[platformIDIndex], stolenMem, fbMem, unifiedMem);
			break;
		case IGHaswell:
			setMemory(reinterpret_cast<FramebufferHSW *>(_modifiedFramebufferList)[platformIDIndex], stolenMem, fbMem, unifiedMem);
			break;
		case IGBroadwell:
			setMemory(reinterpret_cast<FramebufferBDW *>(_modifiedFramebufferList)[platformIDIndex], stolenMem, fbMem, unifiedMem);
			break;
		case IGSkylake:
		case IGKabyLake:
			setMemory(reinterpret_cast<FramebufferSKL *>(_modifiedFramebufferList)[platformIDIndex], stolenMem, fbMem, unifiedMem);
			break;
		case IGCoffeeLake:
			setMemory(reinterpret_cast<FramebufferCFL *>(_modifiedFramebufferList)[platformIDIndex], stolenMem, fbMem, unifiedMem);
			break;
		case IGCannonLake:
			setMemory(reinterpret_cast<FramebufferCNL *>(_modifiedFramebufferList)[platformIDIndex], stolenMem, fbMem, unifiedMem);
			break;
		case IGIceLakeLP:
			setMemory(reinterpret_cast<FramebufferICLLP *>(_modifiedFramebufferList)[platformIDIndex], stolenMem, fbMem, unifiedMem);
			break;
		case IGIceLakeHP:
			setMemory(reinterpret_cast<FramebufferICLHP *>(_modifiedFramebufferList)[platformIDIndex], stolenMem, fbMem, unifiedMem);
			break;
	}
}

- (void) getMemoryIsMobile:(bool *)isMobile StolenMem:(uint32_t *)stolenMem FBMem:(uint32_t  *)fbMem UnifiedMem:(uint32_t  *)unifiedMem MaxStolenMem:(uint32_t  *)maxStolenMem TotalStolenMem:(uint32_t  *)totalStolenMem TotalCursorMem:(uint32_t  *)totalCursorMem MaxOverallMem:(uint32_t  *)maxOverallMem
{
	NSInteger intelGen = [_intelGenComboBox indexOfSelectedItem];
	NSInteger platformIDIndex = [_platformIDComboBox indexOfSelectedItem];
	
	if (intelGen == -1 || platformIDIndex == -1)
		return;
	
	switch (intelGen)
	{
		case IGSandyBridge:
		{
			FramebufferSNB &framebufferSNB = reinterpret_cast<FramebufferSNB *>(_modifiedFramebufferList)[platformIDIndex];
			
			*isMobile = framebufferSNB.fMobile;
			*maxStolenMem = 0 * framebufferSNB.fFBMemoryCount;
			*totalStolenMem = 0; /* the assert here does not multiply, why? */
			*totalCursorMem = framebufferSNB.fPipeCount * 0x80000; // 32 KB
			*maxOverallMem = *totalCursorMem + *maxStolenMem + framebufferSNB.fPortCount * 0x1000; // 1 KB
			
			break;
		}
		case IGIvyBridge:
		{
			FramebufferIVB &framebufferIVB = reinterpret_cast<FramebufferIVB *>(_modifiedFramebufferList)[platformIDIndex];
			
			*isMobile = framebufferIVB.fMobile;
			*stolenMem = framebufferIVB.fStolenMemorySize;
			*fbMem = framebufferIVB.fFramebufferMemorySize;
			*unifiedMem = framebufferIVB.fUnifiedMemorySize;
			*maxStolenMem = framebufferIVB.fFramebufferMemorySize * framebufferIVB.fFBMemoryCount;
			*totalStolenMem = framebufferIVB.fFramebufferMemorySize; /* the assert here does not multiply, why? */
			*totalCursorMem = framebufferIVB.fPipeCount * 0x80000; // 32 KB
			*maxOverallMem = *totalCursorMem + *maxStolenMem + framebufferIVB.fPortCount * 0x1000; // 1 KB
			
			break;
		}
		case IGHaswell:
			getMemoryHaswell(reinterpret_cast<FramebufferHSW *>(_modifiedFramebufferList)[platformIDIndex], isMobile, stolenMem, fbMem, unifiedMem, maxStolenMem, totalStolenMem, totalCursorMem, maxOverallMem);
			break;
		case IGBroadwell:
			getMemoryHaswell(reinterpret_cast<FramebufferBDW *>(_modifiedFramebufferList)[platformIDIndex], isMobile, stolenMem, fbMem, unifiedMem, maxStolenMem, totalStolenMem, totalCursorMem, maxOverallMem);
			break;
		case IGSkylake:
		case IGKabyLake:
			getMemorySkylake(reinterpret_cast<FramebufferSKL *>(_modifiedFramebufferList)[platformIDIndex], isMobile, stolenMem, fbMem, unifiedMem, maxStolenMem, totalStolenMem, totalCursorMem, maxOverallMem);
			break;
		case IGCoffeeLake:
			getMemorySkylake(reinterpret_cast<FramebufferCFL *>(_modifiedFramebufferList)[platformIDIndex], isMobile, stolenMem, fbMem, unifiedMem, maxStolenMem, totalStolenMem, totalCursorMem, maxOverallMem);
			break;
		case IGCannonLake:
			getMemorySkylake(reinterpret_cast<FramebufferCNL *>(_modifiedFramebufferList)[platformIDIndex], isMobile, stolenMem, fbMem, unifiedMem, maxStolenMem, totalStolenMem, totalCursorMem, maxOverallMem);
			break;
		case IGIceLakeLP:
			getMemorySkylake(reinterpret_cast<FramebufferICLLP *>(_modifiedFramebufferList)[platformIDIndex], isMobile, stolenMem, fbMem, unifiedMem, maxStolenMem, totalStolenMem, totalCursorMem, maxOverallMem);
			break;
		case IGIceLakeHP:
			getMemorySkylake(reinterpret_cast<FramebufferICLHP *>(_modifiedFramebufferList)[platformIDIndex], isMobile, stolenMem, fbMem, unifiedMem, maxStolenMem, totalStolenMem, totalCursorMem, maxOverallMem);
			break;
	}
}

- (void) updateInfo
{
	NSInteger intelGen = [_intelGenComboBox indexOfSelectedItem];
	NSInteger platformIDIndex = [_platformIDComboBox indexOfSelectedItem];
	
	if (intelGen == -1 || platformIDIndex == -1)
		return;
	
	NSString *intelGenString = [_intelGenComboBox objectValueOfSelectedItem];
	NSString *deviceIDString = [_intelDeviceIDsDictionary objectForKey:intelGenString];
	uint32_t platformID = [self getPlatformID];
	uint32_t suggestedDeviceID = [self getGPUDeviceID:platformID];
	bool isMobile = false;
	uint32_t stolenMem = 0, fbMem = 0, unifiedMem = 0;
	uint32_t maxStolenMem = 0, totalStolenMem = 0, totalCursorMem = 0, maxOverallMem = 0;
	
	[self getMemoryIsMobile:&isMobile StolenMem:&stolenMem FBMem:&fbMem UnifiedMem:&unifiedMem MaxStolenMem:&maxStolenMem TotalStolenMem:&totalStolenMem TotalCursorMem:&totalCursorMem MaxOverallMem:&maxOverallMem];

	[_selectedFBInfoArray removeAllObjects];
	[_currentFBInfoArray removeAllObjects];
	[_vramInfoArray removeAllObjects];
	
	[self addToList:_selectedFBInfoArray name:@"Intel Generation" value:intelGenString];
	[self addToList:_selectedFBInfoArray name:@"Platform ID" value:[NSString stringWithFormat:@"0x%08X", platformID]];
	
	if (suggestedDeviceID != 0)
	{
		[self addToList:_selectedFBInfoArray name:@"GPU Device ID" value:[NSString stringWithFormat:@"0x%08X", suggestedDeviceID]];
		[self addToList:_selectedFBInfoArray name:@"GPU Name" value:[self getGPUString:platformID]];
	}
	
	[self addToList:_selectedFBInfoArray name:@"Mobile" value:isMobile ? GetLocalizedString(@"Yes") : GetLocalizedString(@"No")];
	[self addToList:_selectedFBInfoArray name:@"GPU Device ID(s)" value:deviceIDString];
	[self addToList:_selectedFBInfoArray name:@"Model(s)" value:[self getModelString:platformID]];
	
	[self addToList:_currentFBInfoArray name:@"Model" value:_modelIdentifier != nil ? _modelIdentifier : @"???"];
	[self addToList:_currentFBInfoArray name:@"Intel Generation" value:_intelGenString];
	[self addToList:_currentFBInfoArray name:@"Platform ID" value:[NSString stringWithFormat:@"0x%08X", _platformID]];
	[self addToList:_currentFBInfoArray name:@"GPU Device ID" value:[NSString stringWithFormat:@"0x%08X", (_gpuDeviceID << 16) | _gpuVendorID]];
	[self addToList:_currentFBInfoArray name:@"GPU Name" value:_gpuModel];
	
	[self addToList:_vramInfoArray name:@"Stolen" value:bytesToPrintable(stolenMem)];
	[self addToList:_vramInfoArray name:@"FBMem" value:bytesToPrintable(fbMem)];
	[self addToList:_vramInfoArray name:@"VRAM" value:bytesToPrintable(unifiedMem)];
	[self addToList:_vramInfoArray name:@"Max Stolen" value:bytesToPrintable(maxStolenMem)];
	[self addToList:_vramInfoArray name:@"Total Stolen" value:bytesToPrintable(totalStolenMem)];
	[self addToList:_vramInfoArray name:@"Total Cursor" value:bytesToPrintable(totalCursorMem)];
	[self addToList:_vramInfoArray name:@"Max Overall" value:bytesToPrintable(maxOverallMem)];
	
	[_selectedFBInfoTableView reloadData];
	[_currentFBInfoTableView reloadData];
	[_vramInfoTableView reloadData];
	
	[_headlessButton setHidden:![self isConnectorHeadless]];
}

- (uint32_t)parseMemoryString:(NSString *)memoryString
{
	uint32_t memoryValue = [memoryString intValue];
	
	if ([memoryString containsString:@"MB"])
	{
		memoryValue *= 1024 * 1024;
	}
	else if ([memoryString containsString:@"KB"])
	{
		memoryValue *= 1024;
	}
	
	//NSLog(@"value: %d bytes", memoryValue);
	
	return memoryValue;
}

- (void) dragConnectorInfo:(uint32_t)dragRow Row:(uint32_t)row
{
	NSInteger intelGen = [_intelGenComboBox indexOfSelectedItem];
	NSInteger platformIDIndex = [_platformIDComboBox indexOfSelectedItem];
	
	if (intelGen == -1 || platformIDIndex == -1)
		return;
	
	if (IS_ICELAKE(intelGen))
	{
		NSMutableArray *connectorInfoArray = [NSMutableArray array];
		
		for (int i = 0; i < 3; i++)
		{
			ConnectorInfoICL *connectorInfo = NULL;
			
			if (![self getConnectorInfoICL:&connectorInfo index:i modified:true])
				continue;
			
			NSValue *connectorInfoObject = [NSValue valueWithPointer:connectorInfo];
			
			[connectorInfoArray addObject:connectorInfoObject];
		}
		
		if (dragRow < row)
		{
			[connectorInfoArray insertObject:[connectorInfoArray objectAtIndex:dragRow] atIndex:row];
			[connectorInfoArray removeObjectAtIndex:dragRow];
		}
		else
		{
			NSValue *connectorInfoObject = [connectorInfoArray objectAtIndex:dragRow];
			[connectorInfoArray removeObjectAtIndex:dragRow];
			[connectorInfoArray insertObject:connectorInfoObject atIndex:row];
		}
	
		ConnectorInfoICL connectorInfoSource[3];
		
		for (int i = 0; i < 3; i++)
		{
			NSValue *connectorInfoObject = [connectorInfoArray objectAtIndex:i];
			
			ConnectorInfoICL *connectorInfo = NULL;
			
			[connectorInfoObject getValue:&connectorInfo];
			
			connectorInfoSource[i] = *connectorInfo;
		}
		
		for (int i = 0; i < 3; i++)
		{
			ConnectorInfoICL *connectorInfoDest = NULL;
			
			if (![self getConnectorInfoICL:&connectorInfoDest index:i modified:true])
				continue;
			
			*connectorInfoDest = connectorInfoSource[i];
			
			/* uint32_t index, busID, pipe;
			ConnectorType type;
			ConnectorFlags flags;
			[self getConnectorInfo:i Index:&index BusID:&busID Pipe:&pipe Type:&type Flags:&flags];
			
			NSLog(@"Index: %d BusID: 0x%02x Pipe: %d Type: %d Flags: %08x", index, busID, pipe, type, flags); */
		}
	}
	else
	{
		NSMutableArray *connectorInfoArray = [NSMutableArray array];
		
		for (int i = 0; i < 4; i++)
		{
			ConnectorInfo *connectorInfo = NULL;
			
			if (![self getConnectorInfo:&connectorInfo index:i modified:true])
				continue;
			
			NSValue *connectorInfoObject = [NSValue valueWithPointer:connectorInfo];
			
			[connectorInfoArray addObject:connectorInfoObject];
		}
		
		if (dragRow < row)
		{
			NSValue *connectorInfoObject = [connectorInfoArray objectAtIndex:dragRow];
			[connectorInfoArray insertObject:connectorInfoObject atIndex:row];
			[connectorInfoArray removeObjectAtIndex:dragRow];
		}
		else
		{
			NSValue *connectorInfoObject = [connectorInfoArray objectAtIndex:dragRow];
			[connectorInfoArray removeObjectAtIndex:dragRow];
			[connectorInfoArray insertObject:connectorInfoObject atIndex:row];
		}
		
		ConnectorInfo connectorInfoSource[4];
		
		for (int i = 0; i < 4; i++)
		{
			NSValue *connectorInfoObject = [connectorInfoArray objectAtIndex:i];
			
			ConnectorInfo *connectorInfo = NULL;
			
			[connectorInfoObject getValue:&connectorInfo];
			
			connectorInfoSource[i] = *connectorInfo;
		}
		
		for (int i = 0; i < 4; i++)
		{
			ConnectorInfo *connectorInfoDest = NULL;

			if (![self getConnectorInfo:&connectorInfoDest index:i modified:true])
				continue;
			
			*connectorInfoDest = connectorInfoSource[i];
			
			/* uint32_t index, busID, pipe;
			ConnectorType type;
			ConnectorFlags flags;
			[self getConnectorInfo:i Index:&index BusID:&busID Pipe:&pipe Type:&type Flags:&flags];
			
			NSLog(@"Index: %d BusID: 0x%02x Pipe: %d Type: %d Flags: %08x", index, busID, pipe, type, flags); */
		}
	}
	
	[_connectorInfoTableView reloadData];
}

- (bool) isConnectorHeadless
{
	NSInteger intelGen = [_intelGenComboBox indexOfSelectedItem];
	NSInteger platformIDIndex = [_platformIDComboBox indexOfSelectedItem];
	
	if (intelGen == -1 || platformIDIndex == -1)
		return false;
	
	if (IS_ICELAKE(intelGen))
	{
		for (int i = 0; i < 3; i++)
		{
			ConnectorInfoICL *connectorInfo;
			
			if (![self getConnectorInfoICL:&connectorInfo index:i modified:false])
				continue;
			
			if ((connectorInfo->index != -1 && connectorInfo->index != 0) || connectorInfo->busID != 0 || connectorInfo->pipe != 0 || connectorInfo->type != ConnectorDummy || (connectorInfo->flags.value != 0x20 && connectorInfo->flags.value != 0x40))
				return false;
		}
	}
	else
	{
		for (int i = 0; i < 4; i++)
		{
			ConnectorInfo *connectorInfo = NULL;
			
			if (![self getConnectorInfo:&connectorInfo index:i modified:false])
				continue;
			
			if ((connectorInfo->index != -1 && connectorInfo->index != 0) || connectorInfo->busID != 0 || connectorInfo->pipe != 0 || connectorInfo->type != ConnectorDummy || (connectorInfo->flags.value != 0x20 && connectorInfo->flags.value != 0x40))
				return false;
		}
	}
	
	return true;
}

- (void) getConnectorInfo:(uint32_t)connectorIndex Index:(uint32_t *)index BusID:(uint32_t *)busID Pipe:(uint32_t *)pipe Type:(ConnectorType *)type Flags:(ConnectorFlags *)flags
{
	NSInteger intelGen = [_intelGenComboBox indexOfSelectedItem];
	NSInteger platformIDIndex = [_platformIDComboBox indexOfSelectedItem];
	
	if (intelGen == -1 || platformIDIndex == -1)
		return;
	
	if (IS_ICELAKE(intelGen))
	{
		ConnectorInfoICL *connectorInfo = NULL;
		
		if ([self getConnectorInfoICL:&connectorInfo index:connectorIndex modified:true])
		{
			*index = connectorInfo->index;
			*busID = connectorInfo->busID;
			*pipe = connectorInfo->pipe;
			*type = connectorInfo->type;
			*flags = connectorInfo->flags;
		}
	}
	else
	{
		ConnectorInfo *connectorInfo = NULL;
		
		if ([self getConnectorInfo:&connectorInfo index:connectorIndex modified:true])
		{
			*index = connectorInfo->index;
			*busID = connectorInfo->busID;
			*pipe = connectorInfo->pipe;
			*type = connectorInfo->type;
			*flags = connectorInfo->flags;
		}
	}
}

- (void) populateConnectorFlagsList
{
	[_connectorFlagsArray removeAllObjects];
	
	NSInteger intelGen = [_intelGenComboBox indexOfSelectedItem];
	NSInteger platformIDIndex = [_platformIDComboBox indexOfSelectedItem];
	
	if (intelGen == -1 || platformIDIndex == -1)
		return;
	
	NSInteger row = [_connectorInfoTableView selectedRow];
	
	if (IS_ICELAKE(intelGen))
	{
		ConnectorInfoICL *connectorInfo = NULL;
		
		if ([self getConnectorInfoICL:&connectorInfo index:row modified:true])
			[self populateConnectorFlags:connectorInfo->flags];
	}
	else
	{
		ConnectorInfo *connectorInfo = NULL;
		
		if ([self getConnectorInfo:&connectorInfo index:row modified:true])
			[self populateConnectorFlags:connectorInfo->flags];
	}

	[_connectorFlagsTableView reloadData];
}

- (void) updateScreens:(NSNotification*)notification
{
	[self updatePCIIDs];
	[self refreshDisplays];
	[self updateSystemInfo];
	[self updateFramebufferList];
}

- (bool) doesDisplayPortMatchIndex:(uint32_t)index port:(uint32_t)port
{
	NSInteger intelGen = [_intelGenComboBox indexOfSelectedItem];
	
	if (intelGen == -1)
		return false;
	
	int indexOffset = (intelGen == IGSandyBridge || intelGen == IGIvyBridge ? 3 : 4);
	
	if (index == 0 && port == 0)
		return true;
	
	if (index != 0 && index + indexOffset == port)
		return true;
	
	return false;
}

- (IBAction)generateAudioCodecsInfo:(id)sender
{
	NSOpenPanel *openPanel = [NSOpenPanel openPanel];
	[openPanel setCanChooseFiles:NO];
	[openPanel setAllowsMultipleSelection:NO];
	[openPanel setCanChooseDirectories:YES];
	[openPanel setNameFieldStringValue:@"Resources"];
	[openPanel setMessage:GetLocalizedString(@"Select AppleALC Resources Folder")];
	
	[openPanel beginSheetModalForWindow:_window completionHandler:^(NSModalResponse returnCode)
	 {
		 [NSApp stopModalWithCode:returnCode];
	 }];
	
	if ([NSApp runModalForWindow:_window] != NSOKButton)
		return;
	
	NSMutableArray *codecArray = [NSMutableArray array];
	
	for (NSURL *url in [openPanel URLs])
	{
		NSFileManager *fileManager = [[NSFileManager alloc] init];
		NSDirectoryEnumerator *directoryEnumerator = [fileManager enumeratorAtURL:url
													   includingPropertiesForKeys:@[NSURLNameKey, NSURLIsDirectoryKey]
																		  options:NSDirectoryEnumerationSkipsHiddenFiles | NSDirectoryEnumerationSkipsSubdirectoryDescendants
																	 errorHandler:nil];
		
		if (directoryEnumerator != nil)
		{
			for (NSURL *url in directoryEnumerator)
			{
				NSNumber *isDirectory;
				[url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:NULL];
				
				if (![isDirectory boolValue])
					continue;
				
				NSString *filePath = [[url path] stringByAppendingPathComponent:@"Info.plist"];
				
				if (![fileManager fileExistsAtPath:filePath])
					continue;
				
				NSDictionary *propertyDictionary = [NSDictionary dictionaryWithContentsOfFile:filePath];
				NSString *vendor = [propertyDictionary objectForKey:@"Vendor"];
				NSNumber *vendorID = [_audioVendorsDictionary objectForKey:vendor];
				NSNumber *codecID = [propertyDictionary objectForKey:@"CodecID"];
				NSString *codecName = [propertyDictionary objectForKey:@"CodecName"];
				NSDictionary *fileDictionary = [propertyDictionary objectForKey:@"Files"];
				NSArray *revisionsArray = [propertyDictionary objectForKey:@"Revisions"];
				NSArray *patchesArray = [propertyDictionary objectForKey:@"Patches"];
				NSArray *layoutArray = [fileDictionary objectForKey:@"Layouts"];
				uint32_t minKernel = 255;
				uint32_t maxKernel = 0;
				
				if (codecName == nil)
					continue;
				
				NSMutableDictionary *codecDictionary = [NSMutableDictionary dictionary];
				
				[codecDictionary setObject:codecName forKey:@"CodecName"];
				[codecDictionary setObject:[NSNumber numberWithUnsignedInt:(([vendorID unsignedIntValue] << 16) | ([codecID unsignedIntValue] & 0xFFFF))] forKey:@"CodecID"];
				
				NSMutableArray *layoutIDArray = [NSMutableArray array];
				NSMutableArray *revisionArray = [NSMutableArray array];
				
				for (NSDictionary *layoutDictionary in layoutArray)
					[layoutIDArray addObject:[layoutDictionary objectForKey:@"Id"]];
				
				for (NSNumber *revisionNumber in revisionsArray)
					[revisionArray addObject:[NSString stringWithFormat:@"0x%06X", [revisionNumber unsignedIntValue]]];
				
				for (NSDictionary *patchDictionary in patchesArray)
				{
					minKernel = MIN(minKernel, [[patchDictionary objectForKey:@"MinKernel"] intValue]);
					maxKernel = MAX(maxKernel, [[patchDictionary objectForKey:@"MaxKernel"] intValue]);
				}
				
				[codecDictionary setObject:layoutIDArray forKey:@"LayoutIDs"];
				[codecDictionary setObject:revisionArray forKey:@"Revisions"];
				[codecDictionary setObject:@(minKernel) forKey:@"MinKernel"];
				[codecDictionary setObject:@(maxKernel) forKey:@"MaxKernel"];
				
				[codecArray addObject:codecDictionary];
			}
		}
		
		[fileManager release];
		
		break;
	}
	
	if (codecArray.count == 0)
		return;
	
	NSSavePanel *savePanel = [NSSavePanel savePanel];
	[savePanel setNameFieldStringValue:@"Codecs.plist"];
	[savePanel setTitle:GetLocalizedString(@"Save Audio Codecs Info")];
	
	[savePanel beginSheetModalForWindow:_window completionHandler:^(NSInteger result)
	 {
		 if (result == NSFileHandlingPanelOKButton)
			 [codecArray writeToFile:savePanel.URL.path atomically:YES];
	 }];
}

- (void)updateAudioCodecInfo
{
	NSBundle *mainBundle = [NSBundle mainBundle];	
	NSString *filePath = nil;
	
	if (!(filePath = [mainBundle pathForResource:@"Codecs" ofType:@"plist" inDirectory:@"Audio"]))
		return;

	NSArray *codecArray = [NSArray arrayWithContentsOfFile:filePath];
	
	for (NSDictionary *codecDictionary in codecArray)
	{
		NSString *codecName = [codecDictionary objectForKey:@"CodecName"];
		NSNumber *codecID = [codecDictionary objectForKey:@"CodecID"];
		NSMutableArray *layoutIDArray = [codecDictionary objectForKey:@"LayoutIDs"];
		NSMutableArray *revisionArray = [codecDictionary objectForKey:@"Revisions"];
		NSNumber *minKernel = [codecDictionary objectForKey:@"MinKernel"];
		NSNumber *maxKernel = [codecDictionary objectForKey:@"MaxKernel"];
		
		for (AudioDevice *audioDevice in _audioDevicesArray)
		{
			if ([codecID unsignedIntValue] != audioDevice.codecID)
				continue;
			
			audioDevice.codecName = codecName;
			audioDevice.layoutIDArray = layoutIDArray;
			audioDevice.revisionArray = revisionArray;
			audioDevice.minKernel = [minKernel unsignedIntValue];
			audioDevice.maxKernel = [maxKernel unsignedIntValue];
		}
	}
}

- (void)updateAudioInfo
{
	NSInteger selectedRow = [_audioDevicesTableView1 selectedRow];
	
	if (selectedRow == -1)
		return;
	
	AudioDevice *audioDevice = _audioDevicesArray[selectedRow];
	
	uint32_t newDeviceID = 0;
	NSNumber *vendorID = [NSNumber numberWithInt:audioDevice.deviceID >> 16];
	NSNumber *deviceID = [NSNumber numberWithInt:audioDevice.deviceID & 0xFFFF];
	NSNumber *subVendorID = [NSNumber numberWithInt:audioDevice.subDeviceID >> 16];
	NSNumber *subDeviceID = [NSNumber numberWithInt:audioDevice.subDeviceID & 0xFFFF];
	NSNumber *audioVendorID = [NSNumber numberWithInt:audioDevice.audioDeviceModelID >> 16];
	NSNumber *audioDeviceID = [NSNumber numberWithInt:audioDevice.audioDeviceModelID & 0xFFFF];
	
	bool needsSpoof = [self spoofAudioDeviceID:audioDevice.deviceID newDeviceID:&newDeviceID];

	[_audioInfoArray removeAllObjects];
	
	[self addToList:_audioInfoArray name:@"Class" value:audioDevice.deviceClass];
	
	[self addToList:_audioInfoArray name:@"Vendor" value:[NSString stringWithFormat:@"%@ (0x%04X)", audioDevice.vendorName, [vendorID unsignedIntValue]]];
	[self addToList:_audioInfoArray name:@"Device" value:[NSString stringWithFormat:@"%@ (0x%04X)%@", audioDevice.deviceName, [deviceID unsignedIntValue], needsSpoof ? @"*" : @""]];
	
	if (needsSpoof)
		[self addToList:_audioInfoArray name:@"" value:[NSString stringWithFormat:@"* %@", GetLocalizedString(@"You may require Spoof Audio Device ID")]];
	
	[self addToList:_audioInfoArray name:@"Sub Vendor" value:[NSString stringWithFormat:@"%@ (0x%04X)", audioDevice.subVendorName, [subVendorID unsignedIntValue]]];
	[self addToList:_audioInfoArray name:@"Sub Device" value:[NSString stringWithFormat:@"%@ (0x%04X)", audioDevice.subDeviceName, [subDeviceID unsignedIntValue]]];
	
	if (audioDevice.audioDeviceModelID != 0)
	{
		[self addToList:_audioInfoArray name:@"Audio Vendor" value:[NSString stringWithFormat:@"%@ (0x%04X)", audioDevice.audioDeviceManufacturerName, [audioVendorID unsignedIntValue]]];
		[self addToList:_audioInfoArray name:@"Audio Device" value:[NSString stringWithFormat:@"%@ (0x%04X)", audioDevice.audioDeviceName, [audioDeviceID unsignedIntValue]]];
	}
	
	if (audioDevice.codecID != 0)
	{
		[self addToList:_audioInfoArray name:@"Codec Vendor" value:[NSString stringWithFormat:@"%@ (0x%04X)", audioDevice.codecVendorName, audioDevice.codecID >> 16]];
		[self addToList:_audioInfoArray name:@"Codec Name" value:[NSString stringWithFormat:@"%@ (0x%04X)", audioDevice.codecName, audioDevice.codecID & 0xFFFF]];
		
		if ([self isAppleHDAAudioDevice:audioDevice])
		{
			[self addToList:_audioInfoArray name:@"ALC Layout ID" value:[NSString stringWithFormat:@"%d", _alcLayoutID]];
			[self addToList:_audioInfoArray name:@"Revisions" value:audioDevice.revisionArray != nil ? [audioDevice.revisionArray componentsJoinedByString:@" "] : @""];
			[self addToList:_audioInfoArray name:@"Min Kernel" value:[NSString stringWithFormat:@"%d", audioDevice.minKernel]];
			[self addToList:_audioInfoArray name:@"Max Kernel" value:[NSString stringWithFormat:@"%d", audioDevice.maxKernel]];
		}
	}
	
	NSMutableDictionary *hdaConfigDefaultDictionary = audioDevice.hdaConfigDefaultDictionary;
	
	// AFGLowPowerState"=<03000000>,"CodecID"=283902517,"ConfigData"=<01470c02>,"FuncGroup"=1,"Codec"="vusun123 - Realtek ALC235 for Lenovo Legion Y520","WakeVerbReinit"=Yes,"LayoutID"=7,"BootConfigData"=<01271c4001271d0001271ea001271fb001471c1001471d0001471e1701471f9001470c0201971c3001971d1001971e8101971f0002171c6002171d1002171e2102171f00>
	
	if (hdaConfigDefaultDictionary != nil)
	{
		NSData *afgLowPowerState = [hdaConfigDefaultDictionary objectForKey:@"AFGLowPowerState"];
		NSNumber *codecID = [hdaConfigDefaultDictionary objectForKey:@"CodecID"];
		NSData *configData = [hdaConfigDefaultDictionary objectForKey:@"ConfigData"];
		NSNumber *funcGroup = [hdaConfigDefaultDictionary objectForKey:@"FuncGroup"];
		NSString *codec = [hdaConfigDefaultDictionary objectForKey:@"Codec"];
		NSNumber *wakeVerbReinit = [hdaConfigDefaultDictionary objectForKey:@"WakeVerbReinit"];
		NSNumber *layoutID = [hdaConfigDefaultDictionary objectForKey:@"LayoutID"];
		NSData *bootConfigData = [hdaConfigDefaultDictionary objectForKey:@"BootConfigData"];
		
		if (afgLowPowerState != nil)
			[self addToList:_audioInfoArray name:@"AFG Low Power State" value:getByteStringClassic(afgLowPowerState)];
		
		if (codecID != nil)
			[self addToList:_audioInfoArray name:@"Codec ID" value:[NSString stringWithFormat:@"0x%04X", [codecID unsignedIntValue]]];
		
		if (configData != nil)
			[self addToList:_audioInfoArray name:@"Config Data" value:getByteStringClassic(configData)];
		
		if (funcGroup != nil)
			[self addToList:_audioInfoArray name:@"Func Group" value:[NSString stringWithFormat:@"%d", [funcGroup unsignedIntValue]]];
		
		if (codec != nil)
			[self addToList:_audioInfoArray name:@"Codec" value:codec];
		
		if (wakeVerbReinit != nil)
			[self addToList:_audioInfoArray name:@"Wake Verb Reinit" value:GetLocalizedString([wakeVerbReinit boolValue] ? @"Yes" : @"No")];

		if (layoutID != nil)
			[self addToList:_audioInfoArray name:@"Layout ID" value:[NSString stringWithFormat:@"%d", [layoutID unsignedIntValue]]];
		
		if (bootConfigData != nil)
			[self addToList:_audioInfoArray name:@"Boot Config Data" value:getByteStringClassic(bootConfigData)];
	}

	[_audioInfoTableView reloadData];
}

- (void)updatePinConfiguration
{
	[_nodeArray removeAllObjects];
	
	NSInteger selectedRow = [_audioDevicesTableView1 selectedRow];
	
	if (selectedRow == -1)
		return;
	
	AudioDevice *audioDevice = _audioDevicesArray[selectedRow];
	NSMutableDictionary *hdaConfigDefaultDictionary = audioDevice.hdaConfigDefaultDictionary;
	
	if (hdaConfigDefaultDictionary != nil)
	{
		NSData *bootConfigData = [hdaConfigDefaultDictionary objectForKey:@"BootConfigData"];
		uint8_t *configDataBytes = (uint8_t *)[bootConfigData bytes];
		
		for (int i = 0; i < [bootConfigData length] / 4; i++)
		{
			uint32_t verb = getReverseBytes(*((uint32_t *)(&configDataBytes[i * 4])));
			//_codecAddress = (verb >> 28) & 0xF;
			uint8_t nid = (verb >> 20) & 0xFF;
			uint32_t command = (verb >> 8) & 0xFFF;
			uint8_t data = verb & 0xFF;
			
			AudioNode *audioNode = nil;
			
			for (AudioNode *findAudioNode in _nodeArray)
			{
				if ([findAudioNode nid] == nid)
					audioNode = findAudioNode;
			}
			
			if (!audioNode)
			{
				audioNode = [[AudioNode alloc] initWithNid:nid];
				[_nodeArray addObject:audioNode];
				[audioNode release];
			}
			
			if (command == 0x70C)
				[audioNode setEapd:data];
			else if ((command >> 4) == 0x71)
				[audioNode updatePinCommand:command data:data];
		}
	}
	
	[_pinConfigurationOutlineView reloadData];
}

- (void) populateDisplayInfo
{
	[_displayInfoArray removeAllObjects];
	
	NSInteger connectorRow = [_connectorInfoTableView selectedRow];
	
	if (connectorRow == -1)
		return;
	
	uint32_t index, busID, pipe;
	ConnectorType type;
	ConnectorFlags flags;
	[self getConnectorInfo:(uint32_t)connectorRow Index:&index BusID:&busID Pipe:&pipe Type:&type Flags:&flags];
	
	if (index == -1)
		return;

	for (Display *display in _displaysArray)
	{
		uint32_t videoDeviceID = (display.videoID >> 16);
		uint32_t videoVendorID = display.videoID & 0xFFFF;
		
		if (videoVendorID != VEN_INTEL_ID)
			continue;
		
		if (_settings.ApplyCurrentPatches)
		{
			if (![self doesDisplayPortMatchIndex:index port:display.port])
				continue;
		}
		else
			if ((uint32_t)connectorRow != display.index)
				continue;
		
		NSString *vendorName = nil, *deviceName = nil;
		[self getPCIDeviceInfo:@(videoVendorID) deviceID:@(videoDeviceID) vendorName:&vendorName deviceName:&deviceName];
		[self addToList:_displayInfoArray name:@"Name" value:display.name];
		[self addToList:_displayInfoArray name:@"Vendor ID" value:[NSString stringWithFormat:@"0x%04X", display.vendorIDOverride]];
		[self addToList:_displayInfoArray name:@"Product ID" value:[NSString stringWithFormat:@"0x%04X", display.productIDOverride]];
		[self addToList:_displayInfoArray name:@"Serial No." value:[NSString stringWithFormat:@"0x%04X", display.serialNumber]];
		[self addToList:_displayInfoArray name:@"Port" value:[NSString stringWithFormat:@"0x%02X", display.port]];
		[self addToList:_displayInfoArray name:@"Internal" value:display.isInternal ? GetLocalizedString(@"Yes") : GetLocalizedString(@"No")];
		[self addToList:_displayInfoArray name:@"EDID" value:getByteStringClassic(display.eDID)];
		[self addToList:_displayInfoArray name:@"GPU Name" value:deviceName];
		[self addToList:_displayInfoArray name:@"GPU Device ID" value:[NSString stringWithFormat:@"0x%08X", display.videoID]];
	}
	
	[_displayInfoTableView reloadData];
}

- (void) populateFramebufferList
{
	[self clearAll];
	
	NSInteger intelGen = [_intelGenComboBox indexOfSelectedItem];
	
	if (intelGen == -1)
		return;
	
	NSString *intelGenString = [_intelGenComboBox objectValueOfSelectedItem];
	NSMutableArray *platformIDArray = [NSMutableArray array];
	
	if (_importIORegNativeMenuItem.state)
	{
		NSData *nativePlatformTable = nil;
		
		if (getPlatformTableNative(&nativePlatformTable))
			readFramebuffer(static_cast<const uint8_t *>([nativePlatformTable bytes]), [nativePlatformTable length], (IntelGen &)intelGen, &_originalFramebufferList, &_modifiedFramebufferList, _framebufferSize, _framebufferCount);
	}
	else if (_importIORegPatchedMenuItem.state)
	{
		NSData *nativePlatformTable = nil, *patchedPlatformTable = nil;
		
		if (getPlatformTableNative(&nativePlatformTable) && getPlatformTablePatched(&patchedPlatformTable))
		{
			if (readFramebuffer(static_cast<const uint8_t *>([nativePlatformTable bytes]), [nativePlatformTable length], (IntelGen &)intelGen, &_originalFramebufferList, &_modifiedFramebufferList, _framebufferSize, _framebufferCount))
				memcpy(_modifiedFramebufferList, [patchedPlatformTable bytes], MIN(_framebufferSize * _framebufferCount, [patchedPlatformTable length]));
		}
	}
	else
	{
		if (_macOS_10_13_6_MenuItem.state)
		{
			NSBundle *mainBundle = [NSBundle mainBundle];
			
			_fileName = [mainBundle pathForResource:intelGenString ofType:@"bin" inDirectory:@"Framebuffer/macOS 10.13.6"];
			
			if (intelGen > IGCoffeeLake)
				_fileName = nil;
		}
		else if (_macOS_10_14_MenuItem.state)
		{
			NSBundle *mainBundle = [NSBundle mainBundle];
			
			_fileName = [mainBundle pathForResource:intelGenString ofType:@"bin" inDirectory:@"Framebuffer/macOS 10.14"];
		}

		if (_fileName != nil)
			readFramebuffer([_fileName cStringUsingEncoding:NSUTF8StringEncoding], (IntelGen &)intelGen, &_originalFramebufferList, &_modifiedFramebufferList, _framebufferSize, _framebufferCount);
		else
		{
			NSString *fbDriverName = [_fbDriversDictionary objectForKey:g_fbNameArray[intelGen]];
			NSString *fbDriverPath = [NSString stringWithFormat:@"/System/Library/Extensions/%@.kext/Contents/MacOS/%@", fbDriverName, fbDriverName];
			readFramebuffer([fbDriverPath cStringUsingEncoding:NSUTF8StringEncoding], (IntelGen &)intelGen, &_originalFramebufferList, &_modifiedFramebufferList, _framebufferSize, _framebufferCount);
		}
	}
	
	if (intelGen == IGSandyBridge)
	{
		// https://github.com/filchermcurr/Ramblings-of-a-hackintosher/blob/master/ig-platform-id.md
		for (int i = 0; i < 9; i++)
		{
			uint32_t framebufferID = g_fbSandyBridge[i];
			[platformIDArray addObject:[NSString stringWithFormat:@"0x%08X", framebufferID]];
		}
	}
	else
	{
		for (int i = 0; i < _framebufferCount; i++)
		{
			uint32_t framebufferID = *reinterpret_cast<uint32_t *>(static_cast<uint8_t *>(_originalFramebufferList) + _framebufferSize * i);
			[platformIDArray addObject:[NSString stringWithFormat:@"0x%08X", framebufferID]];
		}
	}
	
	[_intelGenComboBox setDelegate:nil];
	[_platformIDComboBox setDelegate:nil];
	
	if ([_intelGenComboBox indexOfSelectedItem] != intelGen)
		[_intelGenComboBox selectItemAtIndex:intelGen];
	
	[_platformIDComboBox removeAllItems];
	[_platformIDComboBox deselectItemAtIndex:0];
	
	for (int i = 0; i < _framebufferCount && i < [platformIDArray count]; i++)
		[_platformIDComboBox addItemWithObjectValue:platformIDArray[i]];
	
	if ([_platformIDComboBox numberOfItems] > 0)
	{
		if ([_platformIDComboBox indexOfItemWithObjectValue:_settings.PlatformID] != NSNotFound)
			[_platformIDComboBox selectItemWithObjectValue:_settings.PlatformID];
		else
			[_platformIDComboBox selectItemAtIndex:0];
	}
	
	[_intelGenComboBox setDelegate:self];
	[_platformIDComboBox setDelegate:self];
	
	[self updateInjectDeviceIDComboBox];
	
	//NSLog(@"Address Count: %d (Found %d)", [_platformIDComboBox numberOfItems], _originalFramebufferList.size());
	
	[self updateFramebufferList];
}

- (void)createPlatformIDArray
{
	NSBundle *mainBundle = [NSBundle mainBundle];
	NSString *filePath = nil;
	
	_intelPlatformIDsDictionary_10_13_6 = [[NSMutableDictionary dictionary] retain];
	_intelPlatformIDsDictionary_10_14 = [[NSMutableDictionary dictionary] retain];
	
	NSDictionary *intelPlatformIDsDictionary_10_13_6 = [NSDictionary dictionary];
	NSDictionary *intelPlatformIDsDictionary_10_14 = [NSDictionary dictionary];
	
	if ((filePath = [mainBundle pathForResource:@"PlatformIDs" ofType:@"plist" inDirectory:@"Framebuffer/macOS 10.13.6"]))
		intelPlatformIDsDictionary_10_13_6 = [[NSDictionary dictionaryWithContentsOfFile:filePath] retain];
	
	if ((filePath = [mainBundle pathForResource:@"PlatformIDs" ofType:@"plist" inDirectory:@"Framebuffer/macOS 10.14"]))
		intelPlatformIDsDictionary_10_14 = [[NSDictionary dictionaryWithContentsOfFile:filePath] retain];
	
	for (int i = 0; i < IGCount; i++)
	{
		NSString *intelGenString = g_fbNameArray[i];
		NSString *platformIDString_10_13_6 = [intelPlatformIDsDictionary_10_13_6 objectForKey:intelGenString];
		NSString *platformIDString_10_14 = [intelPlatformIDsDictionary_10_14 objectForKey:intelGenString];
		NSMutableArray *platformIDArray_10_13_6 = getHexArrayFromString(platformIDString_10_13_6);
		NSMutableArray *platformIDArray_10_14 = getHexArrayFromString(platformIDString_10_14);
		
		[_intelPlatformIDsDictionary_10_13_6 setObject:platformIDArray_10_13_6 forKey:intelGenString];
		[_intelPlatformIDsDictionary_10_14 setObject:platformIDArray_10_14 forKey:intelGenString];
	}
}

- (bool)getIntelGenMatch:(uint32_t)platformID intelGen:(NSString **)intelGen
{
	for (NSString *intelGenString in _intelPlatformIDsDictionary_10_14.allKeys)
	{
		NSMutableArray *platformIDArray = [_intelPlatformIDsDictionary_10_14 objectForKey:intelGenString];
		
		for (NSNumber *platformIDNumber in platformIDArray)
		{
			if ([platformIDNumber unsignedIntValue] == platformID)
			{
				*intelGen = intelGenString;
				
				return true;
			}
		}
	}
	
	for (NSString *intelGenString in _intelPlatformIDsDictionary_10_13_6.allKeys)
	{
		NSMutableArray *platformIDArray = [_intelPlatformIDsDictionary_10_13_6 objectForKey:intelGenString];
		
		for (NSNumber *platformIDNumber in platformIDArray)
		{
			if ([platformIDNumber unsignedIntValue] == platformID)
			{
				*intelGen = intelGenString;
				
				return true;
			}
		}
	}
	
	return false;
}

- (void) setPlatformID:(uint32_t)platformID
{
	NSString *intelGenString = nil;
	
	if (![self getIntelGenMatch:platformID intelGen:&intelGenString])
		return;
	
	_settings.IntelGen = intelGenString;
	_settings.PlatformID = [[NSString stringWithFormat:@"0x%08X", platformID] retain];
	
	[_intelGenComboBox selectItemWithObjectValue:_settings.IntelGen];
	[_platformIDComboBox selectItemWithObjectValue:_settings.PlatformID];
}

- (void) updateInjectDeviceIDComboBox
{
	[_injectDeviceIDComboBox removeAllItems];
	
	NSMutableArray *deviceIDArray = nil;
	uint32_t deviceIDIndex = 0;
	
	if (![self getDeviceIDArray:&deviceIDArray])
		return;
	
	for (int i = 0; i < [deviceIDArray count]; i++)
	{
		uint32_t deviceID = (uint32_t)[[deviceIDArray objectAtIndex:i] integerValue];
		
		if (deviceID == _gpuDeviceID)
			deviceIDIndex = i;
		
		NSString *gpuModel = [_intelGPUsDictionary objectForKey:[NSString stringWithFormat:@"0x%04X", deviceID]];
		
		if (gpuModel == nil)
			gpuModel = @"???";
		
		[_injectDeviceIDComboBox addItemWithObjectValue:[NSString stringWithFormat:@"0x%04X: %@", deviceID, gpuModel]];
	}
	
	[_injectDeviceIDComboBox selectItemAtIndex:deviceIDIndex];
}

- (void) updateFramebufferList
{
	if (_settings.ApplyCurrentPatches)
		[self applyCurrentPatches];
	
	[self applyAutoPatching];
	
	[self populateFramebufferInfoList];
	[self populateConnectorFlagsList];
	
	[_connectorInfoTableView reloadData];
	[_connectorFlagsTableView reloadData];
}

- (void) clearAll
{
	if (_originalFramebufferList != nil)
	{
		delete[] _originalFramebufferList;
		_originalFramebufferList = nil;
	}
	
	if (_modifiedFramebufferList != nil)
	{
		delete[] _modifiedFramebufferList;
		_modifiedFramebufferList = nil;
	}
	
	[_framebufferInfoArray removeAllObjects];
	[_framebufferFlagsArray removeAllObjects];
	[_connectorFlagsArray removeAllObjects];
	
	[_framebufferInfoTableView reloadData];
	[_framebufferFlagsTableView reloadData];
	[_connectorInfoTableView reloadData];
	[_connectorFlagsTableView reloadData];
}

- (void) windowWillClose:(NSNotification *)notification
{
	[self saveSettings];
	[self saveUSBPorts];
	[self saveInstalledKexts];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)theApplication
{
	return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification;
{
	[self saveSettings];
	[self saveUSBPorts];
	[self saveInstalledKexts];
}

- (void)setBootEFI:(NSString *)mediaUUID
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	
	[defaults setObject:mediaUUID forKey:@"EFIBootDeviceUUID"];
	
	[defaults synchronize];
}

- (void)unsetBootEFI
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	
	[defaults removeObjectForKey:@"EFIBootDeviceUUID"];
	
	[defaults synchronize];
}

- (void)resetDefaults
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSDictionary *dictionary = [defaults dictionaryRepresentation];
	
	for (id key in dictionary)
		[defaults removeObjectForKey:key];
	
	[defaults synchronize];
}

- (void)setDefaults
{
	NSString *intelGenString = nil;
	
	[self getIntelGenMatch:_platformID intelGen:&intelGenString];
	
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSDictionary *defaultsDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
										(intelGenString != nil ? intelGenString : @"Coffee Lake"), @"IntelGen",
										[NSString stringWithFormat:@"0x%08X", _platformID], @"PlatformID",
										@NO, @"KextsToPatchHex",
										@NO, @"KextsToPatchBase64",
										@YES, @"DeviceProperties",
										@NO, @"iASLDSLSource",
										@(kBootloaderAutoDetect), @"SelectedBootloader",
										@YES, @"AutoDetectChanges",
										@NO, @"UseAllDataMethod",
										@NO, @"PatchAll",
										@YES, @"PatchConnectors",
										@YES, @"PatchVRAM",
										@YES, @"PatchGraphicDevice",
										@YES, @"PatchAudioDevice",
										@NO, @"PatchPCIDevices",
										@NO, @"PatchEDID",
										@NO, @"DVMTPrealloc32MB",
										@NO, @"VRAM2048MB",
										@NO, @"DisableeGPU",
										@NO, @"EnableHDMI20",
										@NO, @"DPtoHDMI",
										@YES, @"UseIntelHDMI",
										@NO, @"GfxYTileFix",
										@NO, @"HotplugRebootFix",
										@NO, @"HDMIInfiniteLoopFix",
										@NO, @"DPCDMaxLinkRateFix",
										@(2), @"DPCDMaxLinkRate",
										@NO, @"FBPortLimit",
										@(2), @"FBPortCount",
										@NO, @"InjectDeviceID",
										@NO, @"SpoofAudioDeviceID",
										@NO, @"InjectFakeIGPU",
										@NO, @"USBPortLimit",
										@NO, @"ApplyCurrentPatches",
										@(0), @"SelectedAudioDevice",
										@YES, @"ShowInstalledOnly",
										@NO, @"LSPCON_Enable",
										@YES, @"LSPCON_AutoDetect",
										@NO, @"LSPCON_Connector",
										@(0), @"LSPCON_ConnectorIndex",
										@NO, @"LSPCON_PreferredMode",
										@(1), @"LSPCON_PreferredModeIndex",
										@NO, @"AII_EnableHWP",
										@YES, @"AII_LogCStates",
										@YES, @"AII_LogIGPU",
										@YES, @"AII_LogIPGStyle",
										@NO, @"AII_LogIntelRegs",
										@YES, @"AII_LogMSRs",
										nil];
	
	[defaults registerDefaults:defaultsDictionary];
	[defaults synchronize];
}

- (void)loadSettings
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	
	_settings.IntelGen = [defaults stringForKey:@"IntelGen"];
	_settings.PlatformID = [defaults stringForKey:@"PlatformID"];
	_settings.KextsToPatchHex = [defaults boolForKey:@"KextsToPatchHex"];
	_settings.KextsToPatchBase64 = [defaults boolForKey:@"KextsToPatchBase64"];
	_settings.DeviceProperties = [defaults boolForKey:@"DeviceProperties"];
	_settings.iASLDSLSource = [defaults boolForKey:@"iASLDSLSource"];
	_settings.SelectedBootloader = (uint32_t)[defaults integerForKey:@"SelectedBootloader"];
	_settings.AutoDetectChanges = [defaults boolForKey:@"AutoDetectChanges"];
	_settings.UseAllDataMethod = [defaults boolForKey:@"UseAllDataMethod"];
	_settings.PatchAll = [defaults boolForKey:@"PatchAll"];
	_settings.PatchConnectors = [defaults boolForKey:@"PatchConnectors"];
	_settings.PatchVRAM = [defaults boolForKey:@"PatchVRAM"];
	_settings.PatchGraphicDevice = [defaults boolForKey:@"PatchGraphicDevice"];
	_settings.PatchAudioDevice = [defaults boolForKey:@"PatchAudioDevice"];
	_settings.PatchPCIDevices = [defaults boolForKey:@"PatchPCIDevices"];
	_settings.PatchEDID = [defaults boolForKey:@"PatchEDID"];
	_settings.DVMTPrealloc32MB = [defaults boolForKey:@"DVMTPrealloc32MB"];
	_settings.VRAM2048MB = [defaults boolForKey:@"VRAM2048MB"];
	_settings.DisableeGPU = [defaults boolForKey:@"DisableeGPU"];
	_settings.EnableHDMI20 = [defaults boolForKey:@"EnableHDMI20"];
	_settings.DPtoHDMI = [defaults boolForKey:@"DPtoHDMI"];
	_settings.UseIntelHDMI = [defaults boolForKey:@"UseIntelHDMI"];
	_settings.GfxYTileFix = [defaults boolForKey:@"GfxYTileFix"];
	_settings.HotplugRebootFix = [defaults boolForKey:@"HotplugRebootFix"];
	_settings.HDMIInfiniteLoopFix = [defaults boolForKey:@"HDMIInfiniteLoopFix"];
	_settings.DPCDMaxLinkRateFix = [defaults boolForKey:@"DPCDMaxLinkRateFix"];
	_settings.DPCDMaxLinkRate = (uint32_t)[defaults integerForKey:@"DPCDMaxLinkRate"];
	_settings.FBPortLimit = [defaults boolForKey:@"FBPortLimit"];
	_settings.FBPortCount = (uint32_t)[defaults integerForKey:@"FBPortCount"];
	_settings.InjectDeviceID = [defaults boolForKey:@"InjectDeviceID"];
	_settings.SpoofAudioDeviceID = [defaults boolForKey:@"SpoofAudioDeviceID"];
	_settings.InjectFakeIGPU = [defaults boolForKey:@"InjectFakeIGPU"];
	_settings.USBPortLimit = [defaults boolForKey:@"USBPortLimit"];
	_settings.ApplyCurrentPatches = [defaults boolForKey:@"ApplyCurrentPatches"];
	_settings.ShowInstalledOnly = [defaults boolForKey:@"ShowInstalledOnly"];
	_settings.LSPCON_Enable = [defaults boolForKey:@"LSPCON_Enable"];
	_settings.LSPCON_AutoDetect = [defaults boolForKey:@"LSPCON_AutoDetect"];
	_settings.LSPCON_Connector = [defaults boolForKey:@"LSPCON_Connector"];
	_settings.LSPCON_ConnectorIndex = (uint32_t)[defaults integerForKey:@"LSPCON_ConnectorIndex"];
	_settings.LSPCON_PreferredMode = [defaults boolForKey:@"LSPCON_PreferredMode"];
	_settings.LSPCON_PreferredModeIndex = (uint32_t)[defaults integerForKey:@"LSPCON_PreferredModeIndex"];
	_settings.AII_EnableHWP = [defaults boolForKey:@"AII_EnableHWP"];
	_settings.AII_LogCStates = [defaults boolForKey:@"AII_LogCStates"];
	_settings.AII_LogIGPU = [defaults boolForKey:@"AII_LogIGPU"];
	_settings.AII_LogIPGStyle = [defaults boolForKey:@"AII_LogIPGStyle"];
	_settings.AII_LogIntelRegs = [defaults boolForKey:@"AII_LogIntelRegs"];
	_settings.AII_LogMSRs = [defaults boolForKey:@"AII_LogMSRs"];
}

- (void)saveSettings
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	
	[defaults setObject:_settings.IntelGen forKey:@"IntelGen"];
	[defaults setObject:_settings.PlatformID forKey:@"PlatformID"];
	[defaults setBool:_settings.KextsToPatchHex forKey:@"KextsToPatchHex"];
	[defaults setBool:_settings.KextsToPatchBase64 forKey:@"KextsToPatchBase64"];
	[defaults setBool:_settings.DeviceProperties forKey:@"DeviceProperties"];
	[defaults setBool:_settings.iASLDSLSource forKey:@"iASLDSLSource"];
	[defaults setInteger:_settings.SelectedBootloader forKey:@"SelectedBootloader"];
	[defaults setBool:_settings.AutoDetectChanges forKey:@"AutoDetectChanges"];
	[defaults setBool:_settings.UseAllDataMethod forKey:@"UseAllDataMethod"];
	[defaults setBool:_settings.PatchAll forKey:@"PatchAll"];
	[defaults setBool:_settings.PatchConnectors forKey:@"PatchConnectors"];
	[defaults setBool:_settings.PatchVRAM forKey:@"PatchVRAM"];
	[defaults setBool:_settings.PatchGraphicDevice forKey:@"PatchGraphicDevice"];
	[defaults setBool:_settings.PatchAudioDevice forKey:@"PatchAudioDevice"];
	[defaults setBool:_settings.PatchPCIDevices forKey:@"PatchPCIDevices"];
	[defaults setBool:_settings.PatchEDID forKey:@"PatchEDID"];
	[defaults setBool:_settings.DVMTPrealloc32MB forKey:@"DVMTPrealloc32MB"];
	[defaults setBool:_settings.VRAM2048MB forKey:@"VRAM2048MB"];
	[defaults setBool:_settings.DisableeGPU forKey:@"DisableeGPU"];
	[defaults setBool:_settings.EnableHDMI20 forKey:@"EnableHDMI20"];
	[defaults setBool:_settings.DPtoHDMI forKey:@"DPtoHDMI"];
	[defaults setBool:_settings.UseIntelHDMI forKey:@"UseIntelHDMI"];
	[defaults setBool:_settings.GfxYTileFix forKey:@"GfxYTileFix"];
	[defaults setBool:_settings.HotplugRebootFix forKey:@"HotplugRebootFix"];
	[defaults setBool:_settings.HDMIInfiniteLoopFix forKey:@"HDMIInfiniteLoopFix"];
	[defaults setBool:_settings.DPCDMaxLinkRateFix forKey:@"DPCDMaxLinkRateFix"];
	[defaults setInteger:_settings.DPCDMaxLinkRate forKey:@"DPCDMaxLinkRate"];
	[defaults setBool:_settings.FBPortLimit forKey:@"FBPortLimit"];
	[defaults setInteger:_settings.FBPortCount forKey:@"FBPortCount"];
	[defaults setBool:_settings.InjectDeviceID forKey:@"InjectDeviceID"];
	[defaults setBool:_settings.USBPortLimit forKey:@"USBPortLimit"];
	[defaults setBool:_settings.SpoofAudioDeviceID forKey:@"SpoofAudioDeviceID"];
	[defaults setBool:_settings.InjectFakeIGPU forKey:@"InjectFakeIGPU"];
	[defaults setBool:_settings.ApplyCurrentPatches forKey:@"ApplyCurrentPatches"];
	[defaults setBool:_settings.ShowInstalledOnly forKey:@"ShowInstalledOnly"];
	[defaults setBool:_settings.LSPCON_Enable forKey:@"LSPCON_Enable"];
	[defaults setBool:_settings.LSPCON_AutoDetect forKey:@"LSPCON_AutoDetect"];
	[defaults setBool:_settings.LSPCON_Connector forKey:@"LSPCON_Connector"];
	[defaults setInteger:_settings.LSPCON_ConnectorIndex forKey:@"LSPCON_ConnectorIndex"];
	[defaults setBool:_settings.LSPCON_PreferredMode forKey:@"LSPCON_PreferredMode"];
	[defaults setInteger:_settings.LSPCON_PreferredModeIndex forKey:@"LSPCON_PreferredModeIndex"];
	[defaults setBool:_settings.AII_EnableHWP forKey:@"AII_EnableHWP"];
	[defaults setBool:_settings.AII_LogCStates forKey:@"AII_LogCStates"];
	[defaults setBool:_settings.AII_LogIGPU forKey:@"AII_LogIGPU"];
	[defaults setBool:_settings.AII_LogIPGStyle forKey:@"AII_LogIPGStyle"];
	[defaults setBool:_settings.AII_LogIntelRegs forKey:@"AII_LogIntelRegs"];
	[defaults setBool:_settings.AII_LogMSRs forKey:@"AII_LogMSRs"];
	
	[defaults synchronize];
}

- (void)comboBoxSelectionDidChange:(NSNotification *)notification
{
	NSComboBox *comboBox = notification.object;
	NSString *identifier = comboBox.identifier;
	
	if ([identifier isEqualToString:@"IntelGen"])
	{
		NSString *intelGenString = [comboBox objectValueOfSelectedItem];
		
		if (intelGenString != nil)
			_settings.IntelGen = intelGenString;
		
		[self populateFramebufferList];
	}
	else if ([identifier isEqualToString:@"PlatformID"])
	{
		NSString *platformIDString = [comboBox objectValueOfSelectedItem];
		
		_settings.PlatformID = [platformIDString retain];
		
		[self populateFramebufferInfoList];
		[_connectorInfoTableView reloadData];
		[_connectorFlagsTableView reloadData];
	}
	else if ([identifier isEqualToString:@"ALCLayoutID"])
	{
		NSString *layoutID = [comboBox objectValueOfSelectedItem];

		_alcLayoutID = [layoutID intValue];
		
		[self updateAudioInfo];
		[self updatePinConfiguration];
	}
}

- (void)getIntegerValuesFromString:(IntConvert *)intConvert
{
	NSScanner *scanner = [NSScanner scannerWithString:intConvert->StringValue];
	[scanner scanHexLongLong:&intConvert->Uint64Value];
	intConvert->Uint32Value = intConvert->Uint64Value & 0xFFFFFFFF;
	intConvert->Uint8Value = intConvert->Uint64Value & 0xFF;
	intConvert->MemoryInBytes = [self parseMemoryString:intConvert->StringValue];
	intConvert->DecimalValue = [intConvert->StringValue intValue];
}

- (void)setFramebufferFlagsWithIndex:(NSInteger)index flags:(FramebufferFlags &)flags value:(bool)value
{
	if (value)
		flags.value |= (1 << index);
	else
		flags.value &= ~(1 << index);
}

- (bool)getConnectorInfoICL:(ConnectorInfoICL **)connectorInfo index:(NSInteger)index modified:(bool)modified
{
	NSInteger intelGen = [_intelGenComboBox indexOfSelectedItem];
	NSInteger platformIDIndex = [_platformIDComboBox indexOfSelectedItem];
	
	if (intelGen == -1 || platformIDIndex == -1)
		return false;
	
	uint8_t *framebufferList = (modified ? _modifiedFramebufferList : _originalFramebufferList);
	
	switch (intelGen)
	{
		case IGIceLakeLP:
			*connectorInfo = &reinterpret_cast<FramebufferICLLP *>(framebufferList)[platformIDIndex].connectors[index];
			return true;
		case IGIceLakeHP:
			*connectorInfo = &reinterpret_cast<FramebufferICLHP *>(framebufferList)[platformIDIndex].connectors[index];
			return true;
	}
	
	return false;
}

- (bool)getConnectorInfo:(ConnectorInfo **)connectorInfo index:(NSInteger)index modified:(bool)modified
{
	NSInteger intelGen = [_intelGenComboBox indexOfSelectedItem];
	NSInteger platformIDIndex = [_platformIDComboBox indexOfSelectedItem];
	
	if (intelGen == -1 || platformIDIndex == -1)
		return false;
	
	uint8_t *framebufferList = (modified ? _modifiedFramebufferList : _originalFramebufferList);
	
	switch (intelGen)
	{
		case IGSandyBridge:
			*connectorInfo = &reinterpret_cast<FramebufferSNB *>(framebufferList)[platformIDIndex].connectors[index];
			return true;
		case IGIvyBridge:
			*connectorInfo = &reinterpret_cast<FramebufferIVB *>(framebufferList)[platformIDIndex].connectors[index];
			return true;
		case IGHaswell:
			*connectorInfo = &reinterpret_cast<FramebufferHSW *>(framebufferList)[platformIDIndex].connectors[index];
			return true;
		case IGBroadwell:
			*connectorInfo = &reinterpret_cast<FramebufferBDW *>(framebufferList)[platformIDIndex].connectors[index];
			return true;
		case IGSkylake:
		case IGKabyLake:
			*connectorInfo = &reinterpret_cast<FramebufferSKL *>(framebufferList)[platformIDIndex].connectors[index];
			return true;
		case IGCoffeeLake:
			*connectorInfo = &reinterpret_cast<FramebufferCFL *>(framebufferList)[platformIDIndex].connectors[index];
			return true;
		case IGCannonLake:
			*connectorInfo = &reinterpret_cast<FramebufferCNL *>(framebufferList)[platformIDIndex].connectors[index];
			return true;
	}
	
	return false;
}

- (void)setConnectorFlags:(uint32_t)index flags:(ConnectorFlags &)flags value:(bool)value
{
	if (value)
		flags.value |= (1 << index);
	else
		flags.value &= ~(1 << index);
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	NSInteger intelGen = [_intelGenComboBox indexOfSelectedItem];
	NSInteger platformIDIndex = [_platformIDComboBox indexOfSelectedItem];

	if (tableView == _generateSerialInfoTableView)
	{
		return [_generateSerialInfoArray count];
	}
	else if (tableView == _modelInfoTableView)
	{
		return [_modelInfoArray count];
	}
	else if (tableView == _selectedFBInfoTableView)
	{
		return [_selectedFBInfoArray count];
	}
	else if (tableView == _currentFBInfoTableView)
	{
		return [_currentFBInfoArray count];
	}
	else if (tableView == _vramInfoTableView)
	{
		return [_vramInfoArray count];
	}
	else if (tableView == _framebufferInfoTableView)
	{
		return [_framebufferInfoArray count];
	}
	else if (tableView == _framebufferFlagsTableView)
	{
		return [_framebufferFlagsArray count];
	}
	else if (tableView == _connectorInfoTableView)
	{
		if (intelGen == -1 || platformIDIndex == -1)
			return 0;
		
		if (intelGen == IGIceLakeLP)
		{
			if (_originalFramebufferList == NULL)
				return 0;
			
			FramebufferICLLP &framebufferICLLP = reinterpret_cast<FramebufferICLLP *>(_originalFramebufferList)[platformIDIndex];
				
			return framebufferICLLP.fPortCount;
		}
		
		return 4;
	}
	else if (tableView == _connectorFlagsTableView)
	{
		return [_connectorFlagsArray count];
	}
	else if (tableView == _displayInfoTableView)
	{
		return [_displayInfoArray count];
	}
	else if (tableView == _bootloaderInfoTableView)
	{
		return [_bootloaderInfoArray count];
	}
	else if (tableView == _bootloaderPatchTableView)
	{
		return [_bootloaderPatchArray count];
	}
	else if (tableView == _nvramTableView)
	{
		return [_nvramDictionary count];
	}
	else if (tableView == _kextsTableView)
	{
		return [(_settings.ShowInstalledOnly ? _installedKextsArray : _kextsArray) count];
	}
	else if (tableView == _usbControllersTableView)
	{
		return [_usbControllersArray count];
	}
	else if (tableView == _usbPortsTableView)
	{
		return [_usbPortsArray count];
	}
	else if (tableView == _audioDevicesTableView1)
	{
		return [_audioDevicesArray count];
	}
	else if (tableView == _audioInfoTableView)
	{
		return [_audioInfoArray count];
	}
	else if (tableView == _efiPartitionsTableView)
	{
		NSMutableArray *efiPartitionsArray = getEfiPartitionsArray(_disksArray);
		
		return [efiPartitionsArray count];
	}
	else if (tableView == _partitionSchemeTableView)
	{
		return [_disksArray count];
	}
	else if (tableView == _pciDevicesTableView)
	{
		return [_pciDevicesArray count];
	}
	else if (tableView == _networkInterfacesTableView)
	{
		return [_networkInterfacesArray count];
	}
	else if (tableView == _bluetoothDevicesTableView)
	{
		return [_bluetoothDevicesArray count];
	}
	else if (tableView == _graphicDevicesTableView)
	{
		return [_graphicDevicesArray count];
	}
	else if (tableView == _audioDevicesTableView2)
	{
		return [_audioDevicesArray count];
	}
	else if (tableView == _storageDevicesTableView)
	{
		return [_storageDevicesArray count];
	}
	else if (tableView == _powerSettingsTableView)
	{
		return [_currentPowerSettings count];
	}
	else if (tableView == _displaysTableView)
	{
		return [_displaysArray count];
	}
	else if (tableView == _resolutionsTableView)
	{
		Display *display;
		
		if (![self getCurrentlySelectedDisplay:&display])
			return 0;
		
		return [display.resolutionsArray count];
	}
	
	return 0;
}

- (NSString *)getToolTip:(NSTableView *)tableView tableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	NSString *identifier = [tableColumn identifier];
	
	if (tableView == _framebufferFlagsTableView)
	{
		for (int i = 0; i < g_framebufferFlagsArray.count; i++)
		{
			if (i != row)
				continue;
			
			NSString *toolTipString = [NSString stringWithFormat:@"TT_%@", g_framebufferFlagsArray[i]];
			
			return GetLocalizedString(toolTipString);
		}
	}
	else if (tableView == _connectorInfoTableView)
	{
		NSUInteger col = [[_connectorInfoTableView tableColumns] indexOfObject:tableColumn];
		NSArray *connectorToolTipArray = @[@"TT_Index", @"TT_BusID", @"TT_Pipe", @"TT_Type", @"TT_Flags"];
		
		for (int i = 0; i < connectorToolTipArray.count; i++)
		{
			if (i != col)
				continue;
			
			return GetLocalizedString(connectorToolTipArray[i]);
		}
	}
	else if (tableView == _connectorFlagsTableView)
	{
		for (int i = 0; i < g_connectorFlagsArray.count; i++)
		{
			if (i != row)
				continue;
			
			NSString *toolTipString = [NSString stringWithFormat:@"TT_%@", g_connectorFlagsArray[i]];
			
			return GetLocalizedString(toolTipString);
		}
	}
	else if (tableView == _bootloaderInfoTableView)
	{
	}
	else if (tableView == _bootloaderPatchTableView)
	{
	}
	else if (tableView == _nvramTableView)
	{
	}
	else if (tableView == _kextsTableView)
	{
	}
	else if (tableView == _usbControllersTableView)
	{
		NSMutableDictionary *usbControllersDictionary = _usbControllersArray[row];
		
		NSNumber *deviceID = [usbControllersDictionary objectForKey:@"DeviceID"];
		NSString *usbRequirements = nil;
		bool hasUsbRequirements = [self getUSBKextRequirements:deviceID usbRequirements:&usbRequirements];
		
		if (!hasUsbRequirements)
			return nil;
		
		return [NSString stringWithFormat:GetLocalizedString(@"You may require %@"), usbRequirements];
	}
	else if (tableView == _usbPortsTableView)
	{
	}
	else if (tableView == _audioDevicesTableView1)
	{
	}
	else if (tableView == _audioInfoTableView)
	{
	}
	else if (tableView == _efiPartitionsTableView)
	{
		NSMutableArray *efiPartitionsArray = getEfiPartitionsArray(_disksArray);
		Disk *disk = efiPartitionsArray[row];
		
		if([identifier isEqualToString:GetLocalizedString(@"Mount")])
			return (disk.isMounted ? GetLocalizedString(@"Unmount") : GetLocalizedString(@"Mount"));
		else if([identifier isEqualToString: GetLocalizedString(@"Open")])
			return (disk.isMounted ?  GetLocalizedString(@"Open") : nil);
	}
	else if (tableView == _partitionSchemeTableView)
	{
	}
	else if (tableView == _pciDevicesTableView)
	{
	}
	else if (tableView == _networkInterfacesTableView)
	{
	}
	else if (tableView == _bluetoothDevicesTableView)
	{
	}
	else if (tableView == _graphicDevicesTableView)
	{
	}
	else if (tableView == _audioDevicesTableView2)
	{
	}
	else if (tableView == _storageDevicesTableView)
	{
	}
	else if (tableView == _powerSettingsTableView)
	{
	}
	else if (tableView == _displaysTableView)
	{
		Display *display = _displaysArray[row];
		
		EDID edid {};
		
		if (display.eDID != nil)
			memcpy(&edid, [display.eDID bytes], min(sizeof(EDID), [display.eDID length]));
		
		return [NSString stringWithFormat:@"%@ (%@)", display.name, [FixEDID getAspectRatio:edid]];
	}
	else if (tableView == _resolutionsTableView)
	{
	}
	
	return nil;
}

- (IBAction)framebufferInfoChanged:(id)sender
{
	NSInteger intelGen = [_intelGenComboBox indexOfSelectedItem];
	NSInteger platformIDIndex = [_platformIDComboBox indexOfSelectedItem];
	
	if (intelGen == -1 || platformIDIndex == -1)
		return;
	
	NSInteger row = [_framebufferInfoTableView rowForView:sender];
	NSTableCellView *view = [_framebufferInfoTableView viewAtColumn:0 row:row makeIfNecessary:NO];
	NSString *value = [sender stringValue];

	//IntConvert intConvert((uint32_t)row, [view.textField stringValue], (NSString *)value);
	IntConvert *intConvert = [[IntConvert alloc] init:(uint32_t)row name:[view.textField stringValue] stringValue:value];
	[self getIntegerValuesFromString:intConvert];
	
	switch (intelGen)
	{
		case IGSandyBridge:
			setFramebufferValues(reinterpret_cast<FramebufferSNB *>(_modifiedFramebufferList)[platformIDIndex], intConvert);
			break;
		case IGIvyBridge:
			setFramebufferValues(reinterpret_cast<FramebufferIVB *>(_modifiedFramebufferList)[platformIDIndex], intConvert);
			break;
		case IGHaswell:
			setFramebufferValues(reinterpret_cast<FramebufferHSW *>(_modifiedFramebufferList)[platformIDIndex], intConvert);
			break;
		case IGBroadwell:
			setFramebufferValues(reinterpret_cast<FramebufferBDW *>(_modifiedFramebufferList)[platformIDIndex], intConvert);
			break;
		case IGSkylake:
		case IGKabyLake:
			setFramebufferValues(reinterpret_cast<FramebufferSKL *>(_modifiedFramebufferList)[platformIDIndex], intConvert);
			break;
		case IGCoffeeLake:
			setFramebufferValues(reinterpret_cast<FramebufferCFL *>(_modifiedFramebufferList)[platformIDIndex], intConvert);
			break;
		case IGCannonLake:
			setFramebufferValues(reinterpret_cast<FramebufferCNL *>(_modifiedFramebufferList)[platformIDIndex], intConvert);
			break;
		case IGIceLakeLP:
			setFramebufferValues(reinterpret_cast<FramebufferICLLP *>(_modifiedFramebufferList)[platformIDIndex], intConvert);
			break;
		case IGIceLakeHP:
			setFramebufferValues(reinterpret_cast<FramebufferICLHP *>(_modifiedFramebufferList)[platformIDIndex], intConvert);
			break;
	}
	
	[self populateFramebufferInfoList];
}

- (IBAction)framebufferFlagsChanged:(id)sender
{
	NSInteger intelGen = [_intelGenComboBox indexOfSelectedItem];
	NSInteger platformIDIndex = [_platformIDComboBox indexOfSelectedItem];
	
	if (intelGen == -1 || platformIDIndex == -1)
		return;
	
	NSButton *button = (NSButton *)sender;
	NSInteger row = [_framebufferFlagsTableView rowForView:sender];
	bool value = [button state];
	
	if (row == -1)
		return;
	
	switch (intelGen)
	{
		case IGSandyBridge:
		case IGIvyBridge:
			break;
		case IGHaswell:
			[self setFramebufferFlagsWithIndex:row flags:reinterpret_cast<FramebufferHSW *>(_modifiedFramebufferList)[platformIDIndex].flags value:value];
			break;
		case IGBroadwell:
			[self setFramebufferFlagsWithIndex:row flags:reinterpret_cast<FramebufferBDW *>(_modifiedFramebufferList)[platformIDIndex].flags value:value];
			break;
		case IGSkylake:
		case IGKabyLake:
			[self setFramebufferFlagsWithIndex:row flags:reinterpret_cast<FramebufferSKL *>(_modifiedFramebufferList)[platformIDIndex].flags value:value];
			break;
		case IGCoffeeLake:
			[self setFramebufferFlagsWithIndex:row flags:reinterpret_cast<FramebufferCFL *>(_modifiedFramebufferList)[platformIDIndex].flags value:value];
			break;
		case IGCannonLake:
			[self setFramebufferFlagsWithIndex:row flags:reinterpret_cast<FramebufferCNL *>(_modifiedFramebufferList)[platformIDIndex].flags value:value];
			break;
		case IGIceLakeLP:
			[self setFramebufferFlagsWithIndex:row flags:reinterpret_cast<FramebufferICLLP *>(_modifiedFramebufferList)[platformIDIndex].flags value:value];
			break;
		case IGIceLakeHP:
			[self setFramebufferFlagsWithIndex:row flags:reinterpret_cast<FramebufferICLHP *>(_modifiedFramebufferList)[platformIDIndex].flags value:value];
			break;
	}
	
	[self updateFramebufferList];
}

- (IBAction)connectorInfoChanged:(id)sender
{
	NSInteger intelGen = [_intelGenComboBox indexOfSelectedItem];
	NSInteger platformIDIndex = [_platformIDComboBox indexOfSelectedItem];
	
	if (intelGen == -1 || platformIDIndex == -1)
		return;
	
	NSInteger row = [_connectorInfoTableView rowForView:sender];
	NSString *value = [sender stringValue];
	
	//IntConvert intConvert((uint32_t)row, [sender identifier], (NSString *)value);
	IntConvert *intConvert = [[IntConvert alloc] init:(uint32_t)row name:[sender identifier] stringValue:(NSString *)value];
	[self getIntegerValuesFromString:intConvert];
	
	if (IS_ICELAKE(intelGen))
	{
		ConnectorInfoICL *connectorInfo = NULL;
		
		if ([self getConnectorInfoICL:&connectorInfo index:row modified:true])
			setConnectorValues(connectorInfo, intConvert);
	}
	else
	{
		ConnectorInfo *connectorInfo = NULL;
		
		if ([self getConnectorInfo:&connectorInfo index:row modified:true])
			setConnectorValues(connectorInfo, intConvert);
	}
	
	[_connectorInfoTableView reloadData];
	[_connectorInfoTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
	
	[self populateConnectorFlagsList];
}

- (IBAction)connectorFlagsChanged:(id)sender
{
	NSInteger intelGen = [_intelGenComboBox indexOfSelectedItem];
	NSInteger platformIDIndex = [_platformIDComboBox indexOfSelectedItem];
	
	if (intelGen == -1 || platformIDIndex == -1)
		return;
	
	NSInteger row = [_connectorFlagsTableView rowForView:sender];
	NSInteger connectorRow = [_connectorInfoTableView selectedRow];
	bool value = [sender state];
	
	if (row == -1)
		return;
	
	if (IS_ICELAKE(intelGen))
	{
		ConnectorInfoICL *connectorInfo = NULL;
		
		if ([self getConnectorInfoICL:&connectorInfo index:connectorRow modified:true])
			[self setConnectorFlags:(int)row flags:connectorInfo->flags value:(int)value];
	}
	else
	{
		ConnectorInfo *connectorInfo = NULL;
		
		if ([self getConnectorInfo:&connectorInfo index:connectorRow modified:true])
			[self setConnectorFlags:(int)row flags:connectorInfo->flags value:(int)value];
	}
	
	[_connectorInfoTableView reloadData];
	[_connectorInfoTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:connectorRow] byExtendingSelection:NO];
}

- (IBAction)powerSettingsChanged:(id)sender
{
	NSInteger row = [_powerSettingsTableView rowForView:sender];
	NSTableCellView *nameView = [_powerSettingsTableView viewAtColumn:0 row:row makeIfNecessary:NO];
	NSString *name = nameView.textField.stringValue;
	NSString *value = [sender stringValue];
	
	[self setPMValue:name value:value];
	
	[self getPowerSettings];
}

- (IBAction)powerButtonClicked:(id)sender
{
	NSButton *button = (NSButton *)sender;
	NSString *identifier = [button identifier];
	
	if ([identifier isEqualToString:@"FixSleepImage"])
	{
		[self fixSleepImage];
	}
	else if ([identifier isEqualToString:@"Refresh"])
	{
		[self getPowerSettings];
	}
}

- (IBAction)toolsButtonClicked:(id)sender
{
	NSButton *button = (NSButton *)sender;
	NSString *identifier = [button identifier];
	
	if ([identifier isEqualToString:@"AppleIntelInfo"])
	{
		[self getAppleIntelInfo];
	}
	else if ([identifier isEqualToString:@"InstallAtherosKext"])
	{
		[self installAtherosKext];
	}
	else if ([identifier isEqualToString:@"InstallSATAHotplugFixKext"])
	{
		[self installSATAHotplugFixKext];
	}
	else if ([identifier isEqualToString:@"CreateWindowsBluetoothRegistryFile"])
	{
		[self createWindowsBluetoothRegistryFile];
	}
	else if ([identifier isEqualToString:@"CreateWindowsUTCRegistryFiles"])
	{
		[self createWindowsUTCRegistryFiles];
	}
	else if ([identifier isEqualToString:@"DumpACPI"])
	{
		[self dumpACPITables];
	}
	else if ([identifier isEqualToString:@"DisableGatekeeper"])
	{
		[self disableGatekeeperAndMountDiskReadWrite:_toolsOutputTextView forced:YES];
	}
	else if ([identifier isEqualToString:@"InstallKexts"])
	{
		[self installKexts];
	}
	else if ([identifier isEqualToString:@"RebuildKextCache"])
	{
		[_toolsOutputTextView setString:@""];
		[self rebuildKextCacheAndRepairPermissions:_toolsOutputTextView];
	}
}

- (IBAction)nvramChanged:(id)sender
{
	NSInteger row = [_nvramTableView selectedRow];

	if (row == -1)
		return;
	
	NSTableCellView *nameView = [_nvramTableView viewAtColumn:0 row:row makeIfNecessary:NO];
	NSString *name = nameView.textField.stringValue;
	id value = [_nvramDictionary objectForKey:name];
	
	if ([value isKindOfClass:[NSString class]])
	{
		if (value != nil)
			[_nvramValueTextView setString:value];
	}
	else if ([value isKindOfClass:[NSData class]])
	{
		NSData *valueData = (NSData *)value;
		NSString *efiBootDeviceString = [NSString stringWithCString:(const char *)valueData.bytes encoding:NSASCIIStringEncoding];
		NSString *xmlString = nil;
		
		if (tryFormatXML(efiBootDeviceString, &xmlString, true))
			[_nvramValueTextView setString:xmlString];
		else
		{
			NSMutableString *byteString = getByteString(valueData, @" ", @"0x", true, true);
			
			[_nvramValueTextView setString:byteString];
			
			//[_nvramValueTextView setString:[NSString stringWithFormat:@"%@", valueData]];
		}
	}
}

- (IBAction)nvramValueTableViewChanged:(id)sender
{
	NSInteger row = [_nvramTableView rowForView:sender];
	
	if (row == -1)
		return;
	
	NSTableCellView *nameView = [_nvramTableView viewAtColumn:0 row:row makeIfNecessary:NO];
	NSTextField *valueTextField = (NSTextField *)sender;
	NSString *name = nameView.textField.stringValue;
	id value = [_nvramDictionary objectForKey:name];
	NSString *newValue = [[valueTextField.stringValue copy] autorelease];
	
	if ([value isKindOfClass:[NSString class]])
	{
		if ([self setNVRAMValue:name value:newValue])
			[_nvramDictionary setObject:newValue forKey:name];
	}
	else if ([value isKindOfClass:[NSData class]])
	{
		NSData *valueData = stringToData(newValue);
		
		if ([self setNVRAMValue:name value:getByteString(valueData, @"", @"%", false, true)])
			[_nvramDictionary setObject:valueData forKey:name];
	}
	
	[_nvramTableView reloadData];
}

- (IBAction)nvramButtonClicked:(id)sender
{
	NSButton *button = (NSButton *)sender;
	NSString *identifier = [button identifier];
	
	if ([identifier isEqualToString:@"Add"])
	{
		[_createNVRAMComboBox removeAllItems];
		[_createNVRAMComboBox addItemWithObjectValue:@"boot-args"];
		[_createNVRAMComboBox setStringValue:@""];
		
		[_createNVRAMStringButton setState:YES];
		[_createNVRAMTextView setString:@""];
		
		NSRect frame = [_createNVRAMVariableWindow frame];
		frame.size = NSMakeSize(_window.frame.size.width, frame.size.height);
		[_createNVRAMVariableWindow setFrame:frame display:NO animate:NO];
		
		[_window beginSheet:_createNVRAMVariableWindow completionHandler:^(NSModalResponse returnCode)
		 {
			 switch (returnCode)
			 {
				 case NSModalResponseCancel:
					 break;
				 case NSModalResponseOK:
				 {
					 if ([_createNVRAMComboBox.stringValue isEqualToString:@""])
						 break;
					 
					 NSString *nameString = [[_createNVRAMComboBox.stringValue copy] autorelease];
					 NSString *valueString = [[_createNVRAMTextView.string copy] autorelease];
					 
					 if (_createNVRAMStringButton.state)
					 {
						 if ([self setNVRAMValue:nameString value:valueString])
							 [_nvramDictionary setObject:valueString forKey:nameString];
					 }
					 else
					 {
						 NSData *valueData = stringToData(valueString);
						 
						 if ([self setNVRAMValue:nameString value:getByteString(valueData, @"", @"%", false, true)])
							 [_nvramDictionary setObject:valueData forKey:nameString];
					 }
					 
					 [_nvramTableView reloadData];
					 break;
				 }
				 default:
					 break;
			 }
		 }];
		
		return;
	}
	else if ([identifier isEqualToString:@"Delete"])
	{
		NSInteger row = [_nvramTableView selectedRow];
		
		if (row == -1)
			return;
		
		NSTableCellView *valueView = [_nvramTableView viewAtColumn:0 row:row makeIfNecessary:NO];
		NSString *name = valueView.textField.stringValue;
		
		if ([self setNVRAMValue:name value:nil])
			[_nvramDictionary removeObjectForKey:name];
		
		[_nvramTableView reloadData];
	}
	else if ([identifier isEqualToString:@"Refresh"])
	{
		if (getIORegProperties(@"IODeviceTree:/options", &_nvramDictionary))
			[_nvramTableView reloadData];
	}
}

- (IBAction)nvramRadioButtonClicked:(id)sender
{
}

- (IBAction)dsdtRenameChanged:(id)sender
{
	NSInteger row = [_bootloaderPatchTableView rowForView:sender];
	bool value = [sender state];
	
	if (row == -1)
		return;
	
	NSMutableDictionary *bootloaderPatchDictionary = _bootloaderPatchArray[row];
	
	[bootloaderPatchDictionary setObject:[NSNumber numberWithBool:!value] forKey:@"Disabled"];
}

- (IBAction)usbNameChanged:(id)sender
{
	NSInteger row = [_usbPortsTableView rowForView:sender];
	NSString *value = [sender stringValue];
	
	if (row == -1)
		return;
	
	NSMutableDictionary *usbPortsDictionary = _usbPortsArray[row];
	
	usbPortsDictionary[@"name"] = value;
}

- (IBAction)usbCommentChanged:(id)sender
{
	NSInteger row = [_usbPortsTableView rowForView:sender];
	NSString *value = [sender stringValue];
	
	if (row == -1)
		return;
	
	NSMutableDictionary *usbPortsDictionary = _usbPortsArray[row];
	
	usbPortsDictionary[@"Comment"] = value;
}

- (IBAction)usbConnectorChanged:(id)sender
{
	NSInteger row = [_usbPortsTableView rowForView:sender];
	NSString *value = [sender stringValue];
	
	if (row == -1)
		return;
	
	NSArray *fieldArray = @[@"USB2", @"USB3", @"TypeC+Sw", @"TypeC", @"Internal"];
	const uint8_t valueArray[] = {0x00, 0x03, 0x09, 0x0A, 0xFF};
	NSUInteger fieldIndex = [fieldArray indexOfObject:value];
	NSNumber *valueNumber = [NSNumber numberWithInt:valueArray[fieldIndex]];
	NSMutableDictionary *usbPortsDictionary = _usbPortsArray[row];
	
	if ([usbPortsDictionary objectForKey:@"portType"] != nil)
		usbPortsDictionary[@"portType"] = valueNumber;
	else if ([usbPortsDictionary objectForKey:@"UsbConnector"] != nil)
		usbPortsDictionary[@"UsbConnector"] = valueNumber;
}

- (IBAction)displaysChanged:(id)sender
{
	NSInteger row = [_displaysTableView rowForView:sender];
	
	if (row == -1)
		return;
	
	NSInteger col = [_displaysTableView columnForView:sender];
	NSTableColumn *tableColumn = [[_displaysTableView tableColumns] objectAtIndex:col];
	NSString *identifier = [tableColumn identifier];
	NSTableCellView *view = [_displaysTableView viewAtColumn:col row:row makeIfNecessary:NO];
	NSString *valueString = nil;
	uint32_t valueInt = 0;
	bool valueBool = false;
	
	if ([view isKindOfClass:[NSTableCellView class]])
	{
		valueString = [((NSTableCellView *)view).textField stringValue];
		NSScanner *scanner = [NSScanner scannerWithString:valueString];
		[scanner scanHexInt:&valueInt];
	}
	else if ([view isKindOfClass:[NSButton class]])
		valueBool = ((NSButton *)view).state;
	
	Display *display = _displaysArray[row];
	
	if([identifier isEqualToString:@"Name"])
		display.name = valueString;
	else if([identifier isEqualToString:@"Vendor ID"])
		display.vendorIDOverride = valueInt;
	else if([identifier isEqualToString:@"Product ID"])
		display.productIDOverride = valueInt;
	else if([identifier isEqualToString:@"Internal"])
		display.isInternal = valueBool;
	
	[_displaysTableView reloadData];
}

- (IBAction)resolutionsChanged:(id)sender
{
	Display *display;
	
	if (![self getCurrentlySelectedDisplay:&display])
		return;
	
	NSInteger row = [_resolutionsTableView rowForView:sender];
	
	if (row == -1)
		return;
	
	NSInteger col = [_resolutionsTableView columnForView:sender];
	NSTableColumn *tableColumn = [[_resolutionsTableView tableColumns] objectAtIndex:col];
	NSString *identifier = [tableColumn identifier];
	NSView *view = [_resolutionsTableView viewAtColumn:col row:row makeIfNecessary:NO];
	NSString *valueString = nil;
	bool valueBool = false;
	int valueInt = 0;
	
	if ([view isKindOfClass:[NSTableCellView class]])
		valueString = [((NSTableCellView *)view).textField stringValue];
	else if ([view isKindOfClass:[NSButton class]])
		valueBool = ((NSButton *)view).state;
	else if ([view isKindOfClass:[NSComboBox class]])
		valueInt = (int)((NSComboBox *)view).indexOfSelectedItem;
	
	Resolution *resolution = display.resolutionsArray[row];
	
	if([identifier isEqualToString:@"Width"])
		resolution.width = [valueString intValue];
	else if([identifier isEqualToString:@"Height"])
		resolution.height = [valueString intValue];
	else if([identifier isEqualToString:@"Type"])
		resolution.type = (HiDPIType)valueInt;
	
	[_resolutionsTableView reloadData];
}

/* - (NSTableRowView *)rowViewAtRow:(NSInteger)row makeIfNecessary:(BOOL)makeIfNecessary;
{
	return nil;
} */

- (void)tableViewSelectionDidChange:(NSNotification *)notification;
{
	NSTableView *tableView = notification.object;
	
	if (tableView == _displaysTableView)
	{
		[_resolutionsTableView reloadData];
		
		Display *display;
		
		if (![self getCurrentlySelectedDisplay:&display])
			return;
		
		[_edidPopupButton selectItemAtIndex:display.eDIDIndex];
		[_iconComboBox selectItemAtIndex:display.iconIndex];
		[_resolutionComboBox selectItemAtIndex:display.resolutionIndex];
		[_fixMonitorRangesButton setState:display.fixMonitorRanges];
		[_injectAppleInfoButton setState:display.injectAppleInfo];
		[_forceRGBModeButton setState:display.forceRGBMode];
		[_patchColorProfileButton setState:display.patchColorProfile];
		[_ignoreDisplayPrefsButton setState:display.ignoreDisplayPrefs];
		
		EDID edid {};
		
		if (display.eDID != nil)
			memcpy(&edid, [display.eDID bytes], min(sizeof(EDID), [display.eDID length]));
		
		[[_edidPopupButton itemAtIndex:0] setTitle:[NSString stringWithFormat:@"%@ (%@)", display.name, [FixEDID getAspectRatio:edid]]];
	}
}

- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row
{
	if (tableView == _efiPartitionsTableView)
	{
	}
	else if (tableView == _partitionSchemeTableView)
	{
		Disk *disk = _disksArray[row];
		NSNumber *blockSize, *totalSize, *volumeTotalSize, *volumeFreeSpace;
		
		if ([disk sizeInfo:&blockSize totalSize:&totalSize volumeTotalSize:&volumeTotalSize volumeFreeSpace:&volumeFreeSpace])
		//if ([disk sizeInfo:&volumeTotalSize freeSize:&volumeFreeSpace])
		{
			if (volumeTotalSize != nil && volumeFreeSpace != nil)
			{
				double percent = 1.0 - ([volumeFreeSpace doubleValue] / [volumeTotalSize doubleValue]);
				NSColor *color = [NSColor colorWithRed:(50.0 / 255.0) green:(175.0 / 255.0) blue:(246.0 / 255.0) alpha:(102.0 / 255.0)];
				BarTableRowView *barTableRowView = [[BarTableRowView alloc] initWithPercent:percent column:3 color:color inset:NSMakeSize(0, 0) radius:0 stroke:NO];
				[barTableRowView autorelease];
				return barTableRowView;
			}
		}
	}
	
	return nil;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	NSTableCellView *result = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
	NSString *identifier = [tableColumn identifier];
	NSComboBox *comboBox = nil;
	NSButton *button = nil;
	NSImageView *image = nil;
	
	if ([result isKindOfClass:[NSComboBox class]])
		comboBox = (NSComboBox *)result;
	else if ([result isKindOfClass:[NSButton class]])
		button = (NSButton *)result;
	else if ([result isKindOfClass:[NSImageView class]])
		image = (NSImageView *)result;
	
	NSInteger intelGen = [_intelGenComboBox indexOfSelectedItem];
	NSInteger platformIDIndex = [_platformIDComboBox indexOfSelectedItem];
	
	if (tableView == _generateSerialInfoTableView)
	{
		if (row < [_generateSerialInfoArray count])
		{
			NSDictionary *dictionary = [_generateSerialInfoArray objectAtIndex:row];
			NSString *value = dictionary[[tableColumn identifier]];
			result.textField.stringValue = (value != nil ? value : @"");
		}
	}
	else if (tableView == _modelInfoTableView)
	{
		if (row < [_modelInfoArray count])
		{
			NSDictionary *dictionary = [_modelInfoArray objectAtIndex:row];
			NSString *value = dictionary[[tableColumn identifier]];
			result.textField.stringValue = (value != nil ? value : @"");
		}
	}
	else if (tableView == _selectedFBInfoTableView)
	{
		if (intelGen == -1 || platformIDIndex == -1)
			result.textField.stringValue = @"";
		
		if (row < [_selectedFBInfoArray count])
		{
			NSDictionary *dictionary = [_selectedFBInfoArray objectAtIndex:row];
			NSString *value = dictionary[[tableColumn identifier]];
			result.textField.stringValue = (value != nil ? value : @"");
		}
	}
	else if (tableView == _currentFBInfoTableView)
	{
		if (intelGen == -1 || platformIDIndex == -1)
			result.textField.stringValue = @"";
		
		if (row < [_currentFBInfoArray count])
		{
			NSDictionary *dictionary = [_currentFBInfoArray objectAtIndex:row];
			NSString *value = dictionary[[tableColumn identifier]];
			result.textField.stringValue = (value != nil ? value : @"");
		}
	}
	else if (tableView == _vramInfoTableView)
	{
		if (intelGen == -1 || platformIDIndex == -1)
			result.textField.stringValue = @"";
		
		if (row < [_vramInfoArray count])
		{
			NSDictionary *dictionary = [_vramInfoArray objectAtIndex:row];
			NSString *value = dictionary[[tableColumn identifier]];
			result.textField.stringValue = (value != nil ? value : @"");
		}
	}
	else if (tableView == _framebufferInfoTableView)
	{
		if (intelGen == -1 || platformIDIndex == -1)
			result.textField.stringValue = @"";
		
		if (row < [_framebufferInfoArray count])
		{
			NSDictionary *dictionary = [_framebufferInfoArray objectAtIndex:row];
			NSString *value = dictionary[[tableColumn identifier]];
			result.textField.stringValue = (value != nil ? value : @"");
		}
	}
	else if (tableView == _framebufferFlagsTableView)
	{
		if (intelGen == -1 || platformIDIndex == -1)
		{
			if ([result isKindOfClass:[NSButton class]])
				button.state = NO;
			else
				[comboBox setStringValue:@""];
		}
		
		if (row < [_framebufferFlagsArray count])
		{
			NSDictionary *dictionary = [_framebufferFlagsArray objectAtIndex:row];
			
			if([identifier isEqualToString:@"Enabled"])
				button.state = [dictionary[@"Value"] isEqualToString:@"Yes"];
			else
			{
				NSString *value = dictionary[[tableColumn identifier]];
				result.textField.stringValue = (value != nil ? value : @"");
			}
		}
	}
	else if (tableView == _connectorInfoTableView)
	{
		if (intelGen == -1 || platformIDIndex == -1)
		{
			if ([result isKindOfClass:[NSTableCellView class]])
				result.textField.stringValue = @"";
			else
				[comboBox setStringValue:@""];
		}
		
		if (IS_ICELAKE(intelGen))
		{
			ConnectorInfoICL *connectorInfo = NULL;
			
			if (![self getConnectorInfoICL:&connectorInfo index:row modified:true])
				return 0;
		
			//NSLog(@"index: %02X busID: %02X pipe: %02X type: %08X flags: %08X", connectorInfo->index, connectorInfo->busID, connectorInfo->pipe, connectorInfo->type, connectorInfo->flags.value);

			NSString *connectorType = connectorTypeToString(connectorInfo->type);
			NSUInteger fieldIndex = [g_connectorArray indexOfObject:[tableColumn identifier]];
			
			switch(fieldIndex)
			{
				case 0:
					result.textField.stringValue = [NSString stringWithFormat:@"%d", connectorInfo->index];
					break;
				case 1:
					result.textField.stringValue = [NSString stringWithFormat:@"0x%02X", connectorInfo->busID];
					break;
				case 2:
					result.textField.stringValue = [NSString stringWithFormat:@"%d", connectorInfo->pipe];
					break;
				case 3:
				{
					if ([comboBox numberOfItems] == 0)
						[comboBox addItemsWithObjectValues:translateArray(g_connectorTypeArray)];
					
					comboBox.stringValue = connectorType;
					
					break;
				}
				case 4:
					result.textField.stringValue = [NSString stringWithFormat:@"0x%08X", connectorInfo->flags.value];
					break;
			}
		}
		else
		{
			ConnectorInfo *connectorInfo = NULL;
			
			if (![self getConnectorInfo:&connectorInfo index:row modified:true])
				return 0;
		
			//NSLog(@"index: %02X busID: %02X pipe: %02X type: %08X flags: %08X", connectorInfo->index, connectorInfo->busID, connectorInfo->pipe, connectorInfo->type, connectorInfo->flags.value);

			NSString *connectorType = connectorTypeToString(connectorInfo->type);
			NSUInteger fieldIndex = [g_connectorArray indexOfObject:[tableColumn identifier]];
			
			switch(fieldIndex)
			{
				case 0:
					result.textField.stringValue = [NSString stringWithFormat:@"%d", connectorInfo->index];
					break;
				case 1:
					result.textField.stringValue = [NSString stringWithFormat:@"0x%02X", connectorInfo->busID];
					break;
				case 2:
					result.textField.stringValue = [NSString stringWithFormat:@"%d", connectorInfo->pipe];
					break;
				case 3:
				{
					if ([comboBox numberOfItems] == 0)
						[comboBox addItemsWithObjectValues:translateArray(g_connectorTypeArray)];
					
					comboBox.stringValue = connectorType;
					
					break;
				}
				case 4:
					result.textField.stringValue = [NSString stringWithFormat:@"0x%08X", connectorInfo->flags.value];
					break;
			}
		}
	}
	else if (tableView == _connectorFlagsTableView)
	{
		if (intelGen == -1 || platformIDIndex == -1)
		{
			if ([result isKindOfClass:[NSButton class]])
				button.state = NO;
			else
				[comboBox setStringValue:@""];
		}
		
		if (row < [_connectorFlagsArray count])
		{
			NSDictionary *dictionary = [_connectorFlagsArray objectAtIndex:row];
			
			if([identifier isEqualToString:@"Enabled"])
				button.state = [dictionary[@"Value"] isEqualToString:@"Yes"];
			else if([identifier isEqualToString:@"Name"])
				result.textField.stringValue = dictionary[@"Name"];
		}
	}
	else if (tableView == _displayInfoTableView)
	{
		if (row < [_displayInfoArray count])
		{
			NSDictionary *dictionary = [_displayInfoArray objectAtIndex:row];
			NSString *value = dictionary[[tableColumn identifier]];
			result.textField.stringValue = (value != nil ? value : @"");
		}
	}
	else if (tableView == _bootloaderInfoTableView)
	{
		if (row < [_bootloaderInfoArray count])
		{
			NSDictionary *dictionary = [_bootloaderInfoArray objectAtIndex:row];
			NSString *value = dictionary[[tableColumn identifier]];
			result.textField.stringValue = (value != nil ? value : @"");
		}
	}
	else if (tableView == _bootloaderPatchTableView)
	{
		NSMutableDictionary *patchDictionary =_bootloaderPatchArray[row];
		
		if([identifier isEqualToString:@"Select"])
			button.state = ![[patchDictionary objectForKey:@"Disabled"] boolValue];
		else if([identifier isEqualToString:@"Type"])
			result.textField.stringValue = [patchDictionary objectForKey:@"Type"];
		else if([identifier isEqualToString:@"Comment"])
			result.textField.stringValue = [patchDictionary objectForKey:@"Comment"];
	}
	else if (tableView == _nvramTableView)
	{
		NSArray *keyArray = [_nvramDictionary.allKeys sortedArrayUsingSelector:@selector(compare:)];
		NSString *key = [keyArray objectAtIndex:row];
		id value = [_nvramDictionary objectForKey:key];
		
		if([identifier isEqualToString:@"Name"])
			result.textField.stringValue = key;
		else if([identifier isEqualToString:@"Value"])
		{
			if ([value isKindOfClass:[NSString class]])
				result.textField.stringValue = [NSString stringWithFormat:@"%@", value];
			else if ([value isKindOfClass:[NSData class]])
				result.textField.stringValue = [NSString stringWithFormat:@"%@", getByteStringClassic(value)];
			else
				result.textField.stringValue = @"???";
		}
	}
	else if (tableView == _kextsTableView)
	{
		NSMutableArray *kextsArray = (_settings.ShowInstalledOnly ? _installedKextsArray : _kextsArray);
		NSMutableDictionary *kextDictionary = kextsArray[row];
		NSString *superseder = [kextDictionary objectForKey:@"Superseder"];
		
		if([identifier isEqualToString:@"Name"])
			result.textField.stringValue = [kextDictionary objectForKey:@"Name"];
		else if([identifier isEqualToString:@"InstalledVersion"])
			result.textField.stringValue = [kextDictionary objectForKey:@"InstalledVersion"];
		else if([identifier isEqualToString:@"CurrentVersion"])
			result.textField.stringValue = [kextDictionary objectForKey:@"CurrentVersion"];
		else if([identifier isEqualToString:@"DownloadVersion"])
			result.textField.stringValue = [kextDictionary objectForKey:@"DownloadVersion"];
		else if([identifier isEqualToString:@"Superseder"])
			result.textField.stringValue = (superseder != nil ? superseder : @"");
		else if([identifier isEqualToString:@"Description"])
			result.textField.stringValue = [kextDictionary objectForKey:@"Description"];
		else if([identifier isEqualToString:@"Url"])
			result.textField.stringValue = [kextDictionary objectForKey:@"ProjectUrl"];
	}
	else if (tableView == _usbControllersTableView)
	{
		NSDictionary *usbControllersDictionary = _usbControllersArray[row];
		
		if([identifier isEqualToString:@"ID"])
		{
			uint32_t locationID = propertyToUInt32([usbControllersDictionary objectForKey:@"ID"]);
			
			result.textField.stringValue = [NSString stringWithFormat:@"0x%02X", locationID];
		}
		else if([identifier isEqualToString:@"Vendor ID"])
		{
			uint32_t deviceID = propertyToUInt32([usbControllersDictionary objectForKey:@"DeviceID"]);
			
			result.textField.stringValue = [NSString stringWithFormat:@"0x%04X", (deviceID & 0xFFFF)];
		}
		else if([identifier isEqualToString:@"Device ID"])
		{
			uint32_t deviceID = propertyToUInt32([usbControllersDictionary objectForKey:@"DeviceID"]);
			
			result.textField.stringValue = [NSString stringWithFormat:@"0x%04X", (deviceID >> 16)];
		}
		else
		{
			NSString *value = [usbControllersDictionary objectForKey:[tableColumn identifier]];
			result.textField.stringValue = (value != nil ? value : @"");
		}
	}
	else if (tableView == _usbPortsTableView)
	{
		NSMutableDictionary *usbPortsDictionary = _usbPortsArray[row];

		if ([identifier isEqualToString:@"Type"])
		{
			result.textField.stringValue = [usbPortsDictionary objectForKey:@"UsbController"];
		}
		else if([identifier isEqualToString:@"locationID"])
		{
			uint32_t locationID = propertyToUInt32([usbPortsDictionary objectForKey:@"locationID"]);
			
			result.textField.stringValue = [NSString stringWithFormat:@"0x%08X", locationID];
		}
		else if([identifier isEqualToString:@"port"])
		{
			uint32_t port = propertyToUInt32([usbPortsDictionary objectForKey:@"port"]);
			
			result.textField.stringValue = [NSString stringWithFormat:@"0x%02X", port];
		}
		else if([identifier isEqualToString:@"UsbConnector"])
		{
			NSNumber *portType = [usbPortsDictionary objectForKey:@"portType"];
			NSNumber *usbConnector = [usbPortsDictionary objectForKey:@"UsbConnector"];
			uint32_t port = (portType != nil ? [portType unsignedIntValue] : usbConnector != nil ? [usbConnector unsignedIntValue] : 0);
			
			if ([comboBox numberOfItems] == 0)
				[comboBox addItemsWithObjectValues:@[@"USB2", @"USB3", @"TypeC+Sw", @"TypeC", @"Internal"]];
			
			comboBox.stringValue = getUSBConnectorType((UsbConnector)port);
		}
		else if([identifier isEqualToString:@"DevSpeed"])
		{
			NSNumber *devSpeed = [usbPortsDictionary objectForKey:@"DevSpeed"];
			
			result.textField.stringValue = getUSBConnectorSpeed(devSpeed ? [devSpeed unsignedIntValue] : -1);
		}
		else
		{
			NSString *value = [usbPortsDictionary objectForKey:[tableColumn identifier]];
			result.textField.stringValue = (value != nil ? value : @"");
		}
	}
	else if (tableView == _audioDevicesTableView1 || tableView == _audioDevicesTableView2)
	{
		AudioDevice *audioDevice = _audioDevicesArray[row];
		NSString *deviceName = (audioDevice.audioDeviceModelID != 0 ? audioDevice.audioDeviceName : (audioDevice.codecID != 0 ? audioDevice.codecName : audioDevice.deviceName));
		
		if([identifier isEqualToString:@"Device"])
			result.textField.stringValue = [NSString stringWithFormat:@"0x%08X", audioDevice.deviceID];
		else if([identifier isEqualToString:@"Sub Device"])
			result.textField.stringValue = [NSString stringWithFormat:@"0x%08X", audioDevice.subDeviceID];
		else if([identifier isEqualToString:@"Codec"])
			result.textField.stringValue = (audioDevice.codecID != 0 ? [NSString stringWithFormat:@"0x%08X", audioDevice.codecID] : @"-");
		else if([identifier isEqualToString:@"Revision"])
			result.textField.stringValue = (audioDevice.codecID != 0 ? [NSString stringWithFormat:@"0x%04X", audioDevice.codecRevisionID & 0xFFFF] : @"-");
		else if([identifier isEqualToString:@"Name"])
			result.textField.stringValue = (deviceName != nil ? deviceName : @"???");
	}
	else if (tableView == _audioInfoTableView)
	{
		NSInteger selectedRow = [_audioDevicesTableView1 selectedRow];
		
		if (selectedRow == -1)
			return nil;
		
		AudioDevice *audioDevice = _audioDevicesArray[selectedRow];
		NSDictionary *dictionary = [_audioInfoArray objectAtIndex:row];
		NSString *name = dictionary[@"Name"];
		NSString *value = dictionary[[tableColumn identifier]];
		
		if ([name isEqualToString:GetLocalizedString(@"ALC Layout ID")])
		{
			if ([[tableColumn identifier] isEqualToString:@"Value"])
			{
				comboBox = [[[NSComboBox alloc] init] autorelease];
				[comboBox setControlSize:NSSmallControlSize];
				[comboBox setFont:[NSFont systemFontOfSize:NSFont.smallSystemFontSize]];
				[comboBox addItemsWithObjectValues:audioDevice.layoutIDArray];
				[comboBox setIdentifier:@"ALCLayoutID"];
				[comboBox setStringValue:value];
				[comboBox setDelegate:self];
				
				return comboBox;
			}
		}

		result.textField.stringValue = (value != nil ? value : @"");
	}
	else if (tableView == _efiPartitionsTableView)
	{
		NSMutableArray *efiPartitionsArray = getEfiPartitionsArray(_disksArray);
		Disk *disk = efiPartitionsArray[row];
		
		if([identifier isEqualToString:@"Icon"])
			[((NSImageView *)result) setImage:disk.icon];
		else if([identifier isEqualToString:@"Device Name"])
			result.textField.stringValue = getDeviceName(_disksArray, disk.disk);
		else if([identifier isEqualToString:@"Volume Name"])
			result.textField.stringValue =(disk.volumeName != nil ? disk.volumeName : @"");
		else if([identifier isEqualToString:@"BSDName"])
			result.textField.stringValue = (disk.mediaBSDName != nil ? disk.mediaBSDName : @"");
		else if([identifier isEqualToString:@"MountPoint"])
			result.textField.stringValue = (disk.volumePath != nil ? [disk.volumePath path] : @"");
		else if([identifier isEqualToString:@"Mount"])
			button.image = [NSImage imageNamed:(disk.isMounted ? @"IconUnmount" : @"IconMount")];
		else if([identifier isEqualToString:@"Open"])
			button.enabled = disk.isMounted;
	}
	else if (tableView == _partitionSchemeTableView)
	{
		Disk *disk = _disksArray[row];
		
		if([identifier isEqualToString:@"Icon"])
			image.image = disk.icon;
		else if([identifier isEqualToString:@"VolumeName"])
		{
			if (disk.isAPFS || disk.isAPFSContainer)
				result.textField.stringValue = [NSString stringWithFormat:@"🔗 %@", disk.apfsBSDNameLink];
			else if (disk.isDisk)
				result.textField.stringValue = getDeviceName(_disksArray, disk.disk);
			else
				result.textField.stringValue = (disk.volumeName != nil ? disk.volumeName : @"");
		}
		else if([identifier isEqualToString:@"BSDName"])
			result.textField.stringValue = (disk.mediaBSDName != nil ? disk.mediaBSDName : @"");
		else if([identifier isEqualToString:@"MountPoint"])
			result.textField.stringValue = (disk.volumePath != nil ? [disk.volumePath path] : @"");
		else if([identifier isEqualToString:@"DiskType"])
			result.textField.stringValue = disk.type;
	}
	else if (tableView == _pciDevicesTableView)
	{
		NSMutableDictionary *pciDeviceDictionary = _pciDevicesArray[row];

		if([identifier isEqualToString:@"View"])
			button.enabled = ([pciDeviceDictionary objectForKey:@"BundleID"] != nil);
		else if([identifier isEqualToString:@"PCIDebug"])
			result.textField.stringValue = [pciDeviceDictionary objectForKey:@"PCIDebug"];
		else if([identifier isEqualToString:@"VendorID"])
			result.textField.stringValue = [NSString stringWithFormat:@"0x%04X", [[pciDeviceDictionary objectForKey:@"VendorID"] unsignedIntValue]];
		else if([identifier isEqualToString:@"DeviceID"])
			result.textField.stringValue = [NSString stringWithFormat:@"0x%04X", [[pciDeviceDictionary objectForKey:@"DeviceID"] unsignedIntValue]];
		else if([identifier isEqualToString:@"SubVendorID"])
			result.textField.stringValue = [NSString stringWithFormat:@"0x%04X", [[pciDeviceDictionary objectForKey:@"SubVendorID"] unsignedIntValue]];
		else if([identifier isEqualToString:@"SubDeviceID"])
			result.textField.stringValue = [NSString stringWithFormat:@"0x%04X", [[pciDeviceDictionary objectForKey:@"SubDeviceID"] unsignedIntValue]];
		else if([identifier isEqualToString:@"VendorName"])
			result.textField.stringValue = [pciDeviceDictionary objectForKey:@"VendorName"];
		else if([identifier isEqualToString:@"DeviceName"])
			result.textField.stringValue = [pciDeviceDictionary objectForKey:@"DeviceName"];
		else if([identifier isEqualToString:@"ClassName"])
			result.textField.stringValue = [pciDeviceDictionary objectForKey:@"ClassName"];
		else if([identifier isEqualToString:@"SubClassName"])
			result.textField.stringValue = [pciDeviceDictionary objectForKey:@"SubClassName"];
		else if([identifier isEqualToString:@"IORegName"])
			result.textField.stringValue = [pciDeviceDictionary objectForKey:@"IORegName"];
		else if([identifier isEqualToString:@"IORegIOName"])
			result.textField.stringValue = [pciDeviceDictionary objectForKey:@"IORegIOName"];
		else if([identifier isEqualToString:@"ASPM"])
			//result.textField.stringValue = [NSString stringWithFormat:@"0x%04X", [[pciDeviceDictionary objectForKey:@"ASPM"] unsignedIntValue]];
			result.textField.stringValue = [pciDeviceDictionary objectForKey:@"ASPM"];
		else if([identifier isEqualToString:@"DevicePath"])
			result.textField.stringValue =  [pciDeviceDictionary objectForKey:@"DevicePath"];
	}
	else if (tableView == _networkInterfacesTableView)
	{
		NSMutableDictionary *networkInterfacesDictionary = _networkInterfacesArray[row];
		NSNumber *vendorID = [networkInterfacesDictionary objectForKey:@"VendorID"];
		NSNumber *deviceID = [networkInterfacesDictionary objectForKey:@"DeviceID"];
		NSString *vendorName = [networkInterfacesDictionary objectForKey:@"VendorName"];
		NSString *deviceName = [networkInterfacesDictionary objectForKey:@"DeviceName"];
		NSString *bsdName = [networkInterfacesDictionary objectForKey:@"BSD Name"];
		NSNumber *builtin = [networkInterfacesDictionary objectForKey:@"Builtin"];
		NSString *bundleID = [networkInterfacesDictionary objectForKey:@"BundleID"];
		
		if([identifier isEqualToString:@"View"])
			button.enabled = (bundleID != nil);
		else if([identifier isEqualToString:@"Vendor"])
			result.textField.stringValue = [NSString stringWithFormat:@"0x%04X", [vendorID unsignedIntValue]];
		else if([identifier isEqualToString:@"Device"])
			result.textField.stringValue = [NSString stringWithFormat:@"0x%04X", [deviceID unsignedIntValue]];
		else if([identifier isEqualToString:@"Vendor Name"])
			result.textField.stringValue = vendorName;
		else if([identifier isEqualToString:@"Device Name"])
			result.textField.stringValue = deviceName;
		else if([identifier isEqualToString:@"BSD Name"])
			result.textField.stringValue = bsdName;
		else if([identifier isEqualToString:@"Builtin"])
			button.state = [builtin boolValue];
	}
	else if (tableView == _bluetoothDevicesTableView)
	{
		NSMutableDictionary *bluetoothDeviceDictionary = _bluetoothDevicesArray[row];
		NSNumber *vendorID = [bluetoothDeviceDictionary objectForKey:@"VendorID"];
		NSNumber *deviceID = [bluetoothDeviceDictionary objectForKey:@"DeviceID"];
		NSString *vendorName = [bluetoothDeviceDictionary objectForKey:@"VendorName"];
		NSString *deviceName = [bluetoothDeviceDictionary objectForKey:@"DeviceName"];
		NSNumber *fwLoaded = [bluetoothDeviceDictionary objectForKey:@"FWLoaded"];
		NSString *bundleID = [bluetoothDeviceDictionary objectForKey:@"BundleID"];
		
		if([identifier isEqualToString:@"View"])
			button.enabled = (bundleID != nil);
		else if([identifier isEqualToString:@"Vendor"])
			result.textField.stringValue = [NSString stringWithFormat:@"0x%04X", [vendorID unsignedIntValue]];
		else if([identifier isEqualToString:@"Device"])
			result.textField.stringValue = [NSString stringWithFormat:@"0x%04X", [deviceID unsignedIntValue]];
		else if([identifier isEqualToString:@"Vendor Name"])
			result.textField.stringValue = vendorName;
		else if([identifier isEqualToString:@"Device Name"])
			result.textField.stringValue = deviceName;
		else if([identifier isEqualToString:@"FWLoaded"])
			button.state = [fwLoaded boolValue];
	}
	else if (tableView == _graphicDevicesTableView)
	{
		NSMutableDictionary *graphicDeviceDictionary = _graphicDevicesArray[row];
		NSString *bundleID = [graphicDeviceDictionary objectForKey:@"BundleID"];
		NSString *model = [graphicDeviceDictionary objectForKey:@"Model"];
		NSString *framebuffer = [graphicDeviceDictionary objectForKey:@"Framebuffer"];
		NSNumber *portCount = [graphicDeviceDictionary objectForKey:@"PortCount"];
		
		if([identifier isEqualToString:@"View"])
			button.enabled = (bundleID != nil);
		else if([identifier isEqualToString:@"Model"])
			result.textField.stringValue = model;
		else if([identifier isEqualToString:@"Framebuffer"])
			result.textField.stringValue = framebuffer;
		else if([identifier isEqualToString:@"Ports"])
			result.textField.stringValue = [portCount stringValue];
	}
	else if (tableView == _storageDevicesTableView)
	{
		NSMutableDictionary *storageDeviceDictionary = _storageDevicesArray[row];
		NSString *bundleID = [storageDeviceDictionary objectForKey:@"BundleID"];
		NSString *model = [storageDeviceDictionary objectForKey:@"Model"];
		NSString *type = [storageDeviceDictionary objectForKey:@"Type"];
		NSString *location = GetLocalizedString([storageDeviceDictionary objectForKey:@"Location"]);
		NSNumber *blockSize = [storageDeviceDictionary objectForKey:@"BlockSize"];
	
		if([identifier isEqualToString:@"View"])
			button.enabled = (bundleID != nil);
		else if([identifier isEqualToString:@"Model"])
			result.textField.stringValue = model;
		else if([identifier isEqualToString:@"Type"])
			result.textField.stringValue = type;
		else if([identifier isEqualToString:@"Location"])
			result.textField.stringValue = location;
		else if([identifier isEqualToString:@"Phy Block"])
			result.textField.stringValue = (blockSize != nil ? [blockSize stringValue] : @"-");
	}
	else if (tableView == _powerSettingsTableView)
	{
		NSArray *sortedPowerKeys = [[_currentPowerSettings allKeys] sortedArrayUsingSelector:@selector(compare:)];
		NSString *powerKey = sortedPowerKeys[row];
		NSString *powerValue = [_currentPowerSettings objectForKey:powerKey];
		
		if([identifier isEqualToString:@"Name"])
			result.textField.stringValue = powerKey;
		else if([identifier isEqualToString:@"Value"])
			result.textField.stringValue = powerValue;
	}
	else if (tableView == _displaysTableView)
	{
		Display *display = _displaysArray[row];
		
		if([identifier isEqualToString:@"Name"])
			result.textField.stringValue = (display.name != nil ? display.name : @"");
		else if([identifier isEqualToString:@"Vendor ID"])
			result.textField.stringValue = [NSString stringWithFormat:@"0x%04X", display.vendorIDOverride];
		else if([identifier isEqualToString:@"Product ID"])
			result.textField.stringValue = [NSString stringWithFormat:@"0x%04X", display.productIDOverride];
		else if([identifier isEqualToString:@"Serial Number"])
			result.textField.stringValue = [NSString stringWithFormat:@"0x%04X", display.serialNumber];
		else if([identifier isEqualToString:@"Internal"])
			button.state = display.isInternal;
	}
	else if (tableView == _resolutionsTableView)
	{
		Display *display;
		
		if (![self getCurrentlySelectedDisplay:&display])
			return 0;
		
		Resolution *resolution = display.resolutionsArray[row];
		
		if([identifier isEqualToString:@"Width"])
			result.textField.stringValue = [NSString stringWithFormat:@"%d", resolution.width];
		else if([identifier isEqualToString:@"x"])
			result.textField.stringValue = @"x";
		else if([identifier isEqualToString:@"Height"])
			result.textField.stringValue = [NSString stringWithFormat:@"%d", resolution.height];
		else if([identifier isEqualToString:@"Type"])
			[comboBox selectItemAtIndex:resolution.type];
	}
	
	NSString *toolTip = [self getToolTip:tableView tableColumn:tableColumn row:row];
	
	if (toolTip != nil)
		[result setToolTip:toolTip];
	else if ([result isKindOfClass:[NSTableCellView class]])
		[result setToolTip:result.textField.stringValue];
	
	return result;
}

- (void)tableView:(NSTableView *)tableView didAddRowView:(NSTableRowView *)rowView forRow:(NSInteger)row
{
	if (tableView == _connectorInfoTableView)
	{
		uint32_t index, busID, pipe;
		ConnectorType type;
		ConnectorFlags flags;
		[self getConnectorInfo:(uint32_t)row Index:&index BusID:&busID Pipe:&pipe Type:&type Flags:&flags];
#ifdef USE_ALTERNATING_BACKGROUND_COLOR
		NSArray *alternatingContentBackgroundColors = [NSColor controlAlternatingRowBackgroundColors];
		NSColor *backgroundColor = alternatingContentBackgroundColors[row % 2];
#else
		NSColor *backgroundColor = [NSColor controlBackgroundColor];
#endif
		
		[rowView setBackgroundColor:backgroundColor];
		
		if (index == -1)
			return;
		
		for (Display *display in _displaysArray)
		{
			uint32_t videoVendorID = display.videoID & 0xFFFF;
			
			if (videoVendorID != VEN_INTEL_ID)
				continue;
			
			if (_settings.ApplyCurrentPatches)
			{
				if (![self doesDisplayPortMatchIndex:index port:display.port])
					continue;
			}
			else
				if ((uint32_t)row != display.index)
					continue;
			
			[rowView setBackgroundColor:(display.isInternal ? _greenColor : _redColor)];
		}
	}
	else if (tableView == _kextsTableView)
	{
		NSMutableArray *kextsArray = (_settings.ShowInstalledOnly ? _installedKextsArray : _kextsArray);
		NSMutableDictionary *kextDictionary = kextsArray[row];
		NSString *installedVersion = [kextDictionary objectForKey:@"InstalledVersion"];
		//NSString *currentVersion = [kextDictionary objectForKey:@"CurrentVersion"];
		NSString *downloadVersion = [kextDictionary objectForKey:@"DownloadVersion"];
		NSString *superseder = [kextDictionary objectForKey:@"Superseder"];
		bool isInstalled = ![installedVersion isEqualToString:@""];
		//bool isCurrentVersionNewer = ([self compareVersion:installedVersion otherVersion:currentVersion] == NSOrderedAscending);
		bool isDownloadVersionNewer = ([self compareVersion:installedVersion otherVersion:downloadVersion] == NSOrderedAscending);
		//bool isNewVersionAvailable = (isCurrentVersionNewer || isDownloadVersionNewer);
		bool isNewVersionAvailable = isDownloadVersionNewer;
		bool isSuperseded = (superseder != nil && ![superseder isEqualToString:@""]);
#ifdef USE_ALTERNATING_BACKGROUND_COLOR
		NSArray *alternatingContentBackgroundColors = [NSColor controlAlternatingRowBackgroundColors];
		NSColor *backgroundColor = alternatingContentBackgroundColors[row % 2];
#else
		NSColor *backgroundColor = [NSColor controlBackgroundColor];
#endif
		
		if (isInstalled)
			[rowView setBackgroundColor:(isNewVersionAvailable || isSuperseded ? _redColor : _greenColor)];
		else
			[rowView setBackgroundColor:backgroundColor];
	}
	else if (tableView == _usbPortsTableView)
	{
		NSDictionary *usbDictionary = _usbPortsArray[row];
		NSNumber *isActive = [usbDictionary objectForKey:@"IsActive"];
#ifdef USE_ALTERNATING_BACKGROUND_COLOR
		NSArray *alternatingContentBackgroundColors = [NSColor controlAlternatingRowBackgroundColors];
		NSColor *backgroundColor = alternatingContentBackgroundColors[row % 2];
#else
		NSColor *backgroundColor = [NSColor controlBackgroundColor];
#endif
	
		[rowView setBackgroundColor:(isActive && [isActive boolValue] ? _greenColor : backgroundColor)];
	}
	else if (tableView == _efiPartitionsTableView)
	{
		NSMutableArray *efiPartitionsArray = getEfiPartitionsArray(_disksArray);
		Disk *disk = efiPartitionsArray[row];
#ifdef USE_ALTERNATING_BACKGROUND_COLOR
		NSArray *alternatingContentBackgroundColors = [NSColor controlAlternatingRowBackgroundColors];
		NSColor *backgroundColor = alternatingContentBackgroundColors[row % 2];
#else
		NSColor *backgroundColor = [NSColor controlBackgroundColor];
#endif
		
		[rowView setBackgroundColor:(disk.isBootableEFI ? _greenColor : backgroundColor)];
	}
	else if (tableView == _partitionSchemeTableView)
	{
		Disk *disk = _disksArray[row];
		
		[rowView setBackgroundColor:[disk color:COLOR_ALPHA]];
	}
	else if (tableView == _powerSettingsTableView)
	{
		NSArray *sortedPowerKeys = [[_currentPowerSettings allKeys] sortedArrayUsingSelector:@selector(compare:)];
		NSString *powerKey = sortedPowerKeys[row];
		NSString *powerValue = [_currentPowerSettings objectForKey:powerKey];
		
		if ([powerKey isEqualToString:@"hibernatemode"])
			[rowView setBackgroundColor:([powerValue isEqualToString:@"0"] ? _greenColor : _redColor)];
		else if ([powerKey isEqualToString:@"proximitywake"])
			[rowView setBackgroundColor:([powerValue isEqualToString:@"0"] ? _greenColor : _redColor)];
	}
}

- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell1 forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	[self tableView:tableView didAddRowView:cell1 forRow:row];
}

- (BOOL)tableView:(NSTableView *)tv writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard*)pboard
{
	NSData *zNSIndexSetData = [NSKeyedArchiver archivedDataWithRootObject:rowIndexes];

	[pboard declareTypes:[NSArray arrayWithObject:MyPrivateTableViewDataType] owner:self];

	[pboard setData:zNSIndexSetData forType:MyPrivateTableViewDataType];

	return YES;
}
 
- (NSDragOperation)tableView:(NSTableView*)tv validateDrop:(id )info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)op
{
	return NSDragOperationEvery;
}
 
 - (BOOL)tableView:(NSTableView *)aTableView acceptDrop:(id )info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)operation
{
	NSPasteboard *pboard = [info draggingPasteboard];
	NSData *rowData = [pboard dataForType:MyPrivateTableViewDataType];
	NSIndexSet *rowIndexes = [NSKeyedUnarchiver unarchiveObjectWithData:rowData];
	NSInteger dragRow = [rowIndexes firstIndex];

	[self dragConnectorInfo:(uint32_t)dragRow Row:(uint32_t)row];
	
	[aTableView noteNumberOfRowsChanged];
	[aTableView moveRowAtIndex:dragRow toIndex:dragRow < row ? row - 1 : row];

	return YES;
}

- (void)tableView:(NSTableView *)tableView sortDescriptorsDidChange:(NSArray *)oldDescriptors
{
	if (tableView == _generateSerialInfoTableView)
	{
		[_generateSerialInfoArray sortUsingDescriptors:[tableView sortDescriptors]];
		[tableView reloadData];
	}
	else if (tableView == _modelInfoTableView)
	{
		[_modelInfoArray sortUsingDescriptors:[tableView sortDescriptors]];
		[tableView reloadData];
	}
	else if (tableView == _selectedFBInfoTableView)
	{
		[_selectedFBInfoArray sortUsingDescriptors:[tableView sortDescriptors]];
		[tableView reloadData];
	}
	else if (tableView == _currentFBInfoTableView)
	{
		[_currentFBInfoArray sortUsingDescriptors:[tableView sortDescriptors]];
		[tableView reloadData];
	}
	else if (tableView == _vramInfoTableView)
	{
		[_vramInfoArray sortUsingDescriptors:[tableView sortDescriptors]];
		[tableView reloadData];
	}
	else if (tableView == _framebufferInfoTableView)
	{
		[_framebufferInfoArray sortUsingDescriptors:[tableView sortDescriptors]];
		[tableView reloadData];
	}
	else if (tableView == _framebufferFlagsTableView)
	{
		[_framebufferFlagsArray sortUsingDescriptors:[tableView sortDescriptors]];
		[tableView reloadData];
	}
	else if (tableView == _connectorInfoTableView)
	{
	}
	else if (tableView == _connectorFlagsTableView)
	{
		[_connectorFlagsArray sortUsingDescriptors:[tableView sortDescriptors]];
		[tableView reloadData];
	}
	else if (tableView == _displayInfoTableView)
	{
		[_displayInfoArray sortUsingDescriptors:[tableView sortDescriptors]];
		[tableView reloadData];
	}
	else if (tableView == _bootloaderInfoTableView)
	{
		[_bootloaderInfoArray sortUsingDescriptors:[tableView sortDescriptors]];
		[tableView reloadData];
	}
	else if (tableView == _bootloaderPatchTableView)
	{
		[_bootloaderPatchArray sortUsingDescriptors:[tableView sortDescriptors]];
		[tableView reloadData];
	}
	else if (tableView == _nvramTableView)
	{
	}
	else if (tableView == _kextsTableView)
	{
		[(_settings.ShowInstalledOnly ? _installedKextsArray : _kextsArray) sortUsingDescriptors:[tableView sortDescriptors]];
		[tableView reloadData];
	}
	else if (tableView == _usbControllersTableView)
	{
		[_usbControllersArray sortUsingDescriptors:[tableView sortDescriptors]];
		[tableView reloadData];
	}
	else if (tableView == _usbPortsTableView)
	{
		[_usbPortsArray sortUsingDescriptors:[tableView sortDescriptors]];
		[tableView reloadData];
	}
	else if (tableView == _audioDevicesTableView1)
	{
	}
	else if (tableView == _audioInfoTableView)
	{
		[_audioInfoArray sortUsingDescriptors:[tableView sortDescriptors]];
		[tableView reloadData];
	}
	else if (tableView == _efiPartitionsTableView)
	{
		NSMutableArray *efiPartitionsArray = getEfiPartitionsArray(_disksArray);
		[efiPartitionsArray sortUsingDescriptors:[tableView sortDescriptors]];
		[tableView reloadData];
	}
	else if (tableView == _partitionSchemeTableView)
	{
	}
	else if (tableView == _pciDevicesTableView)
	{
		[_pciDevicesArray sortUsingDescriptors:[tableView sortDescriptors]];
		[tableView reloadData];
	}
	else if (tableView == _networkInterfacesTableView)
	{
		[_networkInterfacesArray sortUsingDescriptors:[tableView sortDescriptors]];
		[tableView reloadData];
	}
	else if (tableView == _bluetoothDevicesTableView)
	{;
		[_bluetoothDevicesArray sortUsingDescriptors:[tableView sortDescriptors]];
		[tableView reloadData];
	}
	else if (tableView == _graphicDevicesTableView)
	{
		[_graphicDevicesArray sortUsingDescriptors:[tableView sortDescriptors]];
		[tableView reloadData];
	}
	else if (tableView == _audioDevicesTableView2)
	{
	}
	else if (tableView == _storageDevicesTableView)
	{
		[_storageDevicesArray sortUsingDescriptors:[tableView sortDescriptors]];
		[tableView reloadData];
	}
	else if (tableView == _powerSettingsTableView)
	{
	}
	else if (tableView == _displaysTableView)
	{
		[_displaysArray sortUsingDescriptors:[tableView sortDescriptors]];
		[tableView reloadData];
	}
	else if (tableView == _resolutionsTableView)
	{
	}
}

- (void)doubleClickConnectorInfoTableView:(id)object
{
	//NSInteger row = [_framebufferTableView clickedRow];
	
	//User user;
	//[[_framebufferTable objectAtIndex:row] getValue:&user];
	
	//[[NSWorkspace sharedWorkspace] openURL:[self getRegionUrl:&user]];
	
	//NSLog(@"%@", [[self getRegionUrl:&user] absoluteString]);
}

- (IBAction)connectorInfoTableViewSelected:(id)sender
{
	NSInteger row = [sender selectedRow];
	
	if(row == -1)
		return;
	
	[self populateConnectorFlagsList];
	[self populateDisplayInfo];
}

- (IBAction)audioTableViewSelected:(id)sender
{
	[self updateAudioInfo];
	[self updatePinConfiguration];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
	if (outlineView == _infoOutlineView)
	{
		if ([item isKindOfClass:[NSDictionary class]])
		{
			if ([item objectForKey:@"Parent"] != nil)
				return [[item objectForKey:@"Children"] count];
			else
				return NO;
		}
	}
	
	return NO;
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
	if (outlineView == _infoOutlineView)
	{
		if (item == nil)
			return [_infoArray count];
		
		if ([item isKindOfClass:[NSDictionary class]])
		{
			if ([item objectForKey:@"Parent"] != nil)
				return [[item objectForKey:@"Children"] count];
		}
	}
	else if (outlineView == _pinConfigurationOutlineView)
	{
		return (item ? 0 : [_nodeArray count]);
	}
	
	return 0;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
	if (outlineView == _infoOutlineView)
	{
		if (item == nil)
			return [_infoArray objectAtIndex:index];
		
		if ([item isKindOfClass:[NSDictionary class]])
		{
			if ([item objectForKey:@"Parent"] != nil)
				return [[item objectForKey:@"Children"] objectAtIndex:index];
		}
	}
	else if (outlineView == _pinConfigurationOutlineView)
		return (item ? nil : [_nodeArray objectAtIndex:index]);
	
	return nil;
}

- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
	NSTableCellView *result = [outlineView makeViewWithIdentifier:tableColumn.identifier owner:self];
	
	if (outlineView == _infoOutlineView)
	{
		if ([[tableColumn identifier] isEqualToString:@"Name"])
		{
			if ([item objectForKey:@"Parent"] != nil)
				result.textField.stringValue = [item objectForKey:@"Parent"];
			else
				result.textField.stringValue = [item objectForKey:@"Name"] != nil ? [item objectForKey:@"Name"] : item;
		}
		else if ([[tableColumn identifier] isEqualToString:@"Value"])
		{
			if ([item objectForKey:@"Parent"] != nil)
				result.textField.stringValue = @"";
			else
				result.textField.stringValue = [item objectForKey:@"Value"] != nil ? [item objectForKey:@"Value"] : item;
		}
	}
	else if (outlineView == _pinConfigurationOutlineView)
	{
		NSString *nid = [tableColumn identifier];
		AudioNode *audioNode = item;
		
		if ([nid intValue] == 1)
		{
			NSPinCellView *pinCellView = (NSPinCellView *)result;
			
			if (pinCellView)
			{
				if (item)
					[pinCellView setItem:item isSelected:NO];
			}
		}
		else
		{
			switch ([nid intValue])
			{
				case 2:
					result.textField.stringValue = audioNode.nodeString;
					break;
				case 3:
					result.textField.stringValue = audioNode.pinDefaultString;
					break;
				case 4:
					result.textField.stringValue = audioNode.directionString;
					break;
				case 5:
					result.textField.stringValue = [NSString pinDefaultDevice:audioNode.device];
					break;
				case 6:
					result.textField.stringValue = [NSString pinConnector:audioNode.connector];
					break;
				case 7:
					result.textField.stringValue = [NSString pinPort:audioNode.port];
					break;
				case 8:
					result.textField.stringValue = [NSString pinGrossLocation:audioNode.grossLocation];
					break;
				case 9:
					result.textField.stringValue = [NSString pinLocation:audioNode.grossLocation geometricLocation:audioNode.geometricLocation];
					break;
				case 10:
					result.textField.stringValue = [NSString pinColor:[audioNode color]];
					break;
				case 11:
					result.textField.intValue = audioNode.group;
					break;
				case 12:
					result.textField.intValue = [audioNode index];
					break;
				case 13:
					result.textField.stringValue = (audioNode.eapd & HDA_EAPD_BTL_ENABLE_EAPD ? [NSString stringWithFormat:@"0x%1X", audioNode.eapd] : @"-");
					break;
				default:
					break;
			}
		}
	}
	
	return result;
}

- (IBAction)displaySettingsChanged:(id)sender
{
	Display *display;
	NSInteger index;
	
	if (![self getCurrentlySelectedDisplay:&display index:index])
		return;

	display.eDIDIndex = (int)[_edidPopupButton indexOfSelectedItem];
	display.iconIndex = (int)[_iconComboBox indexOfSelectedItem];
	display.resolutionIndex = (int)[_resolutionComboBox indexOfSelectedItem];
	display.fixMonitorRanges = [_fixMonitorRangesButton state];
	display.injectAppleInfo = [_injectAppleInfoButton state];
	display.forceRGBMode = [_forceRGBModeButton state];
	display.patchColorProfile = [_patchColorProfileButton state];
	display.ignoreDisplayPrefs = [_ignoreDisplayPrefsButton state];
}

- (IBAction)platformIDButtonClicked:(id)sender
{
	NSButton *button = (NSButton *)sender;
	NSString *identifier = button.identifier;
	
	if ([identifier isEqualToString:@"GoToCurrent"])
	{
		[self setPlatformID:_platformID];
	}
	else if ([identifier isEqualToString:@"Reload"])
	{
		[self populateFramebufferList];
	}
}

- (IBAction)patchButtonClicked:(id)sender
{
	if (sender == _kextsToPatchHexPatchRadioButton ||
		sender == _kextsToPatchBase64PatchRadioButton ||
		sender == _devicePropertiesPatchRadioButton ||
		sender == _iASLDSLSourcePatchRadioButton)
	{
		_settings.KextsToPatchHex = [_kextsToPatchHexPatchRadioButton state];
		_settings.KextsToPatchBase64 = [_kextsToPatchBase64PatchRadioButton state];
		_settings.DeviceProperties = [_devicePropertiesPatchRadioButton state];
		_settings.iASLDSLSource = [_iASLDSLSourcePatchRadioButton state];
	}
	if (sender == _autoDetectChangesButton)
	{
		_settings.AutoDetectChanges = [_autoDetectChangesButton state];
	}
	else if (sender == _useAllDataMethodButton)
	{
		_settings.UseAllDataMethod = [_useAllDataMethodButton state];
	}
	else if (sender == _allPatchButton)
	{
		_settings.PatchAll = [_allPatchButton state];
	}
	else if (sender == _connectorsPatchButton)
	{
		_settings.PatchConnectors = [_connectorsPatchButton state];
	}
	else if (sender == _vramPatchButton)
	{
		_settings.PatchVRAM = [_vramPatchButton state];
	}
	else if (sender == _graphicDevicePatchButton)
	{
		_settings.PatchGraphicDevice = [_graphicDevicePatchButton state];
	}
	else if (sender == _audioDevicePatchButton)
	{
		_settings.PatchAudioDevice = [_audioDevicePatchButton state];
	}
	else if (sender == _pciDevicesPatchButton)
	{
		_settings.PatchPCIDevices = [_pciDevicesPatchButton state];
	}
	else if (sender == _edidPatchButton)
	{
		_settings.PatchEDID = [_edidPatchButton state];
	}
	else if (sender == _dvmtPrealloc32MB)
	{
		_settings.DVMTPrealloc32MB = [_dvmtPrealloc32MB state];
		
		[self resetAutoPatching];
		[self updateFramebufferList];
	}
	else if (sender == _vram2048MB)
	{
		_settings.VRAM2048MB = [_vram2048MB state];

		[self resetAutoPatching];
		[self updateFramebufferList];
	}
	else if (sender == _disableeGPUButton)
	{
		_settings.DisableeGPU = [_disableeGPUButton state];
	}
	else if (sender == _enableHDMI20Button)
	{
		_settings.EnableHDMI20 = [_enableHDMI20Button state];
	}
	else if (sender == _dptoHDMIButton)
	{
		_settings.DPtoHDMI = [_dptoHDMIButton state];

		[self resetAutoPatching];
		[self updateFramebufferList];
	}
	else if (sender ==_useIntelHDMIButton)
	{
		_settings.UseIntelHDMI = [_useIntelHDMIButton state];
	}
	else if (sender == _gfxYTileFixButton)
	{
		_settings.GfxYTileFix = [_gfxYTileFixButton state];
	}
	else if (sender == _hotplugRebootFixButton)
	{
		_settings.HotplugRebootFix = [_hotplugRebootFixButton state];
		
		[self resetAutoPatching];
		[self updateFramebufferList];
	}
	else if (sender == _hdmiInfiniteLoopFixButton)
	{
		_settings.HDMIInfiniteLoopFix = [_hdmiInfiniteLoopFixButton state];
		
		[self resetAutoPatching];
		[self updateFramebufferList];
	}
	else if (sender == _dpcdMaxLinkRateButton)
	{
		_settings.DPCDMaxLinkRateFix = [_dpcdMaxLinkRateButton state];
		
		[self resetAutoPatching];
		[self updateFramebufferList];
	}
	else if (sender == _fbPortLimitButton)
	{
		_settings.FBPortLimit = [_fbPortLimitButton state];

		[self resetAutoPatching];
		[self updateFramebufferList];
	}
	else if (sender == _injectDeviceIDButton)
	{
		_settings.InjectDeviceID = [_injectDeviceIDButton state];
	}
	else if (sender == _spoofAudioDeviceIDButton)
	{
		_settings.SpoofAudioDeviceID = [_spoofAudioDeviceIDButton state];
	}
	else if (sender == _injectFakeIGPUButton)
	{
		_settings.InjectFakeIGPU = [_injectFakeIGPUButton state];
	}
	else if (sender == _usbPortLimitButton)
	{
		_settings.USBPortLimit = [_usbPortLimitButton state];
	}
}

- (IBAction)lspconButtonClicked:(id)sender
{
	if (sender == _lspconEnableDriverButton)
	{
		_settings.LSPCON_Enable = [_lspconEnableDriverButton state];
	}
	else if (sender == _lspconAutoDetectRadioButton || sender == _lspconConnectorRadioButton)
	{
		_settings.LSPCON_AutoDetect = [_lspconAutoDetectRadioButton state];
		_settings.LSPCON_Connector = [_lspconConnectorRadioButton state];
	}
	else if (sender == _lspconConnectorComboBox)
	{
		_settings.LSPCON_ConnectorIndex = (uint32_t)[_lspconConnectorComboBox indexOfSelectedItem];
	}
	else if (sender == _lspconPreferredModeButton)
	{
		_settings.LSPCON_PreferredMode = [_lspconPreferredModeButton state];
	}
	else if (sender == _lspconPreferredModeComboBox)
	{
		_settings.LSPCON_PreferredModeIndex = (uint32_t)[_lspconPreferredModeComboBox indexOfSelectedItem];
	}
}

- (IBAction)patchComboBoxDidChange:(id)sender
{
	NSComboBox *comboBox = (NSComboBox *)sender;
	NSString *identifier = comboBox.identifier;
	
	if ([identifier isEqualToString:@"DPCDMaxLinkRate"])
	{
		_settings.DPCDMaxLinkRate = (uint32_t)[_dpcdMaxLinkRateComboBox indexOfSelectedItem];

		[self updateFramebufferList];
	}
	else if ([identifier isEqualToString:@"FBPortLimit"])
	{
		_settings.FBPortCount = (uint32_t)[_fbPortLimitComboBox indexOfSelectedItem] + 1;
		
		[self updateFramebufferList];
	}
	else if ([identifier isEqualToString:@"InjectDeviceID"])
	{
	}
}

- (IBAction)bootloaderComboBoxDidChange:(id)sender
{
	NSComboBox *comboBox = (NSComboBox *)sender;
	NSString *identifier = comboBox.identifier;
	
	if ([identifier isEqualToString:@"Bootloader"])
	{
		_settings.SelectedBootloader = (uint32_t)[_bootloaderComboBox indexOfSelectedItem];
		
		[self initBootloaderDownloader:@"forced"];
	}
}

- (IBAction)infoComboBoxDidChange:(id)sender
{
	NSComboBox *comboBox = (NSComboBox *)sender;
	NSString *identifier = comboBox.identifier;
	
	if ([identifier isEqualToString:@"Model"])
	{
		[self updateModelInfo];
	}
}

- (IBAction)generateSerialComboBoxDidChange:(id)sender
{
	NSComboBox *comboBox = (NSComboBox *)sender;
	NSString *identifier = comboBox.identifier;
	
	if ([identifier isEqualToString:@"Model"])
	{
		[self updateGenerateSerialInfo];
	}
}

- (IBAction)generateSerialButtonDidChange:(id)sender
{
	NSComboBox *comboBox = (NSComboBox *)sender;
	NSString *identifier = comboBox.identifier;
	
	if ([identifier isEqualToString:@"CheckSerial1"])
	{
		[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://everymac.com/ultimate-mac-lookup/?search_keywords=%@", _generateSerialNumber]]];
	}
	else if ([identifier isEqualToString:@"CheckSerial2"])
	{
		[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://checkcoverage.apple.com/us/en/?sn=%@", _generateSerialNumber]]];
	}
	else if ([identifier isEqualToString:@"GoToCurrent"])
	{
		[_generateSerialModelInfoComboBox selectItemWithObjectValue:_modelIdentifier];
		
		[self updateGenerateSerialInfo];
	}
	else if ([identifier isEqualToString:@"Refresh"])
	{
		[self updateGenerateSerialInfo];
	}
}

- (uint32_t)getPlatformID
{
	NSString *platformIDString = [_platformIDComboBox objectValueOfSelectedItem];
	
	if (platformIDString == nil)
		return 0;
	
	uint32_t platformID = 0;
	NSScanner *scanner = [NSScanner scannerWithString:platformIDString];
	[scanner scanHexInt:&platformID];
	
	return platformID;
}

- (void)outputDevicePropertiesPatch
{
	NSMutableDictionary *configDictionary = [NSMutableDictionary dictionary];
	
	getConfigDictionary(self, configDictionary, false);
	
	if (_settings.USBPortLimit)
	{
		if ([self isBootloaderOpenCore])
			[OpenCore applyKextsToPatchWith:configDictionary name:@"config_patches" inDirectory:@"USB"];
		else
			[Clover applyKextsToPatchWith:configDictionary name:@"config_patches" inDirectory:@"USB"];
	}
	
	NSError *error;
	NSData *infoData = [NSPropertyListSerialization dataWithPropertyList:configDictionary format:NSPropertyListXMLFormat_v1_0 options:kNilOptions error:&error];
	NSString *infoString = [[NSString alloc] initWithData:infoData encoding:NSUTF8StringEncoding];
	
	if (infoString == nil)
		return;
	
	[self appendTextView:_patchOutputTextView text:infoString];
	
	[infoString release];
}

- (bool)outputKextsToPatchWithName:(NSString *)name originalArray:(vector<uint32_t>&)originalUint32Array modifiedArray:(vector<uint32_t>&)modifiedUint32Array offset:(int32_t)offset size:(int32_t)size
{
	NSString *platformIDString = [_platformIDComboBox objectValueOfSelectedItem];
	
	if (!_settings.KextsToPatchHex && !_settings.KextsToPatchBase64)
		return false;
	
	if (_settings.KextsToPatchHex)
	{
		[self appendTextView:_patchOutputTextView text:@"Find: "];
		
		for (int i = 0; i < size / 4; i++)
			[self appendTextViewWithFormat:_patchOutputTextView format:@"%08X ", swapByteOrder(originalUint32Array[offset + i])];
		
		[self appendTextView:_patchOutputTextView text:@"\nReplace: "];
		
		for (int i = 0; i < size / 4; i++)
			[self appendTextViewWithFormat:_patchOutputTextView format:@"%08X ", swapByteOrder(modifiedUint32Array[offset + i])];
	}
	else if (_settings.KextsToPatchBase64)
	{
		NSMutableData *originalData = [NSMutableData dataWithBytes:&originalUint32Array[offset] length:size];
		NSMutableData *modifiedData = [NSMutableData dataWithBytes:&modifiedUint32Array[offset] length:size];
		NSString *base64OriginalEncoded = [originalData base64EncodedStringWithOptions:0];
		NSString *base64ModifiedEncoded = [modifiedData base64EncodedStringWithOptions:0];
		
		[self appendTextView:_patchOutputTextView text:@"Find: "];
		[self appendTextView:_patchOutputTextView text:base64OriginalEncoded];
		[self appendTextView:_patchOutputTextView text:@"\nReplace: "];
		[self appendTextView:_patchOutputTextView text:base64ModifiedEncoded];
	}
	
	[self appendTextViewWithFormat:_patchOutputTextView format:@"\rComment: %@ %@ Patch by Hackintool (credit headkaze)\r\r", platformIDString, name];
	
	return true;
}

- (bool)showAlert:(NSString *)message text:(NSString *)text
{
	NSAlert *alert = [[[NSAlert alloc] init] autorelease];
	[alert setMessageText:GetLocalizedString(message)];
	[alert setInformativeText:GetLocalizedString(text)];
	[alert addButtonWithTitle:GetLocalizedString(@"Cancel")];
	[alert addButtonWithTitle:GetLocalizedString(@"OK")];
	[alert setAlertStyle:NSWarningAlertStyle];
	
	[alert beginSheetModalForWindow:_window completionHandler:^(NSModalResponse returnCode)
	 {
		 [NSApp stopModalWithCode:returnCode];
	 }];
	
	return ([NSApp runModalForWindow:_window] != NSAlertFirstButtonReturn);
}

- (bool)hasDataChangedWithOriginalArray:(vector<uint32_t>&)originalUint32Array ModifiedArray:(vector<uint32_t>&)modifiedUint32Array Offset:(int32_t)offset Size:(int32_t)size
{
	for (int i = 0; i < size / 4; i++)
	{
		if (originalUint32Array[offset + i] != modifiedUint32Array[offset + i])
			return true;
	}
	
	return false;
}

- (bool)detectFramebufferChanges:(int32_t&)changeStart changeEnd:(int32_t&)changeEnd framebufferSize:(uint32_t&)framebufferSize connectorsStart:(uint32_t&)connectorsStart connectorsSize:(uint32_t&)connectorsSize vramStart:(uint32_t&)vramStart vramSize:(uint32_t&)vramSize originalUint32Array:(vector<uint32_t>&)originalUint32Array modifiedUint32Array:(vector<uint32_t>&)modifiedUint32Array allHasModified:(bool&)allHasModified connectorsHasModified:(bool&)connectorsHasModified vramHasModified:(bool&)vramHasModified
{
	changeStart = -1;
	changeEnd = -1;
	framebufferSize = 0;
	connectorsStart = 0;
	connectorsSize = 0;
	vramStart = 0;
	vramSize = 0;
	NSInteger intelGen = [_intelGenComboBox indexOfSelectedItem];
	NSInteger platformIDIndex = [_platformIDComboBox indexOfSelectedItem];
	
	if (intelGen == -1 || platformIDIndex == -1)
		return false;
	
	uint32_t *originalFramebufferPointer, *modifiedFramebufferPointer;
	connectorsSize = (IS_ICELAKE(intelGen) ? sizeof(ConnectorInfoICL) * 4 : sizeof(ConnectorInfo) * 4);
	vramSize = (intelGen == IGHaswell ? 20 : 16);
	
	switch (intelGen)
	{
		case IGSandyBridge:
		{
			originalFramebufferPointer = reinterpret_cast<uint32_t *>(&reinterpret_cast<FramebufferSNB *>(_originalFramebufferList)[platformIDIndex]);
			modifiedFramebufferPointer = reinterpret_cast<uint32_t *>(&reinterpret_cast<FramebufferSNB *>(_modifiedFramebufferList)[platformIDIndex]);
			framebufferSize = sizeof(FramebufferSNB);
			connectorsStart = offsetof(FramebufferSNB, connectors) / 4;
			vramStart = offsetof(FramebufferSNB, fMobile) / 4;
			
			break;
		}
		case IGIvyBridge:
		{
			originalFramebufferPointer = reinterpret_cast<uint32_t *>(&reinterpret_cast<FramebufferIVB *>(_originalFramebufferList)[platformIDIndex]);
			modifiedFramebufferPointer = reinterpret_cast<uint32_t *>(&reinterpret_cast<FramebufferIVB *>(_modifiedFramebufferList)[platformIDIndex]);
			framebufferSize = sizeof(FramebufferIVB);
			connectorsStart = offsetof(FramebufferIVB, connectors) / 4;
			vramStart = offsetof(FramebufferIVB, fMobile) / 4;
			
			break;
		}
		case IGHaswell:
		{
			originalFramebufferPointer = reinterpret_cast<uint32_t *>(&reinterpret_cast<FramebufferHSW *>(_originalFramebufferList)[platformIDIndex]);
			modifiedFramebufferPointer = reinterpret_cast<uint32_t *>(&reinterpret_cast<FramebufferHSW *>(_modifiedFramebufferList)[platformIDIndex]);
			framebufferSize = sizeof(FramebufferHSW);
			connectorsStart = offsetof(FramebufferHSW, connectors) / 4;
			vramStart = offsetof(FramebufferHSW, fMobile) / 4;
			
			break;
		}
		case IGBroadwell:
		{
			originalFramebufferPointer = reinterpret_cast<uint32_t *>(&reinterpret_cast<FramebufferBDW *>(_originalFramebufferList)[platformIDIndex]);
			modifiedFramebufferPointer = reinterpret_cast<uint32_t *>(&reinterpret_cast<FramebufferBDW *>(_modifiedFramebufferList)[platformIDIndex]);
			framebufferSize = sizeof(FramebufferBDW);
			connectorsStart = offsetof(FramebufferBDW, connectors) / 4;
			vramStart = offsetof(FramebufferBDW, fMobile) / 4;
			
			break;
		}
		case IGSkylake:
		case IGKabyLake:
		{
			originalFramebufferPointer = reinterpret_cast<uint32_t *>(&reinterpret_cast<FramebufferSKL *>(_originalFramebufferList)[platformIDIndex]);
			modifiedFramebufferPointer = reinterpret_cast<uint32_t *>(&reinterpret_cast<FramebufferSKL *>(_modifiedFramebufferList)[platformIDIndex]);
			framebufferSize = sizeof(FramebufferSKL);
			connectorsStart = offsetof(FramebufferSKL, connectors) / 4;
			vramStart = offsetof(FramebufferSKL, fMobile) / 4;
			
			break;
		}
		case IGCoffeeLake:
		{
			originalFramebufferPointer = reinterpret_cast<uint32_t *>(&reinterpret_cast<FramebufferCFL *>(_originalFramebufferList)[platformIDIndex]);
			modifiedFramebufferPointer = reinterpret_cast<uint32_t *>(&reinterpret_cast<FramebufferCFL *>(_modifiedFramebufferList)[platformIDIndex]);
			framebufferSize = sizeof(FramebufferCFL);
			connectorsStart = offsetof(FramebufferCFL, connectors) / 4;
			vramStart = offsetof(FramebufferCFL, fMobile) / 4;
			
			break;
		}
		case IGCannonLake:
		{
			originalFramebufferPointer = reinterpret_cast<uint32_t *>(&reinterpret_cast<FramebufferCNL *>(_originalFramebufferList)[platformIDIndex]);
			modifiedFramebufferPointer = reinterpret_cast<uint32_t *>(&reinterpret_cast<FramebufferCNL *>(_modifiedFramebufferList)[platformIDIndex]);
			framebufferSize = sizeof(FramebufferCNL);
			connectorsStart = offsetof(FramebufferCNL, connectors) / 4;
			vramStart = offsetof(FramebufferCNL, fMobile) / 4;
			
			break;
		}
		case IGIceLakeLP:
		{
			originalFramebufferPointer = reinterpret_cast<uint32_t *>(&reinterpret_cast<FramebufferICLLP *>(_originalFramebufferList)[platformIDIndex]);
			modifiedFramebufferPointer = reinterpret_cast<uint32_t *>(&reinterpret_cast<FramebufferICLLP *>(_modifiedFramebufferList)[platformIDIndex]);
			framebufferSize = sizeof(FramebufferICLLP);
			connectorsStart = offsetof(FramebufferICLLP, connectors) / 4;
			vramStart = offsetof(FramebufferICLLP, fMobile) / 4;
			
			break;
		}
		case IGIceLakeHP:
		{
			originalFramebufferPointer = reinterpret_cast<uint32_t *>(&reinterpret_cast<FramebufferICLHP *>(_originalFramebufferList)[platformIDIndex]);
			modifiedFramebufferPointer = reinterpret_cast<uint32_t *>(&reinterpret_cast<FramebufferICLHP *>(_modifiedFramebufferList)[platformIDIndex]);
			framebufferSize = sizeof(FramebufferICLHP);
			connectorsStart = offsetof(FramebufferICLHP, connectors) / 4;
			vramStart = offsetof(FramebufferICLHP, fMobile) / 4;
			
			break;
		}
	}
	
	for (int i = 0; i < framebufferSize / 4; i++)
	{
		uint32_t originalValue = *originalFramebufferPointer++;
		uint32_t modifiedValue = *modifiedFramebufferPointer++;
		
		if (originalValue != modifiedValue)
		{
			if (changeStart == -1)
				changeStart = i;
			
			changeEnd = i;
		}
		
		originalUint32Array.push_back(originalValue);
		modifiedUint32Array.push_back(modifiedValue);
	}
	
	allHasModified = (changeStart >= 0 && changeEnd <= changeStart + framebufferSize / 4);
	connectorsHasModified = [self hasDataChangedWithOriginalArray:originalUint32Array ModifiedArray:modifiedUint32Array Offset:connectorsStart Size:connectorsSize];
	vramHasModified = [self hasDataChangedWithOriginalArray:originalUint32Array ModifiedArray:modifiedUint32Array Offset:vramStart Size:vramSize];
	
	return true;
}

- (bool)framebufferHasModified
{
	int32_t changeStart, changeEnd;
	uint32_t framebufferSize, connectorsStart, connectorsSize, vramStart, vramSize;
	vector<uint32_t> originalUint32Array, modifiedUint32Array;
	bool allHasModified, connectorsHasModified, vramHasModified;
	
	if (![self detectFramebufferChanges:changeStart changeEnd:changeEnd framebufferSize:framebufferSize connectorsStart:connectorsStart connectorsSize:connectorsSize vramStart:vramStart vramSize:vramSize originalUint32Array:originalUint32Array modifiedUint32Array:modifiedUint32Array allHasModified:allHasModified connectorsHasModified:connectorsHasModified vramHasModified:vramHasModified])
		return false;
	
	return (allHasModified || connectorsHasModified || vramHasModified);
}

- (void)framebufferPatch
{
	NSInteger intelGen = [_intelGenComboBox indexOfSelectedItem];
	NSInteger platformIDIndex = [_platformIDComboBox indexOfSelectedItem];
	
	if (intelGen == -1 || platformIDIndex == -1)
		return;
	
	bool isSandyBridge = (intelGen == IGSandyBridge);
	int32_t changeStart, changeEnd;
	uint32_t framebufferSize, connectorsStart, connectorsSize, vramStart, vramSize;
	vector<uint32_t> originalUint32Array, modifiedUint32Array;
	bool allHasModified, connectorsHasModified, vramHasModified;
	
	[self detectFramebufferChanges:changeStart changeEnd:changeEnd framebufferSize:framebufferSize connectorsStart:connectorsStart connectorsSize:connectorsSize vramStart:vramStart vramSize:vramSize originalUint32Array:originalUint32Array modifiedUint32Array:modifiedUint32Array allHasModified:allHasModified connectorsHasModified:connectorsHasModified vramHasModified:vramHasModified];
	
	if (!_settings.KextsToPatchHex && !_settings.KextsToPatchBase64)
		return;
	
	if (_settings.AutoDetectChanges)
	{
		if (changeStart == -1)
		{
			[self appendTextView:_patchOutputTextView text:@"No Changes Detected!\r"];
		
			return;
		}
		
		if (_settings.PatchAll && allHasModified)
		{
			uint32_t allStart = max(changeStart - 1, 0);
			uint32_t allEnd = min(changeEnd + 1, (int)framebufferSize / 4);
			uint32_t allSize = (allEnd - allStart + 1) * 4;
			[self outputKextsToPatchWithName:@"All" originalArray:originalUint32Array modifiedArray:modifiedUint32Array offset:allStart size:allSize];
		}
		
		if (_settings.PatchConnectors && connectorsHasModified)
			[self outputKextsToPatchWithName:@"Connector" originalArray:originalUint32Array modifiedArray:modifiedUint32Array offset:connectorsStart size:connectorsSize];
		
		if (!isSandyBridge && _settings.PatchVRAM && vramHasModified)
			[self outputKextsToPatchWithName:@"VRAM" originalArray:originalUint32Array modifiedArray:modifiedUint32Array offset:vramStart size:vramSize];
	}
	else
	{
		[self outputKextsToPatchWithName:@"All" originalArray:originalUint32Array modifiedArray:modifiedUint32Array offset:0 size:framebufferSize];
		[self outputKextsToPatchWithName:@"Connector" originalArray:originalUint32Array modifiedArray:modifiedUint32Array offset:connectorsStart size:connectorsSize];
		
		if (!isSandyBridge)
			[self outputKextsToPatchWithName:@"VRAM" originalArray:originalUint32Array modifiedArray:modifiedUint32Array offset:vramStart size:vramSize];
	}
}

- (IBAction)generatePatchButtonClicked:(id)sender
{
	[[[_patchOutputTextView textStorage] mutableString] setString:@""];
	
	[self framebufferPatch];
	
	if (_settings.DeviceProperties)
	{
		[self outputDevicePropertiesPatch];
		
		return;
	}
	
	if (_settings.iASLDSLSource)
	{
		appendFramebufferInfoDSL(self);
		
		return;
	}
}

- (IBAction)headsoftLogoButtonClicked:(id)sender
{
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://headsoft.com.au"]];
}

- (IBAction)vramInfoChanged:(id)sender
{
	NSInteger intelGen = [_intelGenComboBox indexOfSelectedItem];
	NSInteger platformIDIndex = [_platformIDComboBox indexOfSelectedItem];
	
	if (intelGen == -1 || platformIDIndex == -1)
		return;
	
	NSInteger row = [_vramInfoTableView rowForView:sender];
	NSTableCellView *view = [_vramInfoTableView viewAtColumn:0 row:row makeIfNecessary:NO];
	NSString *value = [sender stringValue];
	
	bool isMobile = false;
	uint32_t stolenMem = 0, fbMem = 0, unifiedMem = 0;
	uint32_t maxStolenMem = 0, totalStolenMem = 0, totalCursorMem = 0, maxOverallMem = 0;
	
	[self getMemoryIsMobile:&isMobile StolenMem:&stolenMem FBMem:&fbMem UnifiedMem:&unifiedMem MaxStolenMem:&maxStolenMem TotalStolenMem:&totalStolenMem TotalCursorMem:&totalCursorMem MaxOverallMem:&maxOverallMem];
	
	NSMutableDictionary *vramDictionary = _vramInfoArray[row];
	NSString *name = [vramDictionary objectForKey:@"Name"];

	if ([name isEqualToString:@"Stolen"])
		stolenMem = [self parseMemoryString:value];
	else if ([name isEqualToString:@"FBMem"])
		fbMem = [self parseMemoryString:value];
	else if ([name isEqualToString:@"VRAM"])
		unifiedMem = [self parseMemoryString:value];
	
	[self setStolenMem:stolenMem FBMem:fbMem UnifiedMem:unifiedMem];
	
	[self populateFramebufferInfoList];
}

- (void)loadConfig:(NSMutableDictionary *)propertyDictionary
{
	[self populateFramebufferList];
	
	bool result = NO;
	uint32_t framebufferID = 0;
	
	if (!(result = getUInt32PropertyValue(self, propertyDictionary, @"AAPL,snb-platform-id", &framebufferID)))
		result = getUInt32PropertyValue(self, propertyDictionary, @"AAPL,ig-platform-id", &framebufferID);

	if (result)
		[self setPlatformID:framebufferID];
	
	NSInteger intelGen = [_intelGenComboBox indexOfSelectedItem];
	NSInteger platformIDIndex = [_platformIDComboBox indexOfSelectedItem];
	
	if (intelGen == -1 || platformIDIndex == -1)
		return;
	
	switch (intelGen)
	{
		case IGSandyBridge:
			applyUserPatch<FramebufferSNB>(self, propertyDictionary);
			break;
		case IGIvyBridge:
			applyUserPatch<FramebufferIVB>(self, propertyDictionary);
			break;
		case IGHaswell:
			applyUserPatch<FramebufferHSW>(self, propertyDictionary);
			break;
		case IGBroadwell:
			applyUserPatch<FramebufferBDW>(self, propertyDictionary);
			break;
		case IGSkylake:
		case IGKabyLake:
			applyUserPatch<FramebufferSKL>(self, propertyDictionary);
			break;
		case IGCoffeeLake:
			applyUserPatch<FramebufferCFL>(self, propertyDictionary);
			break;
		case IGCannonLake:
			applyUserPatch<FramebufferCNL>(self, propertyDictionary);
			break;
		case IGIceLakeLP:
			applyUserPatch<FramebufferICLLP>(self, propertyDictionary);
			break;
		case IGIceLakeHP:
			applyUserPatch<FramebufferICLHP>(self, propertyDictionary);
			break;
	}
	
	[self populateFramebufferInfoList];
	[self populateConnectorFlagsList];
	
	[_connectorInfoTableView reloadData];
	[_connectorFlagsTableView reloadData];
}

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename
{
	_fileName = [filename retain];
	
	NSMutableDictionary *configDictionary = [NSMutableDictionary dictionaryWithContentsOfFile:_fileName];
	NSMutableDictionary *propertyDictionary = ([self isBootloaderOpenCore] ? [OpenCore getDevicePropertiesDictionaryWith:configDictionary typeName:@"Add"] : [Clover getDevicesPropertiesDictionaryWith:configDictionary]);
	NSMutableDictionary *pciDeviceDictionary;
	
	if (![self tryGetGPUDeviceDictionary:&pciDeviceDictionary])
		return NO;
	
	NSString *devicePath = [pciDeviceDictionary objectForKey:@"DevicePath"];
	NSMutableDictionary *gpuProperties = [propertyDictionary objectForKey:devicePath];
	
	if (gpuProperties == nil)
		return NO;
	
	[self loadConfig:gpuProperties];
	
	return YES;
}

- (IBAction)openDocument:(id)sender
{
	NSOpenPanel *openPanel = [NSOpenPanel openPanel];
	[openPanel setCanChooseFiles:YES];
	[openPanel setAllowsMultipleSelection:NO];
	[openPanel setCanChooseDirectories:NO];
	
	[openPanel beginSheetModalForWindow:_window completionHandler:^(NSModalResponse returnCode)
	 {
		 [NSApp stopModalWithCode:returnCode];
	 }];
	
	if ([NSApp runModalForWindow:_window] != NSOKButton)
		return;
	
	for (NSURL *url in [openPanel URLs])
	{
		[self application:NSApp openFile:[url path]];
		
		[[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:url];

		break;
	}
}

- (IBAction)fileImportMenuItemClicked:(id)sender
{
	NSMenuItem *menuItem = (NSMenuItem *)sender;
	NSString *identifier = [menuItem identifier];
	
	bool state = menuItem.state;
	
	if (state)
		return;
	
	[menuItem setState:!state];
	
	if (!state)
	{
		[_currentVersionMenuItem setState:false];
		[_macOS_10_13_6_MenuItem setState:false];
		[_macOS_10_14_MenuItem setState:false];
	}

	if ([identifier isEqualToString:@"IOReg Dump (Native)"])
	{
		[_importIORegPatchedMenuItem setState:state];
	}
	else if ([identifier isEqualToString:@"IOReg Dump (Patched)"])
	{
		[_importIORegNativeMenuItem setState:state];
	}
	
	_fileName = nil;
	
	[self populateFramebufferList];
}

- (IBAction)fileExportBootloaderConfig:(id)sender
{
	NSMutableDictionary *configDictionary = nil;
	NSString *configPath = nil;
	
	if (![Config openConfig:self configDictionary:&configDictionary configPath:&configPath])
		return;
	
	getConfigDictionary(self, configDictionary, false);

	// ---------------------------------------------
	// config.plist/KernelAndKextPatches/KextsToPatch
	// ---------------------------------------------
	
	if (_settings.USBPortLimit)
	{
		if ([self isBootloaderOpenCore])
			[OpenCore applyKextsToPatchWith:configDictionary name:@"config_patches" inDirectory:@"USB"];
		else
			[Clover applyKextsToPatchWith:configDictionary name:@"config_patches" inDirectory:@"USB"];
	}
	
	// ---------------------------------------------
	
	[configDictionary writeToFile:configPath atomically:YES];
}

- (IBAction)fileExportFramebufferText:(id)sender
{
	NSInteger intelGen = [_intelGenComboBox indexOfSelectedItem];
	NSInteger platformIDIndex = [_platformIDComboBox indexOfSelectedItem];
	
	if (intelGen == -1 || platformIDIndex == -1)
		return;
	
	NSSavePanel *savePanel = [NSSavePanel savePanel];
	NSString *intelGenString = [_intelGenComboBox objectValueOfSelectedItem];
	[savePanel setNameFieldStringValue:[NSString stringWithFormat:@"%@.txt", intelGenString]];
	
	[savePanel beginSheetModalForWindow:_window completionHandler:^(NSModalResponse returnCode)
	 {
		 [NSApp stopModalWithCode:returnCode];
	 }];
	
	if ([NSApp runModalForWindow:_window] != NSOKButton)
		return;
	
	NSString *framebufferTextPath = [[savePanel URL] path];
		
	[self saveFramebufferText:framebufferTextPath];
}

- (IBAction)fileExportFramebufferBinary:(id)sender
{
	NSInteger intelGen = [_intelGenComboBox indexOfSelectedItem];
	NSInteger platformIDIndex = [_platformIDComboBox indexOfSelectedItem];
	
	if (intelGen == -1 || platformIDIndex == -1)
		return;
	
	NSSavePanel *savePanel = [NSSavePanel savePanel];
	NSString *intelGenString = [_intelGenComboBox objectValueOfSelectedItem];
	[savePanel setNameFieldStringValue:[NSString stringWithFormat:@"%@.bin", intelGenString]];
	
	[savePanel beginSheetModalForWindow:_window completionHandler:^(NSModalResponse returnCode)
	 {
		 [NSApp stopModalWithCode:returnCode];
	 }];
	
	if ([NSApp runModalForWindow:_window] != NSOKButton)
		return;
	
	NSString *framebufferTextPath = [[savePanel URL] path];
	
	[self saveFramebufferBinary:framebufferTextPath];
}

- (IBAction)fileQuit:(id)sender
{
	[NSApp terminate:self];
}

- (IBAction)infoPrint:(id)sender
{
	NSPrintOperation *printOperation = [NSPrintOperation printOperationWithView:_infoTextView];
	NSPrintInfo *printInfo = printOperation.printInfo;
	[printInfo setHorizontalPagination:NSAutoPagination];
	[printInfo setVerticalPagination:NSAutoPagination];
	[printInfo setHorizontallyCentered:YES];
	[printInfo setVerticallyCentered:YES];
	[printInfo setLeftMargin:0.0];
	[printInfo setRightMargin:0.0];
	[printInfo setTopMargin:0.0];
	[printInfo setBottomMargin:0.0];
	[printInfo.dictionary setObject:@YES forKey:NSPrintHeaderAndFooter];
	[printOperation runOperation];
}

- (IBAction)cancelButtonClicked:(id)sender
{
	NSView *superView = [sender superview];
	
	[_window endSheet:superView.window returnCode:NSModalResponseCancel];
}

- (IBAction)okButtonClicked:(id)sender
{
	NSView *superView = [sender superview];
	
	[_window endSheet:superView.window returnCode:NSModalResponseOK];
}

- (IBAction)payPalButtonClicked:(id)sender
{
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://www.paypal.com/cgi-bin/webscr?cmd=_donations&business=benbaker@headsoft.com.au&item_name=Hackintool&currency_code=USD"]];
}

- (IBAction)framebufferMenuItemClicked:(id)sender
{
	NSMenuItem *menuItem = (NSMenuItem *)sender;
	NSString *identifier = [menuItem identifier];
	
	bool state = menuItem.state;
	
	if (state)
		return;
	
	[menuItem setState:!state];
	
	if (!state)
	{
		[_importIORegNativeMenuItem setState:false];
		[_importIORegPatchedMenuItem setState:false];
	}
	
	if ([identifier isEqualToString:@"Current Version"])
	{
		[_macOS_10_13_6_MenuItem setState:state];
		[_macOS_10_14_MenuItem setState:state];
	}
	else if ([identifier isEqualToString:@"macOS 10.13.6"])
	{
		[_currentVersionMenuItem setState:state];
		[_macOS_10_14_MenuItem setState:state];
	}
	else if ([identifier isEqualToString:@"macOS 10.14"])
	{
		[_currentVersionMenuItem setState:state];
		[_macOS_10_13_6_MenuItem setState:state];
	}
	
	_fileName = nil;
	
	[self populateFramebufferList];
}

- (IBAction)patchMenuItemClicked:(id)sender
{
	NSMenuItem *menuItem = (NSMenuItem *)sender;
	NSString *identifier = [menuItem identifier];
	
	if ([identifier isEqualToString:@"Import KextsToPatch"])
	{
		if (_originalFramebufferList == NULL || _modifiedFramebufferList == NULL)
			return;
		
		NSRect frame = [_importKextsToPatchWindow frame];
		frame.size = NSMakeSize(_window.frame.size.width, frame.size.height);
		[_importKextsToPatchWindow setFrame:frame display:NO animate:NO];
		
		[_window beginSheet:_importKextsToPatchWindow completionHandler:^(NSModalResponse returnCode)
		 {
			 switch (returnCode)
			 {
				 case NSModalResponseCancel:
					 break;
				 case NSModalResponseOK:
				 {
					 NSData *findData = stringToData([_findTextField stringValue]);
					 NSData *replaceData = stringToData([_replaceTextField stringValue]);
					 
					 if ([findData length] == 0 || [replaceData length] == 0)
						 break;
					 
					 bool result = applyFindAndReplacePatch(findData, replaceData, _originalFramebufferList, _modifiedFramebufferList, _framebufferSize * _framebufferCount, FIND_AND_REPLACE_COUNT);
					 
					 [[NSOperationQueue mainQueue] addOperationWithBlock:^
					  {
						  [self showAlert:@"Importing KextsToPatch" text:result ? @"Patch Success!" : @"Patch Fail!"];
					  }];

					 [self updateFramebufferList];
					 break;
				 }
				 default:
					 break;
			 }
		 }];
		
		return;
	}
	else if ([identifier isEqualToString:@"AzulPatcher4600"])
	{
		_fileName = nil;
		_settings.IntelGen = @"Haswell";
		_settings.PlatformID = @"0x0A260006";
		_settings.InjectDeviceID = true;
		_settings.UseAllDataMethod = true;
		_settings.DisableeGPU = true;
		
		[_intelGenComboBox selectItemWithObjectValue:_settings.IntelGen];
		[_platformIDComboBox selectItemWithObjectValue:_settings.PlatformID];
		[_injectDeviceIDComboBox selectItemWithObjectValue:@"0x0412: Intel HD Graphics 4600"];
		
		[self updateSettingsGUI];
		
		if (_originalFramebufferList == NULL || _modifiedFramebufferList == NULL)
			return;
		
		// Disable port 0204
		const uint8_t find[]    = {0x02, 0x04, 0x09, 0x00, 0x00, 0x04, 0x00, 0x00, 0x87, 0x00, 0x00, 0x00};
		const uint8_t replace[] = {0xff, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x40, 0x00, 0x00, 0x00};

		// 9MB cursor bytes, 2 ports only
		const uint8_t find1[]    = {0x06, 0x00, 0x26, 0x0a, 0x01, 0x03, 0x03, 0x03, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x30, 0x01, 0x00, 0x00, 0x60, 0x00};
		const uint8_t replace1[] = {0x06, 0x00, 0x26, 0x0a, 0x01, 0x03, 0x02, 0x02, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x30, 0x01, 0x00, 0x00, 0x90, 0x00};

		// HDMI audio
		const uint8_t find2[]    = {0x01, 0x05, 0x09, 0x00, 0x00, 0x04, 0x00, 0x00, 0x87, 0x00, 0x00, 0x00};
		const uint8_t replace2[] = {0x01, 0x05, 0x12, 0x00, 0x00, 0x08, 0x00, 0x00, 0x87, 0x00, 0x00, 0x00};
		
		bool result = applyFindAndReplacePatch([NSData dataWithBytes:find length:sizeof(find)], [NSData dataWithBytes:replace length:sizeof(replace)], _originalFramebufferList, _modifiedFramebufferList, _framebufferSize * _framebufferCount, FIND_AND_REPLACE_COUNT);
		result = applyFindAndReplacePatch([NSData dataWithBytes:find1 length:sizeof(find1)], [NSData dataWithBytes:replace1 length:sizeof(replace1)], _originalFramebufferList, _modifiedFramebufferList, _framebufferSize * _framebufferCount, FIND_AND_REPLACE_COUNT);
		result = applyFindAndReplacePatch([NSData dataWithBytes:find2 length:sizeof(find2)], [NSData dataWithBytes:replace2 length:sizeof(replace2)], _originalFramebufferList, _modifiedFramebufferList, _framebufferSize * _framebufferCount, FIND_AND_REPLACE_COUNT);

		[self updateFramebufferList];
		
		return;
	}
	
	bool state = menuItem.state;
	[menuItem setState:!state];
	
	if ([identifier isEqualToString:@"Apply Current Patches"])
		_settings.ApplyCurrentPatches = [_applyCurrentPatchesMenuItem state];
	
	[self populateFramebufferList];
}

- (IBAction)audioButtonClicked:(id)sender
{
	NSButton *button = (NSButton *)sender;
	NSString *identifier = [button identifier];
	
	if ([identifier isEqualToString:@"Info"])
	{
		/* [_infoTextView setString:@""];
		[_infoTextField setStringValue:@""];
		
		NSBundle *mainBundle = [NSBundle mainBundle];
		NSString *filePath = nil;

		if ((filePath = [mainBundle pathForResource:@"Audio" ofType:@"rtf"]))
			[_infoTextView readRTFDFromFile:filePath];
		
		uint32_t audioDeviceID = 0;
		bool needsSpoof = [self spoofAudioDeviceID:&audioDeviceID];
		
		[_infoTextField setStringValue:needsSpoof ? GetLocalizedString(@"* You may require Spoof Audio Device ID") : @""];
		
		NSRect frame = [_infoWindow frame];
		frame.size = NSMakeSize(_window.frame.size.width, frame.size.height);
		[_infoWindow setFrame:frame display:NO animate:NO];
		
		[_window beginSheet:_infoWindow completionHandler:^(NSModalResponse returnCode)
		 {
			 switch (returnCode)
			 {
				 case NSModalResponseCancel:
					 break;
				 case NSModalResponseOK:
					 break;
				 default:
					 break;
			 }
		 }]; */
		
		NSString *helpBookName = [[NSBundle mainBundle] objectForInfoDictionaryKey: @"CFBundleHelpBookName"];
		[[NSHelpManager sharedHelpManager] openHelpAnchor:@"Audio" inBook:helpBookName];
		
		return;
	}	
}

- (IBAction)usbButtonClicked:(id)sender
{
	NSButton *button = (NSButton *)sender;
	NSString *identifier = [button identifier];
	
	if ([identifier isEqualToString:@"Info"])
	{
		/* [_infoTextView setString:@""];
		[_infoTextField setStringValue:@""];
		
		NSBundle *mainBundle = [NSBundle mainBundle];
		NSString *filePath = nil;
		
		if ((filePath = [mainBundle pathForResource:@"USB" ofType:@"rtf"]))
			[_infoTextView readRTFDFromFile:filePath];
		
		for (NSMutableDictionary *usbControllersDictionary in _usbControllersArray)
		{
			NSNumber *usbControllerID = [usbControllersDictionary objectForKey:@"ID"];
			NSString *usbKextRequirements = [self getUSBKextRequirements:usbControllerID];
			
			if ([usbKextRequirements isEqualToString:@"None"])
				continue;
			
			[_infoTextField setStringValue:[NSString stringWithFormat:GetLocalizedString(@"You may require %@"), usbKextRequirements]];
			
			break;
		}

		NSRect frame = [_infoWindow frame];
		frame.size = NSMakeSize(_window.frame.size.width, frame.size.height);
		[_infoWindow setFrame:frame display:NO animate:NO];
		
		[_window beginSheet:_infoWindow completionHandler:^(NSModalResponse returnCode)
		 {
			 switch (returnCode)
			 {
				 case NSModalResponseCancel:
					 break;
				 case NSModalResponseOK:
					 break;
				 default:
					 break;
			 }
		 }]; */
		
		NSString *helpBookName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleHelpBookName"];
		[[NSHelpManager sharedHelpManager] openHelpAnchor:@"USB" inBook:helpBookName];
		
		return;
	}
	else if ([identifier isEqualToString:@"Delete"])
	{
		NSIndexSet *indexSex = [_usbPortsTableView selectedRowIndexes];
		NSUInteger index = [indexSex lastIndex];
		
		while (index != NSNotFound)
		{
			[_usbPortsArray removeObjectAtIndex:index];
			
			index = [indexSex indexLessThanIndex:index];
		}
		
		[_usbPortsTableView reloadData];
	}
	else if ([identifier isEqualToString:@"ClearAll"])
	{
		[_usbPortsArray removeAllObjects];
		
		[_usbPortsTableView reloadData];
	}
	else if ([identifier isEqualToString:@"Refresh"])
	{
		[self refreshUSBPorts];
		[self refreshUSBControllers];
	}
	else if ([identifier isEqualToString:@"Inject"])
	{
		[self injectUSBPorts];
	}
	else if ([identifier isEqualToString:@"Import"])
	{
		[self importUSBPorts];
	}
	else if ([identifier isEqualToString:@"Export"])
	{
		exportUSBPorts(self);
	}
}

- (IBAction)pciButtonClicked:(id)sender
{
	NSButton *button = (NSButton *)sender;
	NSString *identifier = [button identifier];
	
	if ([identifier isEqualToString:@"UpdatePCIIDs"])
	{
		if ([self downloadPCIIDs])
		{
			[self parsePCIIDs];
			[self updatePCIIDs];
			
			[self showAlert:@"PCIIDs Update" text:@"Successful!"];
		}
		else
			[self showAlert:@"PCIIDs Update" text:@"Failure!"];
	}
	else if ([identifier isEqualToString:@"Export"])
	{
		[self writePCIDevicesTable];
		[self writePCIDevicesJSON];
		[self writePCIDevicesConfig];
		[self writePCIDevicesDSL];
	}
}

- (IBAction)infoButtonClicked:(id)sender
{
	NSButton *button = (NSButton *)sender;
	NSString *identifier = [button identifier];
	
	if ([identifier isEqualToString:@"CheckSerial1"])
	{
		[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://everymac.com/ultimate-mac-lookup/?search_keywords=%@", _serialNumber]]];
	}
	else if ([identifier isEqualToString:@"CheckSerial2"])
	{
		[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://checkcoverage.apple.com/us/en/?sn=%@", _serialNumber]]];
	}
	else if ([identifier isEqualToString:@"Export"])
	{
		[self writeInfo];
	}
	else if ([identifier isEqualToString:@"GoToCurrent"])
	{
		[self selectModelInfo];
	}
	else if ([identifier isEqualToString:@"Visit"])
	{
		uint32_t index = [self getModelIndex:_modelInfoComboBox.stringValue];
		
		if (index != -1)
		{
			NSDictionary *systemDictionary = _systemsArray[index];
			NSString *url = [systemDictionary objectForKey:@"Url"];
			
			[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:url]];
		}
	}
	else if ([identifier isEqualToString:@"Visit EveryMac"])
	{
		[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://everymac.com/"]];
	}
}

- (IBAction)diskMountButtonClicked:(id)sender
{
	NSButton *button = (NSButton *)sender;
	NSInteger row = [_efiPartitionsTableView rowForView:button];
	
	if (row == -1)
		return;
	
	NSMutableArray *efiPartitionsArray = getEfiPartitionsArray(_disksArray);
	Disk *disk = efiPartitionsArray[row];
	NSString *stdoutString = nil, *stderrString = nil;
	
	if (disk.isMounted)
	{
		if ([disk unmount:&stdoutString stderrString:&stderrString])
			sendNotificationTitle(self, @"Hackintool", trimNewLine(![stderrString isEqualToString:@""] ? stderrString : stdoutString), nil, nil, nil, NO);
	}
	else
	{
		if ([disk mount:&stdoutString stderrString:&stderrString])
			sendNotificationTitle(self, @"Hackintool", trimNewLine(![stderrString isEqualToString:@""] ? stderrString : stdoutString), nil, nil, nil, NO);
	}
}

- (IBAction)diskOpenButtonClicked:(id)sender
{
	NSButton *button = (NSButton *)sender;
	NSInteger row = [_efiPartitionsTableView rowForView:button];
	
	if (row == -1)
		return;
	
	NSMutableArray *efiPartitionsArray = getEfiPartitionsArray(_disksArray);
	Disk *disk = efiPartitionsArray[row];
	
	[self open:disk];
}

- (IBAction)mountMenuClicked:(id)sender
{
	NSMenuItem *menuItem = (NSMenuItem *)sender;
	NSInteger row = _partitionSchemeTableView.clickedRow;
	
	if (row == -1)
		return;
	
	if ([menuItem.identifier isEqualToString:@"Mount"])
	{
		Disk *disk = _disksArray[row];
		NSString *stdoutString = nil, *stderrString = nil;
		
		if (disk.isMounted)
		{
			if ([disk unmount:&stdoutString stderrString:&stderrString])
				sendNotificationTitle(self, @"Hackintool", trimNewLine(![stderrString isEqualToString:@""] ? stderrString : stdoutString), nil, nil, nil, NO);
		}
		else
		{
			if ([disk mount:&stdoutString stderrString:&stderrString])
				sendNotificationTitle(self, @"Hackintool", trimNewLine(![stderrString isEqualToString:@""] ? stderrString : stdoutString), nil, nil, nil, NO);
		}
	}
	else if ([menuItem.identifier isEqualToString:@"Eject"])
	{
		Disk *disk = _disksArray[row];
		NSString *stdoutString = nil, *stderrString = nil;
		
		if ([disk eject:&stdoutString stderrString:&stderrString])
			sendNotificationTitle(self, @"Hackintool", trimNewLine(![stderrString isEqualToString:@""] ? stderrString : stdoutString), nil, nil, nil, NO);
	}
	else if ([menuItem.identifier isEqualToString:@"Open"])
	{
		Disk *disk = _disksArray[row];
		
		[self open:disk];
	}
	else if ([menuItem.identifier isEqualToString:@"DeleteAPFSContainer"])
	{
		Disk *disk = _disksArray[row];
		NSString *stdoutString = nil, *stderrString = nil;
		
		if ([disk deleteAPFSContainer:&stdoutString stderrString:&stderrString])
			sendNotificationTitle(self, @"MountEFI", trimNewLine(![stderrString isEqualToString:@""] ? stderrString : stdoutString), nil, nil, nil, NO);
	}
	else if ([menuItem.identifier isEqualToString:@"ConvertToAPFS"])
	{
		Disk *disk = _disksArray[row];
		NSString *stdoutString = nil, *stderrString = nil;
		
		if ([disk convertToAPFS:&stdoutString stderrString:&stderrString])
			sendNotificationTitle(self, @"MountEFI", trimNewLine(![stderrString isEqualToString:@""] ? stderrString : stdoutString), nil, nil, nil, NO);
	}
	else if ([menuItem.identifier isEqualToString:@"VolumeUUID"])
	{
		Disk *disk = _disksArray[row];
		
		[[NSPasteboard generalPasteboard] clearContents];
		[[NSPasteboard generalPasteboard] setString:disk.volumeUUID forType:NSStringPboardType];
	}
	else if ([menuItem.identifier isEqualToString:@"VolumePath"])
	{
		Disk *disk = _disksArray[row];
		
		[[NSPasteboard generalPasteboard] clearContents];
		[[NSPasteboard generalPasteboard] setString:(disk.volumePath != nil ? [disk.volumePath path] : @"") forType:NSStringPboardType];
	}
	else if ([menuItem.identifier isEqualToString:@"MediaUUID"])
	{
		Disk *disk = _disksArray[row];
		
		[[NSPasteboard generalPasteboard] clearContents];
		[[NSPasteboard generalPasteboard] setString:disk.mediaUUID forType:NSStringPboardType];
	}
	else if ([menuItem.identifier isEqualToString:@"BootEFI"])
	{
		Disk *disk = _disksArray[row];
		
		menuItem.state = !menuItem.state;
		
		if (menuItem.state)
			[self setBootEFI:disk.mediaUUID];
		else
			[self unsetBootEFI];
		
		[self getEfiBootDevice];
		
		updateDiskList(_disksArray, _efiBootDeviceUUID);
		
		[self refreshDisks];
	}
}

- (IBAction)installMenuClicked:(id)sender
{
	NSMenuItem *menuItem = (NSMenuItem *)sender;
	NSInteger row = _kextsTableView.clickedRow;
	
	if (row == -1)
		return;
	
	if ([menuItem.identifier isEqualToString:@"Open Url"])
	{
		NSMutableArray *kextsArray = (_settings.ShowInstalledOnly ? _installedKextsArray : _kextsArray);
		NSMutableDictionary *kextDictionary = kextsArray[row];
		NSString *projectUrl = [kextDictionary objectForKey:@"ProjectUrl"];
		
		[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:projectUrl]];
	}
}

- (IBAction)pciMenuClicked:(id)sender
{
	NSMenuItem *menuItem = (NSMenuItem *)sender;
	NSInteger row = _pciDevicesTableView.clickedRow;
	
	if (row == -1)
		return;
	
	if ([menuItem.identifier isEqualToString:@"Copy IOReg Path"])
	{
		NSMutableDictionary *pciDeviceDictionary = _pciDevicesArray[row];
		
		NSString *ioregPath = [pciDeviceDictionary objectForKey:@"IORegPath"];
		
		NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
		[pasteboard clearContents];
		[pasteboard setString:ioregPath forType:NSStringPboardType];
	}
	else if ([menuItem.identifier isEqualToString:@"Copy Device Path"])
	{
		NSMutableDictionary *pciDeviceDictionary = _pciDevicesArray[row];
		
		NSString *devicePath = [pciDeviceDictionary objectForKey:@"DevicePath"];
		
		NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
		[pasteboard clearContents];
		[pasteboard setString:devicePath forType:NSStringPboardType];
	}
}

- (IBAction)infoMenuClicked:(id)sender
{
	NSMenuItem *menuItem = (NSMenuItem *)sender;
	NSInteger row = -1;
	
	if ([menuItem.identifier isEqualToString:@"Copy Value"])
	{
		for (NSTableView *tableView in _tableViewArray)
		{
			if ((row = tableView.clickedRow) == -1)
				continue;
			
			NSView *valueView = [tableView viewAtColumn:1 row:row makeIfNecessary:NO];
			
			if ([valueView isKindOfClass:[NSTableCellView class]])
			{
				NSTableCellView *tableCellView = (NSTableCellView *)valueView;
				NSString *value = tableCellView.textField.stringValue;

				NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
				[pasteboard clearContents];
				[pasteboard setString:value forType:NSStringPboardType];
			}
			else if ([valueView isKindOfClass:[NSComboBox class]])
			{
				NSComboBox *comboBox = (NSComboBox *)valueView;
				NSString *value = comboBox.stringValue;
				
				NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
				[pasteboard clearContents];
				[pasteboard setString:value forType:NSStringPboardType];
			}
			
			break;
		}
	}
}

- (void)textDidChange:(NSNotification *)notification
{
	NSTextView *textView = notification.object;
	
	if (textView == _nvramValueTextView)
	{
		NSInteger row = [_nvramTableView selectedRow];
		
		if (row == -1)
			return;
		
		NSTableCellView *valueView = [_nvramTableView viewAtColumn:0 row:row makeIfNecessary:NO];
		NSString *name = valueView.textField.stringValue;
		id value = [_nvramDictionary objectForKey:name];
		NSString *newValue = [[_nvramValueTextView.string copy] autorelease];
		
		if ([value isKindOfClass:[NSString class]])
		{
			if ([self setNVRAMValue:name value:newValue])
				[_nvramDictionary setObject:newValue forKey:name];
		}
		else if ([value isKindOfClass:[NSData class]])
		{
			NSString *xmlString = nil;
			
			if (tryFormatXML(newValue, &xmlString, false))
			{
				NSData *newValueData = [xmlString dataUsingEncoding:NSASCIIStringEncoding];
				
				if ([self setNVRAMValue:name value:getByteString(newValueData, @"", @"%", false, true)])
					[_nvramDictionary setObject:newValueData forKey:name];
			}
			else
			{
				NSData *valueData = stringToData(newValue);
				
				if ([self setNVRAMValue:name value:getByteString(valueData, @"", @"%", false, true)])
					[_nvramDictionary setObject:valueData forKey:name];
			}
		}
		
		[_nvramTableView reloadData];
		NSIndexSet *indexSet = [NSIndexSet indexSetWithIndex:row];
		[_nvramTableView selectRowIndexes:indexSet byExtendingSelection:NO];
	}
}

- (void)controlTextDidChange:(NSNotification *)notification
{
	NSTextField *textField = notification.object;
	NSString *identifier = [textField identifier];
	
	if ([identifier isEqualToString:@"HexSequence"])
	{
		NSData *hexData = stringToData([_calcHexSequenceTextField stringValue]);
		NSData *reverseData = getReverseData(hexData);
		NSMutableString *reverseHexString = getByteString(reverseData, @" ", @"", false, true);
		NSString *base64String = [hexData base64EncodedStringWithOptions:0];
		NSString *asciiString = [[[NSString alloc] initWithData:hexData encoding:NSASCIIStringEncoding] autorelease];
		[_calcHexSequenceReverseTextField setStringValue:reverseHexString];
		[_calcBase64SequenceTextField setStringValue:base64String];
		[_calcASCIISequenceTextField setStringValue:asciiString];
	}
	else if ([identifier isEqualToString:@"Base64Sequence"])
	{
		NSData *base64Data = [[[NSData alloc] initWithBase64EncodedString:[_calcBase64SequenceTextField stringValue] options:NSDataBase64DecodingIgnoreUnknownCharacters] autorelease];
		NSData *reverseData = getReverseData(base64Data);
		NSMutableString *hexString = getByteString(base64Data, @" ", @"", false, true);
		NSMutableString *reverseHexString = getByteString(reverseData, @" ", @"", false, true);
		NSString *asciiString = [[[NSString alloc] initWithData:base64Data encoding:NSASCIIStringEncoding] autorelease];
		[_calcHexSequenceTextField setStringValue:hexString];
		[_calcHexSequenceReverseTextField setStringValue:reverseHexString];
		[_calcASCIISequenceTextField setStringValue:asciiString];
	}
	else if ([identifier isEqualToString:@"ASCIISequence"])
	{
		NSData *asciiData = [[_calcASCIISequenceTextField stringValue] dataUsingEncoding:NSASCIIStringEncoding];
		NSData *reverseData = getReverseData(asciiData);
		NSMutableString *hexString = getByteString(asciiData, @" ", @"", false, true);
		NSMutableString *reverseHexString = getByteString(reverseData, @" ", @"", false, true);
		NSString *base64String = [asciiData base64EncodedStringWithOptions:0];
		[_calcHexSequenceTextField setStringValue:hexString];
		[_calcHexSequenceReverseTextField setStringValue:reverseHexString];
		[_calcBase64SequenceTextField setStringValue:base64String];
	}
	else if ([identifier isEqualToString:@"HexValue"])
	{
		unsigned long long value = 0;
		NSScanner *scanner = [NSScanner scannerWithString:[_calcHexValueTextField stringValue]];
		[scanner scanHexLongLong:&value];
		NSString *decimalString = [NSString stringWithFormat:@"%llu", value];
		NSString *octalString = [NSString stringWithFormat:@"%llo", value];
		NSString *binaryString = decimalToBinary(value);
		[_calcDecimalValueTextField setStringValue:decimalString];
		[_calcOctalValueTextField setStringValue:octalString];
		[_calcBinaryValueTextField setStringValue:binaryString];
	}
	else if ([identifier isEqualToString:@"DecimalValue"])
	{
		unsigned long long value = 0;
		NSScanner *scanner = [NSScanner scannerWithString:[_calcDecimalValueTextField stringValue]];
		[scanner scanUnsignedLongLong:&value];
		NSString *hexString = [NSString stringWithFormat:@"%llX", value];
		NSString *octalString = [NSString stringWithFormat:@"%llo", value];
		NSString *binaryString = decimalToBinary(value);
		[_calcHexValueTextField setStringValue:hexString];
		[_calcOctalValueTextField setStringValue:octalString];
		[_calcBinaryValueTextField setStringValue:binaryString];
	}
	else if ([identifier isEqualToString:@"OctalValue"])
	{
		unsigned long long value = 0;
		sscanf([[_calcOctalValueTextField stringValue] UTF8String], "%llo", &value);
		NSString *hexString = [NSString stringWithFormat:@"%llX", value];
		NSString *decimalString = [NSString stringWithFormat:@"%llu", value];
		NSString *binaryString = decimalToBinary(value);
		[_calcHexValueTextField setStringValue:hexString];
		[_calcDecimalValueTextField setStringValue:decimalString];
		[_calcBinaryValueTextField setStringValue:binaryString];
	}
	else if ([identifier isEqualToString:@"BinaryValue"])
	{
		unsigned long long value = binaryToDecimal([_calcBinaryValueTextField stringValue]);
		NSString *hexString = [NSString stringWithFormat:@"%llX", value];
		NSString *decimalString = [NSString stringWithFormat:@"%llu", value];
		NSString *octalString = [NSString stringWithFormat:@"%llo", value];
		[_calcHexValueTextField setStringValue:hexString];
		[_calcDecimalValueTextField setStringValue:decimalString];
		[_calcOctalValueTextField setStringValue:octalString];
	}
}

- (IBAction)logButtonClicked:(id)sender
{
	NSButton *button = (NSButton *)sender;
	NSString *identifier = [button identifier];
	
	if ([identifier isEqualToString:@"EraseLog"])
	{
		[_systemLogTextView setString:@""];
		
		[self launchCommandAsAdmin:_systemLogTextView launchPath:@"log" arguments: @[@"erase"]];
	}
	else if ([identifier isEqualToString:@"RefreshLog"])
	{
		[_systemLogTextView setString:@""];

		NSMutableArray *args = [NSMutableArray array];
		NSString *stdoutString = nil;
		
		[args addObjectsFromArray:@[@"show", @"--style", @"syslog", @"--source"]];
		
		if ([_lastBootLogButton state])
			[args addObjectsFromArray:@[@"--last", @"boot"]];
		
		[args addObject:@"--predicate"];
		
		NSMutableString *predicateString = [NSMutableString string];
		
		[predicateString appendFormat:@"process == \"%@\"", [_processLogComboBox stringValue]];
		
		if (![[_containsLogComboBox stringValue] isEqualToString:@""])
			[predicateString appendFormat:@"AND (eventMessage CONTAINS[c] \"%@\")", [_containsLogComboBox stringValue]];
		
		[args addObject:predicateString];
		
		if (launchCommand(@"/usr/bin/log", args, &stdoutString))
		{
			if (stdoutString != nil)
				[_systemLogTextView setString:stdoutString];
		}
	}
}

- (IBAction)displayButtonClicked:(id)sender
{
	NSButton *button = (NSButton *)sender;
	NSString *identifier = [button identifier];
	
	if ([identifier isEqualToString:@"Info"])
	{
		/* [_infoTextView setString:@""];
		[_infoTextField setStringValue:@""];
		
		NSBundle *mainBundle = [NSBundle mainBundle];
		NSString *filePath = nil;
		
		if ((filePath = [mainBundle pathForResource:@"EDID" ofType:@"rtf"]))
			[_infoTextView readRTFDFromFile:filePath];
		
		NSRect frame = [_infoWindow frame];
		frame.size = NSMakeSize(_window.frame.size.width, frame.size.height);
		[_infoWindow setFrame:frame display:NO animate:NO];
		
		[_window beginSheet:_infoWindow completionHandler:^(NSModalResponse returnCode)
		 {
			 switch (returnCode)
			 {
				 case NSModalResponseCancel:
					 break;
				 case NSModalResponseOK:
					 break;
				 default:
					 break;
			 }
		 }]; */
		
		NSString *helpBookName = [[NSBundle mainBundle] objectForInfoDictionaryKey: @"CFBundleHelpBookName"];
		[[NSHelpManager sharedHelpManager] openHelpAnchor:@"Display" inBook:helpBookName];
		
		return;
	}
	else if ([identifier isEqualToString:@"Add"])
	{
		Display *display;
		
		if (![self getCurrentlySelectedDisplay:&display])
			return;
		
		NSArray *resolution1080pArray = @[
										  [[[Resolution alloc] initWithWidth:1920 height:1080 type:kHiDPI1] autorelease],
										  [[[Resolution alloc] initWithWidth:1680 height:945 type:kHiDPI1] autorelease],
										  [[[Resolution alloc] initWithWidth:1440 height:810 type:kHiDPI1] autorelease],
										  [[[Resolution alloc] initWithWidth:1280 height:720 type:kHiDPI1] autorelease],
										  [[[Resolution alloc] initWithWidth:1024 height:576 type:kHiDPI1] autorelease],
								];
		
		NSArray *resolution2KArray = @[
									   [[[Resolution alloc] initWithWidth:2048 height:1152 type:kHiDPI1] autorelease],
									   [[[Resolution alloc] initWithWidth:1920 height:1080 type:kHiDPI1] autorelease],
									   [[[Resolution alloc] initWithWidth:1680 height:945 type:kHiDPI1] autorelease],
									   [[[Resolution alloc] initWithWidth:1440 height:810 type:kHiDPI1] autorelease],
									   [[[Resolution alloc] initWithWidth:1280 height:720 type:kHiDPI1] autorelease],
									   [[[Resolution alloc] initWithWidth:1024 height:576 type:kHiDPI2] autorelease],
									   [[[Resolution alloc] initWithWidth:960 height:540 type:kHiDPI3] autorelease],
									   [[[Resolution alloc] initWithWidth:2048 height:1152 type:kHiDPI4] autorelease],
										  ];
		
		NSArray *resolutionGeneralArray = @[
											[[[Resolution alloc] initWithWidth:1280 height:720 type:kHiDPI2] autorelease],
											[[[Resolution alloc] initWithWidth:960 height:540 type:kHiDPI2] autorelease],
											[[[Resolution alloc] initWithWidth:640 height:360 type:kHiDPI2] autorelease],
											[[[Resolution alloc] initWithWidth:840 height:472 type:kHiDPI3] autorelease],
											[[[Resolution alloc] initWithWidth:720 height:405 type:kHiDPI3] autorelease],
											[[[Resolution alloc] initWithWidth:640 height:360 type:kHiDPI3] autorelease],
											[[[Resolution alloc] initWithWidth:576 height:324 type:kHiDPI3] autorelease],
											[[[Resolution alloc] initWithWidth:512 height:288 type:kHiDPI3] autorelease],
											[[[Resolution alloc] initWithWidth:420 height:234 type:kHiDPI3] autorelease],
											[[[Resolution alloc] initWithWidth:400 height:225 type:kHiDPI3] autorelease],
											[[[Resolution alloc] initWithWidth:320 height:180 type:kHiDPI3] autorelease],
											[[[Resolution alloc] initWithWidth:1920 height:1080 type:kHiDPI4] autorelease],
											[[[Resolution alloc] initWithWidth:1680 height:945 type:kHiDPI4] autorelease],
											[[[Resolution alloc] initWithWidth:1440 height:810 type:kHiDPI4] autorelease],
											[[[Resolution alloc] initWithWidth:1280 height:720 type:kHiDPI4] autorelease],
											[[[Resolution alloc] initWithWidth:1024 height:576 type:kHiDPI4] autorelease],
											[[[Resolution alloc] initWithWidth:960 height:540 type:kHiDPI4] autorelease],
											[[[Resolution alloc] initWithWidth:640 height:360 type:kHiDPI4] autorelease],
										  ];

		if ([display.resolutionsArray count] == 0)
		{
			switch(display.resolutionIndex)
			{
				case 0: // 1080p
					[display.resolutionsArray addObjectsFromArray:resolution1080pArray];
					break;
				case 1: // 2K
					[display.resolutionsArray addObjectsFromArray:resolution2KArray];
					break;
				case 2: // Manual
					break;
			}
			
			[display.resolutionsArray addObjectsFromArray:resolutionGeneralArray];
		}
		else
		{
			Resolution *resolution = [[Resolution alloc] initWithWidth:1920 height:1080 type:kAuto];
			[resolution autorelease];
			[display.resolutionsArray addObject:resolution];
		}
		
		[_resolutionsTableView reloadData];
	}
	else if ([identifier isEqualToString:@"Delete"])
	{
		Display *display;
		
		if (![self getCurrentlySelectedDisplay:&display])
			return;
		
		NSIndexSet *indexSex = [_resolutionsTableView selectedRowIndexes];
		NSUInteger index = [indexSex lastIndex];
		
		while (index != NSNotFound)
		{
			[display.resolutionsArray removeObjectAtIndex:index];
			
			index = [indexSex indexLessThanIndex:index];
		}
		
		[_resolutionsTableView reloadData];
	}
	else if ([identifier isEqualToString:@"Refresh"])
	{
		[self refreshDisplays];
	}
	else if ([identifier isEqualToString:@"Export"])
	{
		for (Display *display in _displaysArray)
		{
			[FixEDID makeEDIDFiles:display];
			[FixEDID createDisplayIcons:_displaysArray];
		}
	}
}

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
	//NSLog (@"didSelectTabViewItem");
	//[self resetCursorRects];
}

- (BOOL)tabView:(NSTabView *)tabView shouldSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
	//NSLog (@"shouldSelectTabViewItem");
	return YES;
}

- (void)tabView:(NSTabView *)tabView willSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
	//NSLog (@"willSelectTabViewItem");
}

- (void)tabViewDidChangeNumberOfTabViewItems:(NSTabView *)tabView
{
	//NSLog (@"tabViewDidChangeNumberOfTabViewItems");
}

// -----------------------------------------------------------------------------------------

- (NSComparisonResult)compareVersion:(NSString *)currentVersion otherVersion:(NSString *)otherVersion
{
    NSArray *currentVersionArray = [currentVersion componentsSeparatedByString:@"."];
	NSArray *otherVersionArray = [otherVersion componentsSeparatedByString:@"."];
    NSInteger pos = 0;

    while ([currentVersionArray count] > pos || [otherVersionArray count] > pos)
	{
        NSInteger v1 = [currentVersionArray count] > pos ? [[currentVersionArray objectAtIndex:pos] integerValue] : 0;
        NSInteger v2 = [otherVersionArray count] > pos ? [[otherVersionArray objectAtIndex:pos] integerValue] : 0;
        
		if (v2 > v1)
            return NSOrderedAscending;
        else if (v2 < v1)
            return NSOrderedDescending;
        
		pos++;
    }

    return NSOrderedSame;
}

- (bool)initBootloaderDownloader:(NSString *)mode
{
	_bootloaderInfo = ([self isBootloaderOpenCore] ? &_openCoreInfo : &_cloverInfo);
	
	if ([mode isEqualToString:@"update"])
	{
		[self showDockIcon];
		[self setBootloaderInfo];
		_forcedUpdate = YES;
		[self doBootloaderUpdate];
	}
	else
	{
		BOOL forced = [mode isEqualToString:@"forced"];
		
		if (forced)
			[self showDockIcon];
		
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		NSDate *now = [NSDate dateWithTimeIntervalSinceNow:0];
		NSTimeInterval lastCheckTimestamp = [[defaults objectForKey:_bootloaderInfo->LastCheckTimestamp] timeIntervalSince1970];
		NSInteger scheduledCheckInterval = [defaults integerForKey:_bootloaderInfo->ScheduledCheckInterval] * 0.9;
		NSTimeInterval intervalFromRef = [now timeIntervalSince1970];
		
		if ((scheduledCheckInterval && lastCheckTimestamp + scheduledCheckInterval < intervalFromRef - scheduledCheckInterval * 0.05) || forced)
		{
			NSLog(@"Starting updates check...");
			
			[defaults setObject:now forKey:_bootloaderInfo->LastCheckTimestamp];
			[defaults synchronize];
			
			if ([self getGithubLatestDownloadInfo:_bootloaderInfo->LatestReleaseURL fileNameMatch:_bootloaderInfo->FileNameMatch browserDownloadUrl:&_bootloaderInfo->LatestDownloadURL downloadVersion:&_bootloaderInfo->LatestVersion])
			{
				NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:_bootloaderInfo->LatestDownloadURL] cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:30.0];
				
				_connection = [[NSURLConnection alloc] initWithRequest:request delegate:self];
				
				if (!_connection)
				{
					NSLog(@"Connection request failed!");
					return false;
				}
			}
		}
		else
		{
			NSLog(@"To early to run check. Terminating...");
			return false;
		}
	}
	
	return true;
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
	NSLog(@"Connection failed with error: %@", error.description);
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
	// Stop downloading installer
	[connection cancel];
	
	_bootloaderInfo->SuggestedFileName = [response.suggestedFilename retain];
	
	[self setBootloaderInfo];
	
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSDate *downloadedDate = [defaults objectForKey:_bootloaderInfo->LastDownloadWarned];
	
	if (([self compareVersion:_bootloaderInfo->BootedVersion otherVersion:_bootloaderInfo->LatestVersion] == NSOrderedAscending) || (downloadedDate && [downloadedDate timeIntervalSinceDate:[NSDate date]] > 60 * 60 * 24))
	{
		[_hasUpdateImageView setImage:[NSImage imageNamed:_bootloaderInfo->IconName]];
		[_hasUpdateTextField setStringValue:[NSString stringWithFormat:GetLocalizedString(@"%@ Version %@ is Available - you have %@. Would you like to download a newer Version?"), _bootloaderInfo->Name, _bootloaderInfo->LatestVersion, _bootloaderInfo->BootedVersion]];
		
		[[NSOperationQueue mainQueue] addOperationWithBlock:^
		 {
			 [_window beginSheet:_hasUpdateWindow completionHandler:^(NSModalResponse returnCode)
			  {
			  }];
		 }];
	}
	else if (_forcedUpdate)
	{
		[_noUpdatesImageView setImage:[NSImage imageNamed:_bootloaderInfo->IconName]];
		[_noUpdatesImageView setStringValue:[NSString stringWithFormat:GetLocalizedString(@"No new %@ Version is Avaliable at this Time!"), _bootloaderInfo->Name]];
		
		[[NSOperationQueue mainQueue] addOperationWithBlock:^
		 {
			 [_window beginSheet:_noUpdatesWindow completionHandler:^(NSModalResponse returnCode)
			  {
			  }];
		 }];
	}
}

- (void)download:(NSURLDownload *)download decideDestinationWithSuggestedFilename:(NSString *)filename
{
	if (_bootloaderInfo->DownloadPath == nil)
		return;
	
	//NSLog(@"Downloading to: %@", _bootloaderDownloadPath);
	
	[download setDestination:_bootloaderInfo->DownloadPath allowOverwrite:YES];
}

- (void)download:(NSURLDownload *)download didReceiveResponse:(NSURLResponse *)response;
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
	
	if ([response expectedContentLength])
	{
		[_progressLevelIndicator setHidden:NO];
		[_progressIndicator setHidden:YES];
		[_progressLevelIndicator setMinValue:0];
		[_progressLevelIndicator setMaxValue:[response expectedContentLength]];
		[_progressLevelIndicator setDoubleValue:0];
	}
	else
	{
		[_progressLevelIndicator setHidden:YES];
		[_progressIndicator setHidden:NO];
	}
}

- (void)download:(NSURLDownload *)download didReceiveDataOfLength:(NSUInteger)length
{
	if (![_progressLevelIndicator isHidden])
	{
		[_progressLevelIndicator setDoubleValue:_progressLevelIndicator.doubleValue + length];
		[_progressTitleTextField setStringValue:[NSString stringWithFormat:GetLocalizedString(@"%1.1f Mbytes"), _progressLevelIndicator.doubleValue / (1024 * 1024)]];
	}
}

- (void)download:(NSURLDownload *)aDownload didFailWithError:(NSError *)error
{
	NSAlert *alert = [[[NSAlert alloc] init] autorelease];
	
	[alert setIcon:[NSImage imageNamed:NSImageNameCaution]];
	[alert setMessageText:[NSString stringWithFormat:GetLocalizedString(@"An error occured while trying to download %@ installer!"), _bootloaderInfo->Name]];
	[alert setInformativeText:error.localizedDescription];
	[alert addButtonWithTitle:GetLocalizedString(@"OK")];
	
	[alert beginSheetModalForWindow:_progressWindow completionHandler:^(NSModalResponse returnCode)
	 {
		 [NSApp stopModalWithCode:returnCode];
		 [_window endSheet:_progressWindow];
	 }];
	
	[NSApp runModalForWindow:_window];
}

- (void)downloadDidFinish:(NSURLDownload *)download
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[[NSWorkspace sharedWorkspace] openFile:_bootloaderInfo->DownloadPath];
	
	[defaults setInteger:_bootloaderInfo->LatestVersion.intValue forKey:_bootloaderInfo->LastVersionDownloaded];
	[defaults setObject:[NSDate date] forKey:_bootloaderInfo->LastDownloadWarned];
	
	[_window endSheet:_progressWindow];
}

- (void)showWindow:(NSWindow *)window
{
	[NSApp activateIgnoringOtherApps:YES];
	[window setLevel:NSModalPanelWindowLevel];
	[window makeKeyAndOrderFront:self];
}

- (void)showDockIcon
{
	ProcessSerialNumber	psn = {0, kCurrentProcess};
	TransformProcessType(&psn, kProcessTransformToForegroundApplication);
}

- (void)setBootloaderInfo
{
	[_bootloaderInfoArray removeAllObjects];
	
	if ([Clover tryGetVersionInfo:&_cloverInfo.BootedVersion installedVersion:&_cloverInfo.InstalledVersion])
		_settings.DetectedBootloader = kBootloaderClover;
	
	if ([OpenCore tryGetVersionInfo:&_openCoreInfo.BootedVersion])
		_settings.DetectedBootloader = kBootloaderOpenCore;
	
	if ([self isBootloaderOpenCore])
	{
		[_bootloaderImageView setImage:[NSImage imageNamed:@"IconOpenCore"]];
		
		[self addToList:_bootloaderInfoArray name:@"Name" value:GetLocalizedString(@"OpenCore")];
		[self addToList:_bootloaderInfoArray name:@"Current Booted Version" value:_openCoreInfo.BootedVersion];
		[self addToList:_bootloaderInfoArray name:@"Latest Available Version" value:_openCoreInfo.LatestVersion];
	}
	else
	{
		[_bootloaderImageView setImage:[NSImage imageNamed:@"IconClover"]];
		[_bootloaderInfoArray removeAllObjects];
		
		[self addToList:_bootloaderInfoArray name:@"Name" value:GetLocalizedString(@"Clover")];
		[self addToList:_bootloaderInfoArray name:@"Current Booted Version" value:_cloverInfo.BootedVersion];
		[self addToList:_bootloaderInfoArray name:@"Last Installed Version" value:_cloverInfo.InstalledVersion];
		[self addToList:_bootloaderInfoArray name:@"Latest Available Version" value:_cloverInfo.LatestVersion];
	}
	
	[_bootloaderInfoTableView reloadData];
}

- (void)showProgressWindow
{
	[_progressCancelButton setAction:@selector(bootloaderButtonClicked:)];
	[_progressLevelIndicator setDoubleValue:0.0];
	[_progressImageView setImage:[NSImage imageNamed:_bootloaderInfo->IconName]];
	[_progressTitleTextField setStringValue:@""];
	[_progressMessageTextField setStringValue:[NSString stringWithFormat:GetLocalizedString(@"Downloading %@"), [_bootloaderInfo->DownloadPath lastPathComponent]]];
	
	[_window beginSheet:_progressWindow completionHandler:^(NSModalResponse returnCode)
	 {
	 }];
}

- (void)doBootloaderUpdate
{
	[self showDockIcon];
	
	if (_forcedUpdate)
	{
		NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:_bootloaderInfo->LatestDownloadURL] cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:20.0];
		
		_download = [[NSURLDownload alloc] initWithRequest:request delegate:self];
		
		if (_download)
		{
			[self showProgressWindow];
		}
	}
	else
	{
		NSSavePanel *savePanel = [NSSavePanel savePanel];
		
		//[savePanel setNameFieldStringValue:[bootloaderInfo->DownloadPath lastPathComponent]];
		[savePanel setNameFieldStringValue:_bootloaderInfo->SuggestedFileName];
		[savePanel setTitle:[NSString stringWithFormat:GetLocalizedString(@"Set %@ Installer Location"), _bootloaderInfo->Name]];
		
		[_hasUpdateImageView setImage:[NSImage imageNamed:_bootloaderInfo->IconName]];
		
		[savePanel beginSheetModalForWindow:_window completionHandler:^(NSInteger result)
		 {
			 if (result == NSFileHandlingPanelOKButton)
			 {
				 _bootloaderInfo->DownloadPath = [savePanel.URL.path retain];
				 
				 NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:_bootloaderInfo->LatestDownloadURL] cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:20.0];
				 
				 _download = [[NSURLDownload alloc] initWithRequest:request delegate:self];
				 
				 if (_download)
					 [self showProgressWindow];
			 }
		 }];
	}
}

- (IBAction)cancelDownloadButtonClicked:(id)sender
{
}

- (IBAction)installedButtonClicked:(id)sender
{
	NSButton *button = (NSButton *)sender;
	NSString *identifier = [button identifier];
	
	if ([identifier isEqualToString:@"ShowInstalledOnly"])
	{
		_settings.ShowInstalledOnly = [_showInstalledOnlyButton state];
		[_kextsTableView reloadData];
	}
	else if ([identifier isEqualToString:@"Update"])
	{
		[self getKextCurrentVersions];
	}
	else if ([identifier isEqualToString:@"Download"])
	{
		[self downloadSelectedKexts];
	}
	else if ([identifier isEqualToString:@"Compile"])
	{
		[self compileSelectedKexts];
	}
}

- (IBAction)bootloaderButtonClicked:(id)sender
{
	NSButton *button = (NSButton *)sender;
	NSString *identifier = [button identifier];
	_bootloaderInfo = ([self isBootloaderOpenCore] ? &_openCoreInfo : &_cloverInfo);
	
	if ([identifier isEqualToString:@"BootloaderInfo"])
	{
		if (_bootloaderInfo->SuggestedFileName == nil)
		{
			[self initBootloaderDownloader:@"forced"];
			
			return;
		}
		
		NSString *desktopPath = [NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES) objectAtIndex:0];
		NSString *installerPath = [NSString stringWithFormat:@"%@/%@", desktopPath, _bootloaderInfo->SuggestedFileName];
		
		//NSLog(@"installerFilename: %@", installerPath);
		
		//if ([_cloverBootedRevision intValue] < [_cloverLatestRevision intValue])

		NSSavePanel *savePanel = [NSSavePanel savePanel];
		[savePanel setNameFieldStringValue:[installerPath lastPathComponent]];
		[savePanel setTitle:GetLocalizedString(@"Set Bootloader Installer Location")];

		[savePanel beginSheetModalForWindow:_window completionHandler:^(NSInteger result)
		{
			if (result == NSFileHandlingPanelOKButton)
			{
				_bootloaderInfo->DownloadPath = [savePanel.URL.path retain];
				
				[self initBootloaderDownloader:@"update"];
			}
		}];
	}
	else if ([identifier isEqualToString:@"ProgressCancel"])
	{
		[_window endSheet:_progressWindow];

		[_download cancel];
	}
	else if ([identifier isEqualToString:@"BootloaderRefresh"])
	{
		[self initBootloaderDownloader:@"forced"];
	}
	else if ([identifier isEqualToString:@"BootloaderClose"])
	{
		[_window endSheet:_noUpdatesWindow];
	}
	else if ([identifier isEqualToString:@"BootloaderUpdate"])
	{
		[_window endSheet:_hasUpdateWindow];
		
		[self doBootloaderUpdate];
	}
	else if ([identifier isEqualToString:@"BootloaderNotNow"])
	{
		[_window endSheet:_hasUpdateWindow];
	}
	else if ([identifier isEqualToString:@"ApplyBootloaderPatches"])
	{
		int bootloaderPatchCount = 0;
		
		for (NSMutableDictionary *patchDictionary in _bootloaderPatchArray)
		{
			NSNumber *disabled = [patchDictionary objectForKey:@"Disabled"];
			
			if ([disabled boolValue])
				continue;
			
			bootloaderPatchCount++;
		}
		
		if (bootloaderPatchCount == 0)
			return;
		
		if (![self showAlert:[NSString stringWithFormat:GetLocalizedString(@"%@ Patch"), _bootloaderInfo->Name] text:[NSString stringWithFormat:GetLocalizedString(@"Are you sure you want to apply %d %@ patch(s)?"), bootloaderPatchCount, _bootloaderInfo->Name]])
			return;
		
		NSMutableDictionary *configDictionary = nil;
		NSString *configPath = nil;
		
		if (![Config openConfig:self configDictionary:&configDictionary configPath:&configPath])
			return;
		
		for (NSMutableDictionary *patchDictionary in _bootloaderPatchArray)
		{
			NSNumber *disabled = [patchDictionary objectForKey:@"Disabled"];
			NSString *type = [patchDictionary objectForKey:@"Type"];
			
			if ([disabled boolValue])
				continue;
			
			NSMutableDictionary *newPatchDictionary = [patchDictionary mutableCopy];
			
			[newPatchDictionary removeObjectForKey:@"Type"];
			
			if ([self isBootloaderOpenCore])
			{
				NSString *name = [newPatchDictionary objectForKey:@"Name"];
				NSString *matchOS = [newPatchDictionary objectForKey:@"MatchOS"];
		
				[newPatchDictionary removeObjectForKey:@"Name"];
				[newPatchDictionary removeObjectForKey:@"MatchOS"];
				[newPatchDictionary removeObjectForKey:@"Disabled"];
				
				if ([type isEqualToString:@"DSDT Rename"])
				{
					[newPatchDictionary setValue:[@"DSDT" dataUsingEncoding:NSUTF8StringEncoding] forKey:@"TableSignature"];
					
					[OpenCore addACPIDSDTPatchWith:configDictionary patchDictionary:newPatchDictionary];
				}
				else if ([type isEqualToString:@"KernelToPatch"] || [type isEqualToString:@"KextsToPatch"])
				{
					NSArray *versionArray = [matchOS componentsSeparatedByString:@"."];
					
					if ([versionArray count] > 1)
						[newPatchDictionary setObject:[NSString stringWithFormat:@"%d.", [versionArray[1] intValue] + 4] forKey:@"MatchKernel"];
					
					[newPatchDictionary setObject:@(YES) forKey:@"Enabled"];
					[newPatchDictionary setObject:name forKey:@"Identifier"];
					[newPatchDictionary setObject:@"" forKey:@"Base"];
					[newPatchDictionary setObject:@(0) forKey:@"Count"];
					[newPatchDictionary setObject:@(0) forKey:@"Limit"];
					[newPatchDictionary setObject:@(0) forKey:@"Skip"];
					[newPatchDictionary setObject:[NSData data] forKey:@"Mask"];
					[newPatchDictionary setObject:[NSData data] forKey:@"ReplaceMask"];
					
					[OpenCore addKernelPatchWith:configDictionary typeName:@"Patch" patchDictionary:newPatchDictionary];
				}
			}
			else
			{
				if ([type isEqualToString:@"DSDT Rename"])
					[Clover addACPIDSDTPatchWith:configDictionary patchDictionary:newPatchDictionary];
				else if ([type isEqualToString:@"KernelToPatch"] || [type isEqualToString:@"KextsToPatch"])
					[Clover addKernelAndKextPatchWith:configDictionary kernelAndKextName:type patchDictionary:newPatchDictionary];
			}
			
			[newPatchDictionary release];
			
			[patchDictionary setObject:@(YES) forKey:@"Disabled"];
		}
		
		[configDictionary writeToFile:configPath atomically:YES];
		
		[_bootloaderPatchTableView reloadData];
	}
}

- (IBAction)lockButtonClicked:(id)sender
{
	if (requestAdministratorRights() != 0)
		return;
}

- (void) updateAuthorization
{
	[_authorizationButton setImage:[NSImage imageNamed:@"IconUnlocked.png"]];
}

- (IBAction)toolbarClicked:(id)sender
{
	NSToolbarItem *toolbarItem = (NSToolbarItem *)sender;
	
	[_tabView selectTabViewItemAtIndex:[toolbarItem.itemIdentifier intValue]];
	
	NSTabViewItem *tabViewItem = [_tabView selectedTabViewItem];
	NSString *identifier = [tabViewItem identifier];
	
	if (toolbarItem.tag == 0)
	{
		[toolbarItem setTag:1];
		
		if ([identifier isEqualToString:@"Bootloader"])
		{
			[self initBootloaderDownloader:@"forced"];
		}
		else if ([identifier isEqualToString:@"Power"])
		{
			[self getPowerSettings];
		}
	}
}

- (IBAction)pciViewButtonClicked:(id)sender
{
	NSButton *button = (NSButton *)sender;
	NSInteger row = -1;
	NSString *bundleID = nil;
	NSMutableDictionary *pciDeviceDictionary = nil;
	
	if ((row = [_pciDevicesTableView rowForView:button]) != -1)
	{
		pciDeviceDictionary = _pciDevicesArray[row];
		bundleID = [pciDeviceDictionary objectForKey:@"BundleID"];
	}
	else if ((row = [_networkInterfacesTableView rowForView:button]) != -1)
	{
		pciDeviceDictionary = _networkInterfacesArray[row];
		bundleID = [pciDeviceDictionary objectForKey:@"BundleID"];
	}
	else if ((row = [_bluetoothDevicesTableView rowForView:button]) != -1)
	{
		pciDeviceDictionary = _bluetoothDevicesArray[row];
		bundleID = [pciDeviceDictionary objectForKey:@"BundleID"];
	}
	else if ((row = [_graphicDevicesTableView rowForView:button]) != -1)
	{
		pciDeviceDictionary = _graphicDevicesArray[row];
		bundleID = [pciDeviceDictionary objectForKey:@"BundleID"];
	}
	else if ((row = [_audioDevicesTableView1 rowForView:button]) != -1)
	{
		AudioDevice *audioDevice = _audioDevicesArray[row];
		bundleID = audioDevice.bundleID;
	}
	else if ((row = [_audioDevicesTableView2 rowForView:button]) != -1)
	{
		AudioDevice *audioDevice = _audioDevicesArray[row];
		bundleID = audioDevice.bundleID;
	}
	else if ((row = [_storageDevicesTableView rowForView:button]) != -1)
	{
		pciDeviceDictionary = _storageDevicesArray[row];
		bundleID = [pciDeviceDictionary objectForKey:@"BundleID"];
	}
	
	NSURL *bundleURL = (__bridge NSURL *)KextManagerCreateURLForBundleIdentifier(kCFAllocatorDefault, (__bridge CFStringRef)bundleID);
	
	if (bundleURL == nil)
		return;
	
	NSArray *fileURLs = [NSArray arrayWithObjects:bundleURL, nil];
	[[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:fileURLs];
	[bundleURL release];
}

- (IBAction)appleIntelInfoButtonClicked:(id)sender
{
	NSButton *button = (NSButton *)sender;
	NSString *identifier = [button identifier];
	
	_settings.AII_EnableHWP = _aiiEnableHWP.state;
	_settings.AII_LogCStates = _aiiLogCStates.state;
	_settings.AII_LogIGPU = _aiiLogIGPU.state;
	_settings.AII_LogIPGStyle = _aiiLogIPGStyle.state;
	_settings.AII_LogIntelRegs = _aiiLogIntelRegs.state;
	_settings.AII_LogMSRs = _aiiLogMSRs.state;
	
	if ([identifier isEqualToString:@"AII_EnableHWP"])
	{
		if (_settings.AII_EnableHWP)
		{
			if (![self showAlert:@"Warning!" text:@"Enabling HWP (Intel Speed Shift) will require a reboot to restore the previous value."])
			{
				[_aiiEnableHWP setState:NO];
				_settings.AII_EnableHWP = false;
			}
		}
	}
	else if ([identifier isEqualToString:@"AII_LogIntelRegs"])
	{
		if (_settings.AII_LogIntelRegs)
		{
			if (![self showAlert:@"Warning!" text:@"Logging Intel registers may cause your system to crash."])
			{
				[_aiiLogIntelRegs setState:NO];
				_settings.AII_LogIntelRegs = false;
			}
		}
	}
}

- (IBAction)outputMenuClicked:(id)sender
{
	NSSavePanel *savePanel = [NSSavePanel savePanel];
	[savePanel setNameFieldStringValue:@"Output.txt"];
	[savePanel setTitle:GetLocalizedString(@"Save Output")];
	
	[savePanel beginSheetModalForWindow:_window completionHandler:^(NSInteger result)
	 {
		 NSError *error;
		 
		 if (result == NSFileHandlingPanelOKButton)
			 [_compileOutputTextView.string writeToFile:savePanel.URL.path atomically:YES encoding:NSUTF8StringEncoding error:&error];
	 }];
}

- (IBAction)systemConfigsClicked:(id)sender
{
	NSMenuItem *menuItem = (NSMenuItem *)sender;
	uint32_t index = (uint32_t)menuItem.tag;
	NSMutableDictionary *propertyDictionary = _systemConfigsArray[index];

	[self loadConfig:propertyDictionary];
}

- (NSInteger)numberOfItemsInMenu:(NSMenu *)menu
{
	if ([menu.identifier isEqualToString:@"Mount"])
		return 5;
	else if ([menu.identifier isEqualToString:@"Tools"])
		return 2;
	else if ([menu.identifier isEqualToString:@"CopyToClipboard"])
		return 3;
	else if ([menu.identifier isEqualToString:@"Install"])
		return 1;
	else if ([menu.identifier isEqualToString:@"PCI"])
		return 2;
	else if ([menu.identifier isEqualToString:@"Info"])
		return 1;
	
	return 0;
}

- (BOOL)menu:(NSMenu *)menu updateItem:(NSMenuItem *)item atIndex:(NSInteger)index shouldCancel:(BOOL)shouldCancel
{
	if ([menu.identifier isEqualToString:@"Mount"] || [menu.identifier isEqualToString:@"Tools"])
	{
		NSInteger row = _partitionSchemeTableView.clickedRow;
		
		if (row == -1)
		{
			[menu cancelTrackingWithoutAnimation];
			
			return NO;
		}
		
		Disk *disk = _disksArray[row];
		
		if ([menu.identifier isEqualToString:@"Mount"])
		{
			if ([item.identifier isEqualToString:@"Mount"])
				item.title = (disk.isMounted ? GetLocalizedString(@"Unmount") : GetLocalizedString(@"Mount"));
			else if ([item.identifier isEqualToString:@"Eject"])
				item.enabled = (disk.isEjectable && !disk.isInternal);
			else if ([item.identifier isEqualToString:@"Open"])
				item.enabled = disk.isMounted;
			else if ([item.identifier isEqualToString:@"BootEFI"])
			{
				item.enabled = disk.isEFI;
				item.state = disk.isBootableEFI;
			}
		}
		else if ([menu.identifier isEqualToString:@"Tools"])
		{
			if ([item.identifier isEqualToString:@"DeleteAPFSContainer"])
				item.enabled = disk.isAPFSContainer;
			else if ([item.identifier isEqualToString:@"ConvertToAPFS"])
				item.enabled = disk.isHFS;
		}
		
		return YES;
	}
	else if ([menu.identifier isEqualToString:@"Install"])
	{
	}
	
	return YES;
}

- (void)open:(Disk *)disk
{
	if (disk.volumePath == nil)
		return;
	
	NSArray *fileURLs = [NSArray arrayWithObjects:disk.volumePath, nil];
	[[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:fileURLs];
}

- (BOOL)installKexts
{
	NSOpenPanel *openPanel = [NSOpenPanel openPanel];
	[openPanel setCanChooseFiles:YES];
	[openPanel setAllowsMultipleSelection:YES];
	[openPanel setCanChooseDirectories:NO];
	[openPanel setAllowedFileTypes:@[@"kext"]];
	[openPanel setPrompt:GetLocalizedString(@"Select")];
	
	[openPanel beginSheetModalForWindow:_window completionHandler:^(NSModalResponse returnCode)
	 {
		 [NSApp stopModalWithCode:returnCode];
	 }];
	
	if ([NSApp runModalForWindow:_window] != NSOKButton)
		return NO;
	
	if (requestAdministratorRights() != 0)
		return NO;
	
	[_toolsOutputTextView setString:@""];
	
	NSString *extensionsPath = [self getExtensionsPath];
	bool rebuildKextCacheAndRepairPermissions = NO;
	
	if ([[openPanel URLs] count] == 0)
		return NO;
	
	if (![self showSavePanelWithDirectory:extensionsPath nameField:[[openPanel URLs][0] lastPathComponent] fileTypes:@[@"kext"] path:&extensionsPath])
		return NO;
	
	for (NSURL *url in [openPanel URLs])
	{
		if ([self installKext:_toolsOutputTextView kextPath:url.path extensionsPath:extensionsPath])
			rebuildKextCacheAndRepairPermissions = YES;
	}

	if (rebuildKextCacheAndRepairPermissions)
		[self rebuildKextCacheAndRepairPermissions:_toolsOutputTextView];
	
	return YES;
}

- (NSString *)getExtensionsPath
{
	NSOperatingSystemVersion minimumSupportedOSVersion = { .majorVersion = 10, .minorVersion = 11, .patchVersion = 0 };
	BOOL isSupported = [NSProcessInfo.processInfo isOperatingSystemAtLeastVersion:minimumSupportedOSVersion];
	
	return (isSupported ? @"/Library/Extensions" : @"/System/Library/Extensions");
}

- (BOOL)isRootDiskFileSystemWritable
{
	for (Disk *disk in _disksArray)
	{
		if (disk.volumePath == nil)
			continue;
		
		if (![[disk.volumePath path] isEqualToString:@"/"])
			continue;
		
		return disk.isFileSystemWritable;
	}
	
	return NO;
}

- (BOOL)disableGatekeeperAndMountDiskReadWrite:(NSTextView *)textView forced:(BOOL)forced
{
	if (requestAdministratorRights() != 0)
		return NO;
	
	if (!forced)
	{
		// Already applied patch in this session
		if (_gatekeeperDisabled)
			return YES;
		
		// If the root disk is writeable return
		if ([self isRootDiskFileSystemWritable])
			return YES;
	
		// Only 10.15.0 requires this
		NSOperatingSystemVersion minimumSupportedOSVersion = { .majorVersion = 10, .minorVersion = 15, .patchVersion = 0 };
		BOOL isOSAtLeastCatalina = [NSProcessInfo.processInfo isOperatingSystemAtLeastVersion:minimumSupportedOSVersion];
	
		if (!isOSAtLeastCatalina)
			return YES;
	}
	
	if (![self showAlert:@"Disable Gatekeeper and mount the disk in read/write mode?" text:@"This is required for some operations on macOS 10.15+"])
		return NO;
	
	[self launchCommandAsAdmin:textView launchPath:@"spctl" arguments: @[@"--master-disable"]];
	[self launchCommandAsAdmin:textView launchPath:@"mount" arguments: @[@"-uw", @"/"]];
	[self launchCommandAsAdmin:textView launchPath:@"killall" arguments: @[@"Finder"]];
	
	_gatekeeperDisabled = YES;
	
	return YES;
}

- (BOOL)showSavePanelWithDirectory:(NSString *)directory nameField:(NSString *)nameField fileTypes:(NSArray *)fileTypes path:(NSString **)path
{
	NSOpenPanel *openPanel = [NSOpenPanel openPanel];
	[openPanel setDirectoryURL:[NSURL URLWithString:directory]];
	[openPanel setNameFieldStringValue:nameField];
	[openPanel setAllowedFileTypes:fileTypes];
	[openPanel setPrompt:GetLocalizedString(@"Select Destination")];
	[openPanel setCanChooseDirectories:YES];
	[openPanel setCanCreateDirectories:YES];
	[openPanel setCanChooseFiles:NO];
	
	[openPanel beginSheetModalForWindow:_window completionHandler:^(NSModalResponse returnCode)
	 {
		 [NSApp stopModalWithCode:returnCode];
	 }];
	
	if ([NSApp runModalForWindow:_window] != NSOKButton)
		return NO;
	
	*path = [openPanel URL].path;
	
	return YES;
}

- (BOOL)installKext:(NSTextView *)textView kextPath:(NSString *)kextPath useSavePanel:(BOOL)useSavePanel
{
	NSString *extensionsPath = [self getExtensionsPath];

	if (useSavePanel)
		[self showSavePanelWithDirectory:extensionsPath nameField:[kextPath lastPathComponent] fileTypes:@[@"kext"] path:&extensionsPath];
	
	[self installKext:textView kextPath:kextPath extensionsPath:extensionsPath];
	
	return YES;
}

- (BOOL)installKext:(NSTextView *)textView kextPath:(NSString *)kextPath extensionsPath:(NSString *)extensionsPath
{
	if (requestAdministratorRights() != 0)
		return NO;
	
	[self disableGatekeeperAndMountDiskReadWrite:textView forced:NO];
	
	NSString *fileName = [kextPath lastPathComponent];
	
	[self appendTextView:textView foregroundColor:[NSColor textColor] backgroundColor:_orangeColor text:[NSString stringWithFormat:GetLocalizedString(@"Installing '%@'...\n"), fileName]];
	
	[self launchCommandAsAdmin:textView launchPath:@"rm" arguments:@[@"-Rf", [extensionsPath stringByAppendingPathComponent:fileName]]];
	[self launchCommandAsAdmin:textView launchPath:@"cp" arguments: @[@"-R", kextPath, extensionsPath]];
	
	return YES;
}

- (BOOL)installAtherosKext
{
	// https://www.insanelymac.com/forum/files/file/956-atheros-installer-for-macos-mojave-and-catalina/
	// For macOS Catalina:
	// 1. Copy /System/Library/Extensions/IO80211Family.kext to Desktop
	// 2. Copy IO80211Family.kext to /System/Library/Extensions
	
	NSString *stdoutString = nil;
	NSBundle *mainBundle = [NSBundle mainBundle];
	NSArray *pathArray = NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES);
	NSString *desktopPath = [pathArray objectAtIndex:0];
	NSString *kextPath = nil;
	
	NSOperatingSystemVersion minimumSupportedOSVersion = { .majorVersion = 10, .minorVersion = 15, .patchVersion = 0 };
	BOOL isOSAtLeastCatalina = [NSProcessInfo.processInfo isOperatingSystemAtLeastVersion:minimumSupportedOSVersion];
	
	if (isOSAtLeastCatalina)
	{
		if (requestAdministratorRights() != 0)
			return NO;
		
		if (!(kextPath = [mainBundle pathForResource:@"IO80211Family" ofType:@"kext" inDirectory:@"Kexts"]))
			return NO;
		
		NSString *srcKextPath = @"/System/Library/Extensions/IO80211Family.kext";
		NSString *dstKextPath = [desktopPath stringByAppendingPathComponent:@"IO80211Family.kext"];
		
		launchCommandAsAdmin(@"/bin/cp", @[@"-r", srcKextPath, dstKextPath], &stdoutString);
		
		if ([self installKext:_toolsOutputTextView kextPath:kextPath extensionsPath:@"/System/Library/Extensions"])
			[self rebuildKextCacheAndRepairPermissions:_toolsOutputTextView];
	}
	else
	{
		if (!(kextPath = [mainBundle pathForResource:@"AirPortAtheros40" ofType:@"kext" inDirectory:@"Kexts"]))
			return NO;
		
		if ([self installKext:_toolsOutputTextView kextPath:kextPath useSavePanel:NO])
			[self rebuildKextCacheAndRepairPermissions:_toolsOutputTextView];
	}
	
	return YES;
}

- (void)installSATAHotplugFixKext
{
	NSBundle *mainBundle = [NSBundle mainBundle];
	NSString *kextPath = nil;
	
	if (!(kextPath = [mainBundle pathForResource:@"AppleAHCIPortHotplug" ofType:@"kext" inDirectory:@"Kexts"]))
		return;
	
	if ([self installKext:_toolsOutputTextView kextPath:kextPath useSavePanel:YES])
		[self rebuildKextCacheAndRepairPermissions:_toolsOutputTextView];
}

- (BOOL)rebuildKextCacheAndRepairPermissions:(NSTextView *)textView
{
	if (requestAdministratorRights() != 0)
		return NO;
	
	[self disableGatekeeperAndMountDiskReadWrite:textView forced:NO];
	
	[self appendTextView:textView foregroundColor:[NSColor textColor] backgroundColor:_orangeColor text:GetLocalizedString(@"Rebuilding KextCache and Repairing Permissions...\n")];
	
	[_progressCancelButton setTag:NO];
	[_progressCancelButton setAction:@selector(progressCancelButtonClicked:)];
	[_progressLevelIndicator setDoubleValue:0.0];
	[_progressLevelIndicator setMinValue:0.0];
	[_progressLevelIndicator setMaxValue:1.0];
	[_progressImageView setImage:[NSImage imageNamed:NSImageNameApplicationIcon]];
	[_progressTitleTextField setStringValue:GetLocalizedString(@"Rebuild KextCache and Repair Permissions")];
	[_progressMessageTextField setStringValue:@""];
	
	__block bool cancelProgress = NO;
	
	void (^progressBlock)(void);
	progressBlock =
	^{
		[self launchCommandAsAdmin:textView launchPath:@"chown" arguments:@[@"-v", @"-R", @"root:wheel", @"/System/Library/Extensions"] cancelProgress:&cancelProgress progressPercent:0.1];
		
		if (!cancelProgress)
			[self launchCommandAsAdmin:textView launchPath:@"touch" arguments:@[@"/System/Library/Extensions"] cancelProgress:&cancelProgress progressPercent:0.2];

		if (!cancelProgress)
			[self launchCommandAsAdmin:textView launchPath:@"chmod" arguments:@[@"-v", @"-R", @"755", @"/Library/Extensions"] cancelProgress:&cancelProgress progressPercent:0.3];
		
		if (!cancelProgress)
			[self launchCommandAsAdmin:textView launchPath:@"chown" arguments:@[@"-v", @"-R", @"root:wheel", @"/Library/Extensions"] cancelProgress:&cancelProgress progressPercent:0.4];
		
		if (!cancelProgress)
			[self launchCommandAsAdmin:textView launchPath:@"touch" arguments:@[@"/Library/Extensions"] cancelProgress:&cancelProgress progressPercent:0.5];
		
		if (!cancelProgress)
			[self launchCommandAsAdmin:textView launchPath:@"kextcache" arguments:@[@"-i", @"/"] cancelProgress:&cancelProgress progressPercent:1.0];
		
		// Flushes /AppleInternal/Library/Extensions (used by Apple developers)
		//if (!cancelProgress)
		//	[self launchCommandAsAdmin:textView launchPath:@"kextcache" arguments:@[@"-u", @"/"] cancelProgress:&cancelProgress progressPercent:1.0];

		dispatch_async(dispatch_get_main_queue(), ^{
			[_window endSheet:_progressWindow];
		});
	};
	
	dispatch_queue_t queue = dispatch_get_global_queue(0, 0);
	dispatch_async(queue,progressBlock);
	
	[_window beginSheet:_progressWindow completionHandler:^(NSModalResponse returnCode)
	 {
		 [NSApp stopModalWithCode:returnCode];
	 }];
	
	return ([NSApp runModalForWindow:_window] == NSOKButton);
}

- (BOOL)createWindowsBluetoothRegistryFile
{
	if (requestAdministratorRights() != 0)
		return NO;
	
	NSError *error = nil;
	NSString *stdoutString = nil;
	
	if (!launchCommandAsAdmin(@"/usr/bin/defaults", @[@"read", BluetoothPath1, @"LinkKeys"], &stdoutString))
		launchCommandAsAdmin(@"/usr/bin/defaults", @[@"read", BluetoothPath2, @"LinkKeys"], &stdoutString);

	if (stdoutString == nil)
		return NO;
	
	// Convert new NSData to old format
	NSRegularExpression *regEx = [NSRegularExpression regularExpressionWithPattern:@"\\{length = \\d+, bytes = 0x([0-9a-fA-F .]*)\\}" options:0 error:&error];
	stdoutString = [regEx stringByReplacingMatchesInString:stdoutString options:0 range:NSMakeRange(0, [stdoutString length]) withTemplate:@"<$1>"];
	
	NSDictionary *linkKeysDictionary = [NSPropertyListSerialization propertyListWithData:[stdoutString dataUsingEncoding:NSUTF8StringEncoding] options:kNilOptions format:nil error:&error];
	
	if (linkKeysDictionary == nil)
		return NO;
	
	NSMutableString *outputString = [NSMutableString string];
	
	[outputString appendString:@"Windows Registry Editor Version 5.00\n"];
	[outputString appendString:@"\n"];
	[outputString appendString:@"[HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\Services\\BTHPORT\\Parameters\\Keys]\n"];
	[outputString appendString:@"\n"];
	
	for (NSString *linkKey in linkKeysDictionary.allKeys)
	{
		NSDictionary *linkKeyDictionary = [linkKeysDictionary objectForKey:linkKey];
		NSString *windowsLinkKey = [linkKey stringByReplacingOccurrencesOfString:@"-" withString:@""];
		
		[outputString appendFormat:@"[HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\Services\\BTHPORT\\Parameters\\Keys\\%@]\n", windowsLinkKey];
		
		for (NSString *key in linkKeyDictionary.allKeys)
		{
			NSData *keyData = [linkKeyDictionary objectForKey:key];
			NSString *windowsKey = [key stringByReplacingOccurrencesOfString:@"-" withString:@""];
			NSData *reversedKeyData = getReverseData(keyData);
			
			[outputString appendFormat:@"\"%@\"=hex:%@\n", windowsKey, getByteString(reversedKeyData, @",", @"", false, false)];
		}
	}
	
	NSArray *pathArray = NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES);
	NSString *desktopPath = [pathArray objectAtIndex:0];
	NSString *outputFilePath = [desktopPath stringByAppendingPathComponent:@"Bluetooth.reg"];
	[outputString writeToFile:outputFilePath atomically:YES encoding:NSUTF8StringEncoding error:&error];
	
	NSArray *fileURLs = [NSArray arrayWithObjects:[NSURL fileURLWithPath:outputFilePath], nil];
	[[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:fileURLs];
	
	return YES;
}

- (void)createWindowsUTCRegistryFiles
{
	NSError *error;
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSArray *pathArray = NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES);
	NSString *desktopPath = [pathArray objectAtIndex:0];
	NSString *winUTCOnPath = [desktopPath stringByAppendingPathComponent:@"WinUTCOn.reg"];
	NSString *winUTCOffPath = [desktopPath stringByAppendingPathComponent:@"WinUTCOff.reg"];
	
	NSBundle *mainBundle = [NSBundle mainBundle];
	NSString *srcPath = nil;
	
	if ((srcPath = [mainBundle pathForResource:@"WinUTCOn" ofType:@"reg" inDirectory:@"Windows"]))
		[fileManager copyItemAtPath:srcPath toPath:winUTCOnPath error:&error];
	
	if ((srcPath = [mainBundle pathForResource:@"WinUTCOff" ofType:@"reg" inDirectory:@"Windows"]))
		[fileManager copyItemAtPath:srcPath toPath:winUTCOffPath error:&error];
	
	NSArray *fileURLs = [NSArray arrayWithObjects:[NSURL fileURLWithPath:winUTCOnPath], nil];
	[[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:fileURLs];
}

- (void)getPowerSettings
{
	// TODO: pmset -g assertions
	// TODO: pmset -g stats
	
	NSString *stdoutString = nil;
	
	bool isSystemWide = true;
	
	[_systemWidePowerSettings release];
	[_currentPowerSettings release];
	
	_systemWidePowerSettings = [[NSMutableDictionary dictionary] retain];
	_currentPowerSettings = [[NSMutableDictionary dictionary] retain];

	launchCommand(@"/usr/bin/pmset", @[@"-g"], &stdoutString);
	
	NSArray *powerManagementArray = [stdoutString componentsSeparatedByString:@"\n"];
	
	for (NSString *pmLine in powerManagementArray)
	{
		if ([pmLine isEqualToString:@"System-wide power settings:"])
			continue;
		
		if ([pmLine isEqualToString:@"Currently in use:"])
		{
			isSystemWide = false;
			continue;
		}
		
		NSMutableArray *pmArray = [[[pmLine componentsSeparatedByString:@" "] mutableCopy] autorelease];
		[pmArray removeObject:@""];
		
		if (pmArray.count < 2)
			continue;
		
		if (isSystemWide)
			[_systemWidePowerSettings setObject:pmArray[1] forKey:pmArray[0]];
		else
			[_currentPowerSettings setObject:pmArray[1] forKey:pmArray[0]];
	}
	
	[_powerSettingsTableView reloadData];
}

- (BOOL)fixSleepImage
{
	if (requestAdministratorRights() != 0)
		return NO;
	
	// sudo pmset -a standby 0
	// sudo pmset -a womp 0
	// sudo pmset -a powernap 0
	// sudo pmset -a disksleep 0
	// sudo pmset -a autopoweroff 0
	// sudo pmset -a sleep 1
	
	// hibernatemode=0
	// womp=0
	// networkoversleep=0
	// sleep=0
	// Sleep=On
	// ttyskeepawake=1
	// hibernatefile=/var/vm/sleepimage
	// disksleep=0
	// gpuswitch=2
	// displaysleep=10
	
	NSString *stdoutString = nil;
	NSString *hibernatefile = [_currentPowerSettings objectForKey:@"hibernatefile"];
	NSString *hibernatemode = [_currentPowerSettings objectForKey:@"hibernatemode"];
	NSString *proximitywake = [_currentPowerSettings objectForKey:@"proximitywake"];
	
	launchCommandAsAdmin(@"/usr/bin/pmset", @[@"-a", @"hibernatemode", @"0"], &stdoutString);
									   
	if (proximitywake != nil)
		launchCommandAsAdmin(@"/usr/bin/pmset", @[@"-a", @"proximitywake", @"0"], &stdoutString);
	
	if (hibernatefile != nil)
	{
		launchCommandAsAdmin(@"/bin/rm", @[hibernatefile], &stdoutString);
		launchCommandAsAdmin(@"/usr/bin/touch", @[hibernatefile], &stdoutString);
		launchCommandAsAdmin(@"/usr/bin/chflags", @[@"uchg", hibernatefile], &stdoutString);
	}
	
	// Always check your hibernatemode after updates and disable it.
	// System updates tend to re-enable it, although making sleepimage a directory tends to help.
	//launchCommandAsAdmin(@"/bin/mkdir", @[hibernatefile], &stdoutString);
	
	[self getPowerSettings];
	
	return YES;
}

- (IBAction)progressCancelButtonClicked:(id)sender
{
	NSButton *cancelButton = (NSButton *)sender;
	[cancelButton setTag:YES];
}
	
- (bool)tryUpdateProgress:(double)progressPercent
{
	[_progressLevelIndicator setDoubleValue:progressPercent];
	[_progressLevelIndicator setNeedsDisplay:YES];
	
	if (_progressCancelButton.tag)
	{
		[_window endSheet:_progressWindow];
		return YES;
	}
	
	return NO;
}

- (bool)launchCommandAsAdmin:(NSTextView *)textView launchPath:(NSString *)launchPath arguments:(NSArray *)arguments
{
	NSString *stdoutString = nil, *stderrString = nil;
	NSString *argumentsString = [arguments componentsJoinedByString:@" "];
	NSString *fullPath = [NSString stringWithFormat:@"%@ %@\n", launchPath, argumentsString];
	
	[self appendTextView:textView foregroundColor:[NSColor textColor] backgroundColor:_orangeColor text:fullPath];
	
	bool result = launchCommandAsAdmin(launchPath, arguments, &stdoutString, &stderrString);
	
	[self appendTextView:textView text:stdoutString];
	[self appendTextView:textView foregroundColor:[NSColor textColor] backgroundColor:_redColor text:stderrString];
	
	return result;
}

- (bool)launchCommandAsAdmin:(NSTextView *)textView launchPath:(NSString *)launchPath arguments:(NSArray *)arguments cancelProgress:(bool *)cancelProgress progressPercent:(double)progressPercent
{
	NSString *stdoutString = nil, *stderrString = nil;
	NSString *argumentsString = [arguments componentsJoinedByString:@" "];
	NSString *fullPath = [NSString stringWithFormat:@"%@ %@\n", launchPath, argumentsString];
	
	dispatch_async(dispatch_get_main_queue(), ^{
		[self appendTextView:textView foregroundColor:[NSColor textColor] backgroundColor:_orangeColor text:fullPath];
	});
	
	bool result = launchCommandAsAdmin(launchPath, arguments, &stdoutString, &stderrString);
	
	dispatch_async(dispatch_get_main_queue(), ^{
		[self appendTextView:textView text:stdoutString];
		[self appendTextView:textView foregroundColor:[NSColor textColor] backgroundColor:_redColor text:stderrString];
		
		*cancelProgress = [self tryUpdateProgress:progressPercent];
	});
	
	return result;
}

- (void)waitWith:(NSString*)title message:(NSString *)message seconds:(NSInteger)seconds
{
	[_progressCancelButton setTag:NO];
	[_progressCancelButton setAction:@selector(progressCancelButtonClicked:)];
	[_progressLevelIndicator setDoubleValue:0.0];
	[_progressLevelIndicator setMinValue:0.0];
	[_progressLevelIndicator setMaxValue:1.0];
	[_progressImageView setImage:[NSImage imageNamed:NSImageNameApplicationIcon]];
	[_progressTitleTextField setStringValue:GetLocalizedString(title)];
	[_progressMessageTextField setStringValue:GetLocalizedString(message)];
	
	__block bool cancelProgress = NO;
	
	void (^progressBlock)(void);
	progressBlock =
	^{
		for (int i = 0; i < seconds; i++)
		{
			usleep(1000000);
			
			double progressPercent = (double)(i + 1) / (double)seconds;
			
			dispatch_async(dispatch_get_main_queue(), ^{
				cancelProgress = [self tryUpdateProgress:progressPercent];
			});
			
			if (cancelProgress)
				break;
		}
		
		dispatch_async(dispatch_get_main_queue(), ^{
			[_window endSheet:_progressWindow];
		});
	};
	
	dispatch_queue_t queue = dispatch_get_global_queue(0, 0);
	dispatch_async(queue,progressBlock);
	
	[_window beginSheet:_progressWindow completionHandler:^(NSModalResponse returnCode)
	 {
		 [NSApp stopModalWithCode:returnCode];
	 }];
	
	[NSApp runModalForWindow:_window];
}

- (BOOL)getAppleIntelInfo
{
	if (requestAdministratorRights() != 0)
		return NO;
	
	[_toolsOutputTextView setString:@""];
	
	NSBundle *mainBundle = [NSBundle mainBundle];
	NSString *srcKextPath = nil;
	
	if (!(srcKextPath = [mainBundle pathForResource:@"AppleIntelInfo" ofType:@"kext" inDirectory:@"Kexts"]))
		return NO;
	
	NSString *stdoutString = nil;
	NSError *error;
	NSString *tempPath = getTempPath();
	NSString *dstKextPath = [tempPath stringByAppendingPathComponent:@"AppleIntelInfo.kext"];
	NSString *infoPath = [dstKextPath stringByAppendingPathComponent:@"Contents/Info.plist"];
	NSString *srcDatPath = @"/tmp/AppleIntelInfo.dat";
	NSString *dstDatPath = [tempPath stringByAppendingPathComponent:@"AppleIntelInfo.dat"];
	NSString *userName = NSUserName();
	
	launchCommandAsAdmin(@"/bin/cp", @[@"-r", srcKextPath, dstKextPath], &stdoutString);
	
	launchCommandAsAdmin(@"/usr/sbin/chown", @[@"-R", userName, dstKextPath], &stdoutString);
	
	NSMutableDictionary *infoDictionary = [NSMutableDictionary dictionaryWithContentsOfFile:infoPath];
	NSMutableDictionary *ioKitPersonalities = [[[infoDictionary objectForKey:@"IOKitPersonalities"] mutableCopy] autorelease];
	NSMutableDictionary *appleIntelInfoDictionary = [[[ioKitPersonalities objectForKey:@"AppleIntelInfo"] mutableCopy] autorelease];
	
	[appleIntelInfoDictionary setObject:[NSNumber numberWithBool:_settings.AII_EnableHWP] forKey:@"enableHWP"];
	[appleIntelInfoDictionary setObject:[NSNumber numberWithBool:_settings.AII_LogCStates] forKey:@"logCStates"];
	[appleIntelInfoDictionary setObject:[NSNumber numberWithBool:_settings.AII_LogIGPU] forKey:@"logIGPU"];
	[appleIntelInfoDictionary setObject:[NSNumber numberWithBool:_settings.AII_LogIPGStyle] forKey:@"logIPGStyle"];
	[appleIntelInfoDictionary setObject:[NSNumber numberWithBool:_settings.AII_LogIntelRegs] forKey:@"logIntelRegs"];
	[appleIntelInfoDictionary setObject:[NSNumber numberWithBool:_settings.AII_LogMSRs] forKey:@"logMSRs"];
	
	[ioKitPersonalities setObject:appleIntelInfoDictionary forKey:@"AppleIntelInfo"];
	[infoDictionary setObject:ioKitPersonalities forKey:@"IOKitPersonalities"];
	
	[infoDictionary writeToFile:infoPath atomically:YES];
	
	launchCommandAsAdmin(@"/usr/sbin/chown", @[@"-R", @"root:wheel", dstKextPath], &stdoutString);
	launchCommandAsAdmin(@"/bin/chmod", @[@"-R", @"755", dstKextPath], &stdoutString);
	launchCommandAsAdmin(@"/sbin/kextload", @[dstKextPath], &stdoutString);
	if (_settings.AII_LogCStates)
		[self waitWith:@"Logging CStates" message:@"Perform CPU intensive activity..." seconds:30];
	launchCommandAsAdmin(@"/sbin/kextunload", @[dstKextPath], &stdoutString);
	launchCommandAsAdmin(@"/bin/cp", @[srcDatPath, dstDatPath], &stdoutString);
	launchCommandAsAdmin(@"/usr/sbin/chown", @[userName, dstDatPath], &stdoutString);
	launchCommandAsAdmin(@"/bin/chmod", @[@"777", dstDatPath], &stdoutString);
	
	NSString *appleIntelInfoDat = [NSString stringWithContentsOfFile:dstDatPath encoding:NSUTF8StringEncoding error:&error];
	
	if (appleIntelInfoDat != nil)
		[_toolsOutputTextView setString:appleIntelInfoDat];
	
	launchCommandAsAdmin(@"/bin/rm", @[@"-r", tempPath], &stdoutString);
	
	return YES;
}

- (bool)setNVRAMValue:(NSString *)name value:(NSString *)value
{
	bool success = false;
	NSString *stdoutString = nil;
	
	if (value == nil)
		success = launchCommandAsAdmin(@"/usr/sbin/nvram", @[@"-d", name], &stdoutString);
	else
		success = launchCommandAsAdmin(@"/usr/sbin/nvram", @[[NSString stringWithFormat:@"%@=%@", name, value]], &stdoutString);
	
	return success;
}

- (NSString *)getNVRAMValue:(NSString *)name
{
	NSString *stdoutString = nil;
	
	bool success = launchCommand(@"/usr/sbin/nvram", @[name], &stdoutString);
	
	if (!success || [stdoutString isEqualToString:@""] || ![stdoutString containsString:@"\t"])
		return nil;
	
	NSArray *nvramArray = [stdoutString componentsSeparatedByString:@"\t"];
	NSString *retString = [nvramArray lastObject];
	
	if ([retString hasSuffix:@"\n"])
		retString = [retString substringToIndex:[retString length] - 1];
		
	return retString;
}

- (bool)setPMValue:(NSString *)name value:(NSString *)value
{
	NSString *stdoutString = nil;
	
	return launchCommandAsAdmin(@"/usr/bin/pmset", @[@"-a", name, value], &stdoutString);
}

- (NSMutableString *)parseNVRAMValue:(NSString *)value
{
	NSMutableString *retString = [NSMutableString string];
	
	for (int i = 0; i < value.length;)
	{
		if ([value characterAtIndex:i] == '%' && i + 3 <= value.length)
		{
			NSString *hexValue = [value substringWithRange:NSMakeRange(i, 3)];
			uint32_t result = 0;
			NSScanner *scanner = [NSScanner scannerWithString:hexValue];
			[scanner setScanLocation:1];
			[scanner scanHexInt:&result];
			[retString appendFormat:@"%02X", (uint16_t)result];
			i += 3;
		}
		else
		{
			[retString appendFormat:@"%02X", [value characterAtIndex:i]];
			i++;
		}
	}
	
	return retString;
}

- (void)dumpACPITables
{
	[_toolsOutputTextView setString:@""];
	
	NSString *stdoutString = nil;
	//NSString *userName = NSUserName();
	
	NSBundle *mainBundle = [NSBundle mainBundle];
	NSString *iaslPath = [mainBundle pathForResource:@"iasl" ofType:@"" inDirectory:@"Utilities"];
	//NSString *refsPath = [mainBundle pathForResource:@"refs" ofType:@"txt" inDirectory:@"Utilities"];

	io_service_t expert;
	
	if ((expert = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("AppleACPIPlatformExpert"))))
	{
		NSOpenPanel *openPanel = [NSOpenPanel openPanel];
		[openPanel setTitle:GetLocalizedString(@"Dump ACPI Tables")];
		[openPanel setCanChooseDirectories:true];
		[openPanel setCanChooseFiles:false];
		[openPanel setCanCreateDirectories:true];
		[openPanel setPrompt:GetLocalizedString(@"Choose a destination folder")];
		
		if ([openPanel runModal] == NSFileHandlingPanelOKButton)
		{
			NSDictionary *tableDictionary = (__bridge NSDictionary *)IORegistryEntryCreateCFProperty(expert, CFSTR("ACPI Tables"), kCFAllocatorDefault, 0);
			
			for (NSString *key in tableDictionary.allKeys)
			{
				if (![key hasPrefix:@"DSDT"] && ![key hasPrefix:@"SSDT"])
					continue;
				
				NSString *fileName = [NSString stringWithFormat:@"%@/%@.aml", openPanel.URL.path, key];
				NSData *tableData = [tableDictionary objectForKey:key];
				
				[tableData writeToFile:fileName atomically:YES];
			}
			
			// iasl -da -dl -fe refs.txt DSDT.aml SSDT*.aml
			
			//launchCommand(@"/bin/cp", @[refsPath, openPanel.URL.path], &stdoutString);
			//launchCommand(@"/usr/sbin/chown", @[userName, refsPath], &stdoutString);
			
			launchCommand(iaslPath, openPanel.URL.path, @[@"-dl", @"-f", @"DSDT.aml"], &stdoutString);
			
			[self appendTextView:_toolsOutputTextView text:stdoutString];
			
			for (NSString *key in tableDictionary.allKeys)
			{
				if (![key hasPrefix:@"SSDT"])
					continue;
				
				NSString *fileName = [NSString stringWithFormat:@"%@.aml", key];
				
				launchCommand(iaslPath, openPanel.URL.path, @[@"-dl", @"-fe", @"DSDT.aml", fileName], &stdoutString);
				
				[self appendTextView:_toolsOutputTextView text:stdoutString];
			}
		}
		
		IOObjectRelease(expert);
	}
}

-(void)getOpenCoreVersion
{
	NSError *error;
	NSString *tempPath = getTempPath();
	NSURL *projFileUrl = [[NSURL URLWithString:kOpenCoreProjectFileURL] URLByAppendingPathComponent:@"project.pbxproj"];
	NSString *projFileDest = [NSString stringWithFormat:@"%@/project.pbxproj", tempPath];
	NSData *projFileData = nil;
	
	if ([[NSFileManager defaultManager] fileExistsAtPath:projFileDest])
		[[NSFileManager defaultManager] removeItemAtPath:projFileDest error:&error];
	
	projFileData = [NSData dataWithContentsOfURL:projFileUrl options:NSDataReadingUncached error:&error];
		
	if (projFileData == nil)
		return;
		
	[projFileData writeToFile:projFileDest atomically:YES];
		
	NSString *projectVersion;
	
	if ([self tryGetProjectFileVersion:projFileDest projectVersion:&projectVersion])
		NSLog(@"OpenCore Version: %@", projectVersion);
	
	NSString *stdoutString = nil;
	
	launchCommand(@"/bin/rm", @[@"-Rf", tempPath], &stdoutString);
}

- (void)compileOutputNotification:(NSNotification *)notification
{
	NSDictionary *dictionary = [notification userInfo];
	NSData *fileData = [dictionary objectForKey:@"Data"];
	
	NSString *stringRead = [[NSString alloc] initWithData:fileData encoding:NSUTF8StringEncoding];
	[self appendTextView:_compileOutputTextView foregroundColor:[NSColor textColor] backgroundColor:[NSColor textBackgroundColor] text:stringRead];
	[stringRead release];
}

- (void)compileErrorNotification:(NSNotification *)notification
{
	NSDictionary *dictionary = [notification userInfo];
	NSData *fileData = [dictionary objectForKey:@"Data"];
	
	NSString *stringRead = [[NSString alloc] initWithData:fileData encoding:NSUTF8StringEncoding];
	[self appendTextView:_compileOutputTextView foregroundColor:[NSColor textColor] backgroundColor:_redColor text:stringRead];
	[stringRead release];
}

- (void)compileCompleteNotification:(NSNotification *)notification
{
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMin ofSubviewAt:(NSInteger)dividerIndex
{
	return 90.0;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedMaximumPosition ofSubviewAt:(NSInteger)dividerIndex
{
	return 500.0;
}

@end
