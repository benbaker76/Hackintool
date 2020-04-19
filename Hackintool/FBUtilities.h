//
//  FBUtilities.h
//  Hackintool
//
//  Created by Ben Baker on 7/29/18.
//  Copyright © 2018 Ben Baker. All rights reserved.
//

#ifndef FBUtilities_h
#define FBUtilities_h

#import "IntelFramebuffer.h"
#import "AppDelegate.h"
#import "IORegTools.h"
#import "MiscTools.h"
#import "Clover.h"
#import "OpenCore.h"
#import "FixEDID.h"
#import "Display.h"

#define GetLocalizedString(key) \
[[NSBundle mainBundle] localizedStringForKey:(key) value:@"" table:nil]

enum KernelVersion
{
	SnowLeopard   = 10,
	Lion          = 11,
	MountainLion  = 12,
	Mavericks     = 13,
	Yosemite      = 14,
	ElCapitan     = 15,
	Sierra        = 16,
	HighSierra    = 17,
	Mojave        = 18,
};

bool getIntelGenString(NSDictionary *fbDriversDictionary, NSString **intelGenString);
void getConfigDictionary(AppDelegate *appDelegate, NSMutableDictionary *configDictionary, bool forceAll);
void getPCIProperties(AppDelegate *appDelegate, NSMutableDictionary *configDictionary);
bool getAudioProperties(AppDelegate *appDelegate, NSString *name, NSMutableDictionary *configDictionary);
bool appendFramebufferInfoDSL(AppDelegate *appDelegate, uint32_t tab, NSMutableDictionary *configDictionary, NSString *name, NSMutableString **outputString);
void appendFramebufferInfoDSL(AppDelegate *appDelegate);
void injectUseIntelHDMI(AppDelegate *appDelegate, NSMutableDictionary *configDictionary);
bool injectWLAN(AppDelegate *appDelegate, NSMutableDictionary *configDictionary);

template <typename T>
void setMemory(T &framebuffer, uint32_t stolenMem, uint32_t fbMem, uint32_t unifiedMem)
{
	framebuffer.fStolenMemorySize = stolenMem;
	framebuffer.fFramebufferMemorySize = fbMem;
	framebuffer.fUnifiedMemorySize = unifiedMem;
}

template <typename T>
void getMemoryHaswell(T &framebuffer, bool *isMobile, uint32_t *stolenMem, uint32_t *fbMem, uint32_t *unifiedMem, uint32_t *maxStolenMem, uint32_t *totalStolenMem, uint32_t *totalCursorMem, uint32_t *maxOverallMem)
{
	*isMobile = framebuffer.fMobile;
	*stolenMem = framebuffer.fStolenMemorySize;
	*fbMem = framebuffer.fFramebufferMemorySize;
	*unifiedMem = framebuffer.fUnifiedMemorySize;
	*maxStolenMem = framebuffer.fStolenMemorySize * framebuffer.fFBMemoryCount + framebuffer.fFramebufferMemorySize + 0x100000; // 1 MB
	*totalStolenMem = calculateStolenHaswell(framebuffer.flags, framebuffer.fStolenMemorySize, framebuffer.fFBMemoryCount, framebuffer.fFramebufferMemorySize);
	*totalCursorMem = framebuffer.fPipeCount * 0x80000; // 32 KB
	*maxOverallMem = *totalCursorMem + *maxStolenMem + framebuffer.fPortCount * 0x1000; // 1 KB
}

template <typename T>
void getMemorySkylake(T &framebuffer, bool *isMobile, uint32_t *stolenMem, uint32_t *fbMem, uint32_t *unifiedMem, uint32_t *maxStolenMem, uint32_t *totalStolenMem, uint32_t *totalCursorMem, uint32_t *maxOverallMem)
{
	*isMobile = framebuffer.fMobile;
	*stolenMem = framebuffer.fStolenMemorySize;
	*fbMem = framebuffer.fFramebufferMemorySize;
	*unifiedMem = framebuffer.fUnifiedMemorySize;
	*maxStolenMem = framebuffer.fStolenMemorySize * framebuffer.fFBMemoryCount + framebuffer.fFramebufferMemorySize + 0x100000; // 1 MB
	*totalStolenMem = calculateStolenSkylake(framebuffer.flags, framebuffer.fStolenMemorySize, framebuffer.fFBMemoryCount, framebuffer.fFramebufferMemorySize);
	*totalCursorMem = framebuffer.fPipeCount * 0x80000; // 32 KB
	*maxOverallMem = *totalCursorMem + *maxStolenMem + framebuffer.fPortCount * 0x1000; // 1 KB
}

template <typename T>
void setFramebufferValues(T &framebuffer, IntConvert *intConvert)
{
	NSUInteger fieldIndex = [translateArray(g_framebufferArray) indexOfObject:GetLocalizedString(intConvert->Name)];
	
	switch (fieldIndex)
	{
		case 0: // framebufferID
			if constexpr (!std::is_same_v<T, FramebufferSNB>)
				framebuffer.framebufferID = intConvert->Uint32Value;
			break;
		case 1: // fModelNameAddr
			if constexpr (!std::is_same_v<T, FramebufferSNB> && !std::is_same_v<T, FramebufferIVB> && !std::is_same_v<T, FramebufferBDW> && !std::is_same_v<T, FramebufferHSW>)
				framebuffer.fModelNameAddr = intConvert->Uint64Value;
			break;
		case 2: // fMobile
			framebuffer.fMobile = [intConvert->StringValue isEqualToString:@"Yes"] ? 1 : 0;
			break;
		case 3: // fPipeCount
			framebuffer.fPipeCount = intConvert->DecimalValue;
			break;
		case 4: // fPortCount
			framebuffer.fPortCount = intConvert->DecimalValue;
			break;
		case 5: // fFBMemoryCount
			framebuffer.fFBMemoryCount = intConvert->DecimalValue;
			break;
		case 6: // fStolenMemorySize
			if constexpr (!std::is_same_v<T, FramebufferSNB>)
				framebuffer.fStolenMemorySize = intConvert->MemoryInBytes;
			break;
		case 7: // fFramebufferMemorySize
			if constexpr (!std::is_same_v<T, FramebufferSNB>)
				framebuffer.fFramebufferMemorySize = intConvert->MemoryInBytes;
			break;
		case 8: // fCursorMemorySize
			if constexpr (!std::is_same_v<T, FramebufferSNB> && !std::is_same_v<T, FramebufferIVB> && !std::is_same_v<T, FramebufferBDW> && !std::is_same_v<T, FramebufferSKL> && !std::is_same_v<T, FramebufferCFL> && !std::is_same_v<T, FramebufferCNL> && !std::is_same_v<T, FramebufferICLLP> && !std::is_same_v<T, FramebufferICLHP>)
				framebuffer.fCursorMemorySize = intConvert->MemoryInBytes;
			break;
		case 9: // fUnifiedMemorySize
			if constexpr (!std::is_same_v<T, FramebufferSNB>)
				framebuffer.fUnifiedMemorySize = intConvert->MemoryInBytes;
			break;
		case 10: // fBacklightFrequency
			if constexpr (!std::is_same_v<T, FramebufferCFL> && !std::is_same_v<T, FramebufferCNL> && !std::is_same_v<T, FramebufferICLLP>)
				framebuffer.fBacklightFrequency = intConvert->DecimalValue;
			break;
		case 11: // fBacklightMax
			if constexpr (!std::is_same_v<T, FramebufferCFL> && !std::is_same_v<T, FramebufferCNL> && !std::is_same_v<T, FramebufferICLLP>)
				framebuffer.fBacklightMax = intConvert->DecimalValue;
			break;
		case 12: // Flags
			if constexpr (!std::is_same_v<T, FramebufferSNB> && !std::is_same_v<T, FramebufferIVB>)
				framebuffer.flags.value = intConvert->Uint32Value;
			break;
		case 13: // fBTTableOffsetIndexSlice
			if constexpr (!std::is_same_v<T, FramebufferSNB> && !std::is_same_v<T, FramebufferIVB> && !std::is_same_v<T, FramebufferHSW> && !std::is_same_v<T, FramebufferBDW> && !std::is_same_v<T, FramebufferICLLP> && !std::is_same_v<T, FramebufferICLHP>)
				framebuffer.fBTTableOffsetIndexSlice = intConvert->Uint8Value;
			break;
		case 14: // fBTTableOffsetIndexNormal
			if constexpr (!std::is_same_v<T, FramebufferSNB> && !std::is_same_v<T, FramebufferIVB> && !std::is_same_v<T, FramebufferHSW> && !std::is_same_v<T, FramebufferBDW> && !std::is_same_v<T, FramebufferICLLP> && !std::is_same_v<T, FramebufferICLHP>)
				framebuffer.fBTTableOffsetIndexNormal = intConvert->Uint8Value;
			break;
		case 15: // fBTTableOffsetIndexHDMI
			if constexpr (!std::is_same_v<T, FramebufferSNB> && !std::is_same_v<T, FramebufferIVB> && !std::is_same_v<T, FramebufferHSW> && !std::is_same_v<T, FramebufferBDW> && !std::is_same_v<T, FramebufferICLLP> && !std::is_same_v<T, FramebufferICLHP>)
				framebuffer.fBTTableOffsetIndexHDMI = intConvert->Uint8Value;
			break;
		case 16: // CamelliaVersion
			if constexpr (!std::is_same_v<T, FramebufferSNB> && !std::is_same_v<T, FramebufferIVB>)
			{
				NSUInteger fieldIndex = [translateArray(g_camelliaArray) indexOfObject:GetLocalizedString(intConvert->StringValue)];
				
				switch (fieldIndex)
				{
					case 0:
						framebuffer.camelliaVersion = CamelliaDisabled;
						break;
					case 1:
						framebuffer.camelliaVersion = CamelliaV1;
						break;
					case 2:
						framebuffer.camelliaVersion = CamelliaV2;
						break;
					case 3:
						framebuffer.camelliaVersion = CamelliaV3;
						break;
					case 4:
						framebuffer.camelliaVersion = CamelliaUnsupported;
						break;
				}
			}
			break;
		case 17: // fNumTransactionsThreshold
			if constexpr (!std::is_same_v<T, FramebufferSNB> && !std::is_same_v<T, FramebufferIVB>)
				framebuffer.fNumTransactionsThreshold = intConvert->DecimalValue;
			break;
		case 18: // fVideoTurboFreq
			if constexpr (!std::is_same_v<T, FramebufferSNB> && !std::is_same_v<T, FramebufferIVB>)
				framebuffer.fVideoTurboFreq = intConvert->DecimalValue;
			break;
		case 19: // fBTTArraySliceAddr
			if constexpr (!std::is_same_v<T, FramebufferSNB> && !std::is_same_v<T, FramebufferIVB> && !std::is_same_v<T, FramebufferHSW> && !std::is_same_v<T, FramebufferBDW> && !std::is_same_v<T, FramebufferICLLP> && !std::is_same_v<T, FramebufferICLHP>)
				framebuffer.fBTTArraySliceAddr = intConvert->Uint64Value;
			break;
		case 20: // fBTTArrayNormalAddr
			if constexpr (!std::is_same_v<T, FramebufferSNB> && !std::is_same_v<T, FramebufferIVB> && !std::is_same_v<T, FramebufferHSW> && !std::is_same_v<T, FramebufferBDW> && !std::is_same_v<T, FramebufferICLLP> && !std::is_same_v<T, FramebufferICLHP>)
				framebuffer.fBTTArrayNormalAddr = intConvert->Uint64Value;
			break;
		case 21: // fBTTArrayHDMIAddr
			if constexpr (!std::is_same_v<T, FramebufferSNB> && !std::is_same_v<T, FramebufferIVB> && !std::is_same_v<T, FramebufferHSW> && !std::is_same_v<T, FramebufferBDW> && !std::is_same_v<T, FramebufferICLLP> && !std::is_same_v<T, FramebufferICLHP>)
				framebuffer.fBTTArrayHDMIAddr = intConvert->Uint64Value;
			break;
		case 22: // fSliceCount
			if constexpr (!std::is_same_v<T, FramebufferSNB> && !std::is_same_v<T, FramebufferIVB> && !std::is_same_v<T, FramebufferHSW> && !std::is_same_v<T, FramebufferBDW>)
				framebuffer.fSliceCount = intConvert->DecimalValue;
			break;
		case 23: // fEuCount
			if constexpr (!std::is_same_v<T, FramebufferSNB> && !std::is_same_v<T, FramebufferIVB> && !std::is_same_v<T, FramebufferHSW> && !std::is_same_v<T, FramebufferBDW>)
				framebuffer.fEuCount = intConvert->DecimalValue;
			break;
	}
}

template <typename T>
void setConnectorValues(T &connectorInfo, IntConvert *intConvert)
{
	NSUInteger fieldIndex = [translateArray(g_connectorArray) indexOfObject:GetLocalizedString(intConvert->Name)];
	
	switch (fieldIndex)
	{
		case 0:
			connectorInfo->index = intConvert->DecimalValue;
			break;
		case 1:
			connectorInfo->busID = intConvert->Uint8Value;
			break;
		case 2:
			connectorInfo->pipe = intConvert->DecimalValue;
			break;
		case 3:
		{
			NSUInteger fieldIndex = [translateArray(g_connectorTypeArray) indexOfObject:GetLocalizedString(intConvert->StringValue)];

			switch (fieldIndex)
			{
				case 0:
					connectorInfo->type = ConnectorZero;
					break;
				case 1:
					connectorInfo->type = ConnectorDummy;
					break;
				case 2:
					connectorInfo->type = ConnectorLVDS;
					break;
				case 3:
					connectorInfo->type = ConnectorDigitalDVI;
					break;
				case 4:
					connectorInfo->type = ConnectorSVID;
					break;
				case 5:
					connectorInfo->type = ConnectorVGA;
					break;
				case 6:
					connectorInfo->type = ConnectorDP;
					break;
				case 7:
					connectorInfo->type = ConnectorHDMI;
					break;
				case 8:
					connectorInfo->type = ConnectorAnalogDVI;
					break;
			}
			break;
		}
		case 4:
			connectorInfo->flags.value = intConvert->Uint32Value;
			break;
	}
}

template <typename T>
void applyUserPatch(AppDelegate *appDelegate, NSDictionary *propertyDictionary, NSString *propertyName, int propertyOffset, int propertySize)
{
	NSInteger intelGen = [appDelegate.intelGenComboBox indexOfSelectedItem];
	NSInteger platformIDIndex = [appDelegate.platformIDComboBox indexOfSelectedItem];
	
	if (intelGen == -1 || platformIDIndex == -1)
		return;
	
	T *modifiedFramebufferPointer = &reinterpret_cast<T *>(appDelegate.modifiedFramebufferList)[platformIDIndex];
	
	NSData *propertyData = [propertyDictionary objectForKey:propertyName];
	
	if (propertyData == nil)
		return;
	
	memcpy(reinterpret_cast<uint8_t *>(modifiedFramebufferPointer) + propertyOffset, [propertyData bytes], MIN(propertySize, [propertyData length]));
}

template <typename T1, typename T2>
void applyUserConnectorsPatch(AppDelegate *appDelegate, NSDictionary *propertyDictionary)
{
	uint32_t platformID = [appDelegate getPlatformID];
	
	for (int i = 0; i < 3; i++)
	{
		uint32_t conEnable = 0;
		
		if (!getUInt32PropertyValue(appDelegate, propertyDictionary, [NSString stringWithFormat:@"framebuffer-con%d-enable", i], &conEnable) || !conEnable)
			continue;
		
		applyUserPatch<T1>(appDelegate, propertyDictionary, [NSString stringWithFormat:@"framebuffer-con%d-index", i], offsetof(T1, connectors) + offsetof(T2, index) + sizeof(T2) * i, membersize(T2, index));
		applyUserPatch<T1>(appDelegate, propertyDictionary, [NSString stringWithFormat:@"framebuffer-con%d-busid", i], offsetof(T1, connectors) + offsetof(T2, busID) + sizeof(T2) * i, membersize(T2, busID));
		applyUserPatch<T1>(appDelegate, propertyDictionary, [NSString stringWithFormat:@"framebuffer-con%d-pipe", i], offsetof(T1, connectors) + offsetof(T2, pipe) + sizeof(T2) * i, membersize(T2, pipe));
		applyUserPatch<T1>(appDelegate, propertyDictionary, [NSString stringWithFormat:@"framebuffer-con%d-type", i], offsetof(T1, connectors) + offsetof(T2, type) + sizeof(T2) * i, membersize(T2, type));
		applyUserPatch<T1>(appDelegate, propertyDictionary, [NSString stringWithFormat:@"framebuffer-con%d-flags", i], offsetof(T1, connectors) + offsetof(T2, flags) + sizeof(T2) * i, membersize(T2, flags));
		
		applyUserPatch<T1>(appDelegate, propertyDictionary, [NSString stringWithFormat:@"framebuffer-con%d-alldata", i], offsetof(T1, connectors) + sizeof(T2) * i, INT_MAX);
		applyUserPatch<T1>(appDelegate, propertyDictionary, [NSString stringWithFormat:@"framebuffer-con%d-%08X-alldata", i, platformID], offsetof(T1, connectors) + sizeof(T2) * i, INT_MAX);
		applyUserPatch<T1>(appDelegate, propertyDictionary, [NSString stringWithFormat:@"framebuffer-con%d-%08x-alldata", i, platformID], offsetof(T1, connectors) + sizeof(T2) * i, INT_MAX);
	}
}

template <typename T>
void applyUserPatchFindAndReplace(AppDelegate *appDelegate, NSDictionary *propertyDictionary)
{
	uint32_t platformID = [appDelegate getPlatformID];
	
	for (int i = 0; i < 10; i++)
	{
		uint32_t patchEnable = 0;
		
		if (!getUInt32PropertyValue(appDelegate, propertyDictionary, [NSString stringWithFormat:@"framebuffer-patch%d-enable", i], &patchEnable) || !patchEnable)
			continue;
		
		uint32_t framebufferID = 0;
		
		if (getUInt32PropertyValue(appDelegate, propertyDictionary, [NSString stringWithFormat:@"framebuffer-patch%d-framebufferid", i], &framebufferID))
			if (platformID != framebufferID)
				continue;
		
		NSData *findData = [propertyDictionary objectForKey:[NSString stringWithFormat:@"framebuffer-patch%d-find", i]];
		NSData *replaceData = [propertyDictionary objectForKey:[NSString stringWithFormat:@"framebuffer-patch%d-replace", i]];
		uint32_t count = 0;
		
		if (!getUInt32PropertyValue(appDelegate, propertyDictionary, [NSString stringWithFormat:@"framebuffer-patch%d-count", i], &count))
			count = 1;
		
		if (findData == nil || replaceData == nil)
			continue;
		
		applyFindAndReplacePatch(findData, replaceData, appDelegate.originalFramebufferList, appDelegate.modifiedFramebufferList, sizeof(appDelegate.modifiedFramebufferList), count);
	}
}

template <typename T>
void applyUserSettings(AppDelegate *appDelegate, NSDictionary *propertyDictionary)
{
	Settings settings = appDelegate.settings;
	uint32_t disableeGPU = 0, enableHDMI20 = 0, gfxYTile = 0, deviceID = 0, hdmiInfiniteLoopFix = 0;
	uint32_t lspcon_Enable = 0, lspcon_ConnectorIndex = 0, lspcon_PreferredModeIndex = 0;
	NSMutableArray *deviceIDArray = nil;
	
	if (getUInt32PropertyValue(appDelegate, propertyDictionary, @"device-id", &deviceID))
	{
		if ([appDelegate getDeviceIDArray:&deviceIDArray])
		{
			uint32_t deviceIDIndex = (uint32_t)[deviceIDArray indexOfObject:@(deviceID)];
			[[appDelegate injectDeviceIDComboBox] selectItemAtIndex:deviceIDIndex];
			settings.InjectDeviceID = true;
		}
	}
	
	if (getUInt32PropertyValue(appDelegate, propertyDictionary, @"disable-external-gpu", &disableeGPU))
		settings.DisableeGPU = disableeGPU;
	
	if (getUInt32PropertyValue(appDelegate, propertyDictionary, @"enable-hdmi20", &enableHDMI20))
		settings.EnableHDMI20 = enableHDMI20;
	
	if (getUInt32PropertyValue(appDelegate, propertyDictionary, @"AAPL,GfxYTile", &gfxYTile))
		settings.GfxYTileFix = gfxYTile;
	
	if (getUInt32PropertyValue(appDelegate, propertyDictionary, @"enable-hdmi-dividers-fix", &hdmiInfiniteLoopFix))
		settings.HDMIInfiniteLoopFix = hdmiInfiniteLoopFix;
	
	if (getUInt32PropertyValue(appDelegate, propertyDictionary, @"enable-lspcon-support", &lspcon_Enable))
		settings.LSPCON_Enable = lspcon_Enable;
	
	bool connectorFound = NO;
	
	for (int i = 0; i < 4; i++)
	{
		if (getUInt32PropertyValue(appDelegate, propertyDictionary, [NSString stringWithFormat:@"framebuffer-con%d-has-lspcon", i], &lspcon_ConnectorIndex))
		{
			settings.LSPCON_AutoDetect = NO;
			settings.LSPCON_Connector = YES;
			settings.LSPCON_ConnectorIndex = i;
			
			connectorFound = YES;
		}
		
		if (getUInt32PropertyValue(appDelegate, propertyDictionary, [NSString stringWithFormat:@"framebuffer-con%d-preferred-lspcon-mode", i], &lspcon_PreferredModeIndex))
		{
			settings.LSPCON_PreferredMode = YES;
			settings.LSPCON_PreferredModeIndex = lspcon_PreferredModeIndex;
			
			connectorFound = YES;
		}
		
		if (connectorFound)
			break;
	}

	[appDelegate setSettings:settings];
	[appDelegate updateSettingsGUI];
}

template <typename T>
void applyUserPatch(AppDelegate *appDelegate, NSDictionary *propertyDictionary)
{
	applyUserSettings<T>(appDelegate, propertyDictionary);
	
	uint32_t platformID = [appDelegate getPlatformID];
	uint32_t patchEnable = 0, framebufferID = 0;
	
	if (!getUInt32PropertyValue(appDelegate, propertyDictionary, @"framebuffer-patch-enable", &patchEnable) || !patchEnable)
		return;
	
	if (!getUInt32PropertyValue(appDelegate, propertyDictionary, @"AAPL,snb-platform-id", &framebufferID))
		getUInt32PropertyValue(appDelegate, propertyDictionary, @"AAPL,ig-platform-id", &framebufferID);
	
	if (platformID != framebufferID)
		return;
	
	applyUserPatchFindAndReplace<T>(appDelegate, propertyDictionary);
	
	if (getUInt32PropertyValue(appDelegate, propertyDictionary, @"framebuffer-framebufferid", &framebufferID))
		if (platformID != framebufferID)
			return;

	applyUserPatch<T>(appDelegate, propertyDictionary, @"framebuffer-mobile", offsetof(T, fMobile), membersize(T, fMobile));
	applyUserPatch<T>(appDelegate, propertyDictionary, @"framebuffer-pipecount", offsetof(T, fPipeCount), membersize(T, fPipeCount));
	applyUserPatch<T>(appDelegate, propertyDictionary, @"framebuffer-portcount", offsetof(T, fPortCount), membersize(T, fPortCount));
	applyUserPatch<T>(appDelegate, propertyDictionary, @"framebuffer-memorycount", offsetof(T, fFBMemoryCount), membersize(T, fFBMemoryCount));
	if constexpr (!std::is_same_v<T, FramebufferSNB>)
	{
		applyUserPatch<T>(appDelegate, propertyDictionary, @"framebuffer-stolenmem", offsetof(T, fStolenMemorySize), membersize(T, fStolenMemorySize));
		applyUserPatch<T>(appDelegate, propertyDictionary, @"framebuffer-fbmem", offsetof(T, fFramebufferMemorySize), membersize(T, fFramebufferMemorySize));
		applyUserPatch<T>(appDelegate, propertyDictionary, @"framebuffer-unifiedmem", offsetof(T, fUnifiedMemorySize), membersize(T, fUnifiedMemorySize));
		if constexpr (!std::is_same_v<T, FramebufferIVB>)
		{
			applyUserPatch<T>(appDelegate, propertyDictionary, @"framebuffer-flags", offsetof(T, flags), membersize(T, flags));
			applyUserPatch<T>(appDelegate, propertyDictionary, @"framebuffer-camellia", offsetof(T, camelliaVersion), membersize(T, camelliaVersion));
		}
	}
	
	if constexpr (std::is_same_v<T, FramebufferICLLP> || std::is_same_v<T, FramebufferICLHP>)
		applyUserConnectorsPatch<T, ConnectorInfoICL>(appDelegate, propertyDictionary);
	else
		applyUserConnectorsPatch<T, ConnectorInfo>(appDelegate, propertyDictionary);
}

template <typename T>
void applyAutoPatching(AppDelegate *appDelegate)
{
	NSInteger intelGen = [appDelegate.intelGenComboBox indexOfSelectedItem];
	NSInteger platformIDIndex = [appDelegate.platformIDComboBox indexOfSelectedItem];
	
	if (intelGen == -1 || platformIDIndex == -1)
		return;
	
	Settings settings = [appDelegate settings];
	
	T *originalFramebufferPointer = &reinterpret_cast<T *>(appDelegate.originalFramebufferList)[platformIDIndex];
	T *modifiedFramebufferPointer = &reinterpret_cast<T *>(appDelegate.modifiedFramebufferList)[platformIDIndex];
	
	if constexpr (!std::is_same_v<T, FramebufferSNB>)
	{
		if (settings.DVMTPrealloc32MB)
		{
			modifiedFramebufferPointer->fStolenMemorySize = 0x1300000;		// 19 MB (19922944 bytes)
			modifiedFramebufferPointer->fFramebufferMemorySize = 0x900000;	// 9 MB (9437184 bytes)
		}
		
		if (settings.VRAM2048MB)
			modifiedFramebufferPointer->fUnifiedMemorySize = 0x80000000;	// 2048 MB (2147483648 bytes)
	}
	
	if (settings.FBPortLimit)
	{
		// FIXME: Should these two be included?
		//modifiedFramebufferPointer->fPipeCount = settings.FBPortCount;
		modifiedFramebufferPointer->fPortCount = settings.FBPortCount;
		//modifiedFramebufferPointer->fMemoryCount = settings.FBPortCount;
	}
	
	for (int i = 0; i < arrsize(originalFramebufferPointer->connectors); i++)
	{
		bool disablePort = (settings.FBPortLimit && i >= settings.FBPortCount);
		bool dpToHDMI = (settings.DPtoHDMI && originalFramebufferPointer->connectors[i].type == ConnectorDP);
		bool hotplugRebootFix = (modifiedFramebufferPointer->connectors[i].index != -1 && settings.HotplugRebootFix);
		
		if (disablePort)
		{
			// FIXME: Is this enough to disable a port?
			modifiedFramebufferPointer->connectors[i].index = -1;
			//modifiedFramebufferPointer->connectors[i].busID = 0;
			//modifiedFramebufferPointer->connectors[i].pipe = 0;
			//modifiedFramebufferPointer->connectors[i].type = ConnectorDummy;
			//modifiedFramebufferPointer->connectors[i].flags.value = 0;
		}
		else
		{
			if (dpToHDMI)
				modifiedFramebufferPointer->connectors[i].type = ConnectorHDMI;
			
			if (hotplugRebootFix)
				modifiedFramebufferPointer->connectors[i].pipe = 18;
		}
	}
}

template <typename T>
void resetAutoPatching(AppDelegate *appDelegate)
{
	NSInteger intelGen = [appDelegate.intelGenComboBox indexOfSelectedItem];
	NSInteger platformIDIndex = [appDelegate.platformIDComboBox indexOfSelectedItem];
	
	if (intelGen == -1 || platformIDIndex == -1)
		return;
	
	Settings settings = [appDelegate settings];
	
	T *originalFramebufferPointer = &reinterpret_cast<T *>(appDelegate.originalFramebufferList)[platformIDIndex];
	T *modifiedFramebufferPointer = &reinterpret_cast<T *>(appDelegate.modifiedFramebufferList)[platformIDIndex];
	
	if constexpr (!std::is_same_v<T, FramebufferSNB>)
	{
		if (!settings.DVMTPrealloc32MB)
		{
			modifiedFramebufferPointer->fStolenMemorySize = originalFramebufferPointer->fStolenMemorySize;
			modifiedFramebufferPointer->fFramebufferMemorySize = originalFramebufferPointer->fFramebufferMemorySize;
		}
		
		if (!settings.VRAM2048MB)
			modifiedFramebufferPointer->fUnifiedMemorySize = originalFramebufferPointer->fUnifiedMemorySize;
	}
	
	if (!settings.FBPortLimit)
	{
		// FIXME: Should these two be included?
		//modifiedFramebufferPointer->fPipeCount = originalFramebufferPointer->fPipeCount;
		modifiedFramebufferPointer->fPortCount = originalFramebufferPointer->fPortCount;
		//modifiedFramebufferPointer->fMemoryCount = originalFramebufferPointer->fMemoryCount;
	}
	
	for (int i = 0; i < arrsize(originalFramebufferPointer->connectors); i++)
	{
		bool disablePort = (settings.FBPortLimit && i >= settings.FBPortCount);
		bool dpToHDMI = (settings.DPtoHDMI && originalFramebufferPointer->connectors[i].type == ConnectorDP);
		bool hotplugRebootFix = (modifiedFramebufferPointer->connectors[i].index != -1 && settings.HotplugRebootFix);
		
		if (!disablePort)
		{
			// FIXME: Is this enough to disable a port?
			modifiedFramebufferPointer->connectors[i].index = originalFramebufferPointer->connectors[i].index;
			//modifiedFramebufferPointer->connectors[i].busID = originalFramebufferPointer->connectors[i].busID;
			//modifiedFramebufferPointer->connectors[i].pipe = originalFramebufferPointer->connectors[i].pipe;
			//modifiedFramebufferPointer->connectors[i].type = originalFramebufferPointer->connectors[i].type;
			//modifiedFramebufferPointer->connectors[i].flags.value = originalFramebufferPointer->connectors[i].flags.value;
		}

		if (!dpToHDMI)
			modifiedFramebufferPointer->connectors[i].type = originalFramebufferPointer->connectors[i].type;
		
		if (!hotplugRebootFix)
			modifiedFramebufferPointer->connectors[i].pipe = originalFramebufferPointer->connectors[i].pipe;
	}
}

template <typename T>
void getIGPU_LSPCONProperties(AppDelegate *appDelegate, NSMutableDictionary *gpuDictionary)
{
	NSInteger intelGen = [appDelegate.intelGenComboBox indexOfSelectedItem];
	NSInteger platformIDIndex = [appDelegate.platformIDComboBox indexOfSelectedItem];
	
	if (intelGen == -1 || platformIDIndex == -1)
		return;
	
	Settings settings = [appDelegate settings];
	
	T *originalFramebufferPointer = &reinterpret_cast<T *>(appDelegate.originalFramebufferList)[platformIDIndex];
	T *modifiedFramebufferPointer = &reinterpret_cast<T *>(appDelegate.modifiedFramebufferList)[platformIDIndex];
	
	if (settings.LSPCON_Enable)
		[gpuDictionary setObject:getNSDataUInt32(1) forKey:@"enable-lspcon-support"];
	else
		return;
	
	if (settings.LSPCON_AutoDetect)
	{
		for (int i = 0; i < arrsize(originalFramebufferPointer->connectors); i++)
		{
			if (modifiedFramebufferPointer->connectors[i].type == ConnectorHDMI)
			{
				[gpuDictionary setObject:getNSDataUInt32(1) forKey:[NSString stringWithFormat:@"framebuffer-con%d-has-lspcon", i]];
				
				if (settings.LSPCON_PreferredMode)
					[gpuDictionary setObject:getNSDataUInt32(settings.LSPCON_PreferredModeIndex) forKey:[NSString stringWithFormat:@"framebuffer-con%d-preferred-lspcon-mode", i]];
			}
		}
	}
	else
	{
		[gpuDictionary setObject:getNSDataUInt32(1) forKey:[NSString stringWithFormat:@"framebuffer-con%d-has-lspcon", settings.LSPCON_ConnectorIndex]];
		
		if (settings.LSPCON_PreferredMode)
			[gpuDictionary setObject:getNSDataUInt32(settings.LSPCON_PreferredModeIndex) forKey:[NSString stringWithFormat:@"framebuffer-con%d-preferred-lspcon-mode", settings.LSPCON_ConnectorIndex]];
	}
}

template <typename T>
void getIGPUProperties(AppDelegate *appDelegate, NSMutableDictionary *configDictionary)
{	
	NSInteger intelGen = [appDelegate.intelGenComboBox indexOfSelectedItem];
	NSInteger platformIDIndex = [appDelegate.platformIDComboBox indexOfSelectedItem];

	bool framebufferPatchEnabled = (intelGen != -1 && platformIDIndex != -1);
	
	if (!framebufferPatchEnabled)
		return;
	
	Settings settings = [appDelegate settings];
	
	T *originalFramebufferPointer = nil, *modifiedFramebufferPointer = nil;

	originalFramebufferPointer = &reinterpret_cast<T *>(appDelegate.originalFramebufferList)[platformIDIndex];
	modifiedFramebufferPointer = &reinterpret_cast<T *>(appDelegate.modifiedFramebufferList)[platformIDIndex];
	
	NSMutableDictionary *devicesPropertiesDictionary = ([appDelegate isBootloaderOpenCore] ? [OpenCore getDevicePropertiesDictionaryWith:configDictionary typeName:@"Add"] : [Clover getDevicesPropertiesDictionaryWith:configDictionary]);
	NSMutableDictionary *pciDeviceDictionary;
	
	if (![appDelegate tryGetGPUDeviceDictionary:&pciDeviceDictionary])
		return;
	
	NSString *deviceName = [pciDeviceDictionary objectForKey:@"DeviceName"];
	NSString *className = [pciDeviceDictionary objectForKey:@"ClassName"];
	NSString *subClassName = [pciDeviceDictionary objectForKey:@"SubClassName"];
	NSString *devicePath = [pciDeviceDictionary objectForKey:@"DevicePath"];
	NSString *slotName = [pciDeviceDictionary objectForKey:@"SlotName"];

	NSMutableDictionary *gpuDictionary = [NSMutableDictionary dictionary];
	
	[devicesPropertiesDictionary setObject:gpuDictionary forKey:devicePath];
	
	[gpuDictionary setObject:deviceName forKey:@"model"];
	//[gpuDictionary setObject:deviceName forKey:@"AAPL,model"];
	[gpuDictionary setObject:([subClassName isEqualToString:@"???"] ? className : subClassName) forKey:@"device_type"];
	[gpuDictionary setObject:slotName forKey:@"AAPL,slot-name"];
	
	if constexpr (std::is_same_v<T, FramebufferSNB>)
	{
		uint32_t framebufferID = g_fbSandyBridge[platformIDIndex];
		[gpuDictionary setObject:getNSDataUInt32(framebufferID) forKey:@"AAPL,snb-platform-id"];
	}
	else
		[gpuDictionary setObject:getNSDataUInt32(modifiedFramebufferPointer->framebufferID) forKey:@"AAPL,ig-platform-id"];
	
	if (settings.GfxYTileFix)
	{
		// For those unfamiliar, since macOS Sierra 10.12 update, Skylake's Intel HD 530 integrated graphics has had certain graphical
		// artifacts or 'glitches' in the upper left corner of the menu bar and elsewhere. This does not occur under OS X El Capitan.
		[gpuDictionary setObject:getNSDataUInt32(1) forKey:@"AAPL,GfxYTile"];
	}
	
	if (settings.InjectDeviceID)
	{
		NSMutableArray *deviceIDArray = nil;
		
		if ([appDelegate getDeviceIDArray:&deviceIDArray])
		{
			uint32_t deviceIDIndex = (uint32_t)[[appDelegate injectDeviceIDComboBox] indexOfSelectedItem];
			uint32_t deviceID = (uint32_t)[[deviceIDArray objectAtIndex:deviceIDIndex] integerValue];
			
			[gpuDictionary setObject:getNSDataUInt32(deviceID) forKey:@"device-id"];
		}
	}
	
	if (settings.DisableeGPU)
		[gpuDictionary setObject:getNSDataUInt32(1) forKey:@"disable-external-gpu"];
	
	if (settings.EnableHDMI20)
		[gpuDictionary setObject:getNSDataUInt32(1) forKey:@"enable-hdmi20"];
	
	if (settings.HDMIInfiniteLoopFix)
		[gpuDictionary setObject:getNSDataUInt32(1) forKey:@"enable-hdmi-dividers-fix"];
	
	if (settings.DPCDMaxLinkRateFix)
	{
		NSArray *dpcdMaxLinkRateArray = @[@(0x06), @(0x0A), @(0x14), @(0x1E)];
		NSNumber *dpcdMaxLinkRateNumber = [dpcdMaxLinkRateArray objectAtIndex:settings.DPCDMaxLinkRate];
		
		[gpuDictionary setObject:getNSDataUInt32(1) forKey:@"enable-dpcd-max-link-rate-fix"];
		[gpuDictionary setObject:getNSDataUInt32([dpcdMaxLinkRateNumber unsignedIntValue]) forKey:@"dpcd-max-link-rate"];
	}
	
	if (settings.PatchEDID)
	{
		for (int i = 0; i < [appDelegate.displaysArray count]; i++)
		{
			Display *display = appDelegate.displaysArray[i];
			NSData *edidData = nil;
			[FixEDID getEDIDData:display edidData:&edidData];
			
			if (edidData != nil)
				[gpuDictionary setObject:edidData forKey:[NSString stringWithFormat:@"AAPL0%d,override-no-connect", i]];
		}
	}
	
	bool mobileHasModified = (originalFramebufferPointer->fMobile != modifiedFramebufferPointer->fMobile);
	bool pipeCountHasModified = (originalFramebufferPointer->fPipeCount != modifiedFramebufferPointer->fPipeCount);
	bool portCountHasModified = (originalFramebufferPointer->fPortCount != modifiedFramebufferPointer->fPortCount);
	bool memCountHasModified = (originalFramebufferPointer->fFBMemoryCount != modifiedFramebufferPointer->fFBMemoryCount);
	bool flagsHasModified = false;
	bool camelliaHasModified = false;
	
	if constexpr (!std::is_same_v<T, FramebufferSNB> && !std::is_same_v<T, FramebufferIVB>)
	{
		flagsHasModified = (originalFramebufferPointer->flags.value != modifiedFramebufferPointer->flags.value);
		camelliaHasModified = (originalFramebufferPointer->camelliaVersion != modifiedFramebufferPointer->camelliaVersion);
	}
	
	if (!settings.AutoDetectChanges || [appDelegate framebufferHasModified])
		[gpuDictionary setObject:getNSDataUInt32(1) forKey:@"framebuffer-patch-enable"];
	
	if (settings.AutoDetectChanges || settings.PatchAll)
	{
		if (!settings.AutoDetectChanges || mobileHasModified || pipeCountHasModified || portCountHasModified || memCountHasModified || flagsHasModified || camelliaHasModified)
		{
			if (!settings.AutoDetectChanges || mobileHasModified)
				[gpuDictionary setObject:getNSDataUInt32(modifiedFramebufferPointer->fMobile) forKey:@"framebuffer-mobile"];
			
			if (!settings.AutoDetectChanges || pipeCountHasModified)
				[gpuDictionary setObject:getNSDataUInt32(modifiedFramebufferPointer->fPipeCount) forKey:@"framebuffer-pipecount"];
			
			if (!settings.AutoDetectChanges || portCountHasModified)
				[gpuDictionary setObject:getNSDataUInt32(modifiedFramebufferPointer->fPortCount) forKey:@"framebuffer-portcount"];
			
			if (!settings.AutoDetectChanges || memCountHasModified)
				[gpuDictionary setObject:getNSDataUInt32(modifiedFramebufferPointer->fFBMemoryCount) forKey:@"framebuffer-memorycount"];
			
			if constexpr (!std::is_same_v<T, FramebufferSNB> && !std::is_same_v<T, FramebufferIVB>)
			{
				if (!settings.AutoDetectChanges || flagsHasModified)
					[gpuDictionary setObject:getNSDataUInt32(modifiedFramebufferPointer->flags.value) forKey:@"framebuffer-flags"];
				
				if (!settings.AutoDetectChanges || camelliaHasModified)
					[gpuDictionary setObject:getNSDataUInt32(modifiedFramebufferPointer->camelliaVersion) forKey:@"framebuffer-camellia"];
			}
		}
	}
	
	if (settings.AutoDetectChanges || settings.PatchVRAM)
	{
		if constexpr (!std::is_same_v<T, FramebufferSNB>)
		{
			bool stolenMemHasModified = (originalFramebufferPointer->fStolenMemorySize != modifiedFramebufferPointer->fStolenMemorySize);
			bool fbMemHasModified = (originalFramebufferPointer->fFramebufferMemorySize != modifiedFramebufferPointer->fFramebufferMemorySize);
			bool cursorMemHasModified = false;
			bool unifiedMemHasModified = (originalFramebufferPointer->fUnifiedMemorySize != modifiedFramebufferPointer->fUnifiedMemorySize);
			
			if constexpr (std::is_same_v<T, FramebufferHSW>)
				cursorMemHasModified = (originalFramebufferPointer->fCursorMemorySize != modifiedFramebufferPointer->fCursorMemorySize);
		
			if (!settings.AutoDetectChanges || stolenMemHasModified || fbMemHasModified || cursorMemHasModified || unifiedMemHasModified)
			{
				if (!settings.AutoDetectChanges || stolenMemHasModified)
					[gpuDictionary setObject:getNSDataUInt32(modifiedFramebufferPointer->fStolenMemorySize) forKey:@"framebuffer-stolenmem"];
				
				if (!settings.AutoDetectChanges || fbMemHasModified)
					[gpuDictionary setObject:getNSDataUInt32(modifiedFramebufferPointer->fFramebufferMemorySize) forKey:@"framebuffer-fbmem"];
				
				if constexpr (std::is_same_v<T, FramebufferHSW>)
				{
					if (!settings.AutoDetectChanges || cursorMemHasModified)
						[gpuDictionary setObject:getNSDataUInt32(modifiedFramebufferPointer->fCursorMemorySize) forKey:@"framebuffer-cursormem"];
				}
				
				if (!settings.AutoDetectChanges || unifiedMemHasModified)
					[gpuDictionary setObject:getNSDataUInt32(modifiedFramebufferPointer->fUnifiedMemorySize) forKey:@"framebuffer-unifiedmem"];
			}
		}
	}
	
	if (settings.AutoDetectChanges || settings.PatchConnectors)
	{
		if (settings.UseAllDataMethod)
		{
			int connectorModifiedIndex = 0;
			int totalFieldModifiedCount[4] { 0 };
			int totalConnectorModifiedCount[4] { 0 };
			
			for (int i = 0; i < arrsize(originalFramebufferPointer->connectors); i++)
			{
				int fieldModifiedCount = 0;
				
				fieldModifiedCount = (originalFramebufferPointer->connectors[i].index != modifiedFramebufferPointer->connectors[i].index ? fieldModifiedCount + 1 : fieldModifiedCount);
				fieldModifiedCount = (originalFramebufferPointer->connectors[i].busID != modifiedFramebufferPointer->connectors[i].busID ? fieldModifiedCount + 1 : fieldModifiedCount);
				fieldModifiedCount = (originalFramebufferPointer->connectors[i].pipe != modifiedFramebufferPointer->connectors[i].pipe ? fieldModifiedCount + 1 : fieldModifiedCount);
				fieldModifiedCount = (originalFramebufferPointer->connectors[i].type != modifiedFramebufferPointer->connectors[i].type ? fieldModifiedCount + 1 : fieldModifiedCount);
				fieldModifiedCount = (originalFramebufferPointer->connectors[i].flags.value != modifiedFramebufferPointer->connectors[i].flags.value ? fieldModifiedCount + 1 : fieldModifiedCount);
				
				if (fieldModifiedCount > 0)
				{
					totalFieldModifiedCount[connectorModifiedIndex] += fieldModifiedCount;
					totalConnectorModifiedCount[connectorModifiedIndex]++;
				}
				else
				{
					totalFieldModifiedCount[i] = 0;
					totalConnectorModifiedCount[i] = 0;
					connectorModifiedIndex = i + 1;
				}
			}
			
			for (int i = 0; i < arrsize(originalFramebufferPointer->connectors); i++)
			{
				//NSLog(@"[%d] totalConnectorModifiedCount: %d totalFieldModifiedCount: %d", i, totalConnectorModifiedCount[i], totalFieldModifiedCount[i]);
				
				if (totalConnectorModifiedCount[i] > 0)
				{
					[gpuDictionary setObject:getNSDataUInt32(1) forKey:[NSString stringWithFormat:@"framebuffer-con%d-enable", i]];
					[gpuDictionary setObject:[NSData dataWithBytes:&modifiedFramebufferPointer->connectors[i] length:totalConnectorModifiedCount[i] * sizeof(modifiedFramebufferPointer->connectors[i])] forKey:[NSString stringWithFormat:@"framebuffer-con%d-alldata", i]];
					
					i += totalConnectorModifiedCount[i] - 1;
				}
			}
		}
		else
		{
			for (int i = 0; i < arrsize(originalFramebufferPointer->connectors); i++)
			{
				bool indexHasModified = (originalFramebufferPointer->connectors[i].index != modifiedFramebufferPointer->connectors[i].index);
				bool busIDHasModified = (originalFramebufferPointer->connectors[i].busID != modifiedFramebufferPointer->connectors[i].busID);
				bool pipeHasModified = (originalFramebufferPointer->connectors[i].pipe != modifiedFramebufferPointer->connectors[i].pipe);
				bool typeHasModified = (originalFramebufferPointer->connectors[i].type != modifiedFramebufferPointer->connectors[i].type);
				bool flagsHasModified = (originalFramebufferPointer->connectors[i].flags.value != modifiedFramebufferPointer->connectors[i].flags.value);
				
				if (!settings.AutoDetectChanges || indexHasModified || busIDHasModified || pipeHasModified || typeHasModified || flagsHasModified)
				{
					[gpuDictionary setObject:getNSDataUInt32(1) forKey:[NSString stringWithFormat:@"framebuffer-con%d-enable", i]];
					
					if (!settings.AutoDetectChanges || indexHasModified)
						[gpuDictionary setObject:getNSDataUInt32(modifiedFramebufferPointer->connectors[i].index) forKey:[NSString stringWithFormat:@"framebuffer-con%d-index", i]];
					
					if (!settings.AutoDetectChanges || busIDHasModified)
						[gpuDictionary setObject:getNSDataUInt32(modifiedFramebufferPointer->connectors[i].busID) forKey:[NSString stringWithFormat:@"framebuffer-con%d-busid", i]];
					
					if (!settings.AutoDetectChanges || pipeHasModified)
						[gpuDictionary setObject:getNSDataUInt32(modifiedFramebufferPointer->connectors[i].pipe) forKey:[NSString stringWithFormat:@"framebuffer-con%d-pipe", i]];
					
					if (!settings.AutoDetectChanges || typeHasModified)
						[gpuDictionary setObject:getNSDataUInt32(modifiedFramebufferPointer->connectors[i].type) forKey:[NSString stringWithFormat:@"framebuffer-con%d-type", i]];
					
					if (!settings.AutoDetectChanges || flagsHasModified)
						[gpuDictionary setObject:getNSDataUInt32(modifiedFramebufferPointer->connectors[i].flags.value) forKey:[NSString stringWithFormat:@"framebuffer-con%d-flags", i]];
				}
			}
		}
	}
	
	getIGPU_LSPCONProperties<T>(appDelegate, gpuDictionary);
}

template <typename T>
void addFramebufferToList(AppDelegate *appDelegate, T &framebuffer)
{
	[appDelegate addToList:appDelegate.framebufferInfoArray name:@"FramebufferID" value:[NSString stringWithFormat:@"0x%08X", framebuffer.framebufferID]];
	[appDelegate addToList:appDelegate.framebufferInfoArray name:@"ModelNameAddr" value:[NSString stringWithFormat:@"0x%016llX", framebuffer.fModelNameAddr]];
	[appDelegate addToList:appDelegate.framebufferInfoArray name:@"Mobile" value:[NSString stringWithFormat:framebuffer.fMobile ? @"Yes" : @"No"]];
	[appDelegate addToList:appDelegate.framebufferInfoArray name:@"PipeCount" value:[NSString stringWithFormat:@"%d", framebuffer.fPipeCount]];
	[appDelegate addToList:appDelegate.framebufferInfoArray name:@"PortCount" value:[NSString stringWithFormat:@"%d", framebuffer.fPortCount]];
	[appDelegate addToList:appDelegate.framebufferInfoArray name:@"FBMemoryCount" value:[NSString stringWithFormat:@"%d", framebuffer.fFBMemoryCount]];
	[appDelegate addToList:appDelegate.framebufferInfoArray name:@"StolenMemorySize" value:bytesToPrintable(framebuffer.fStolenMemorySize)];
	[appDelegate addToList:appDelegate.framebufferInfoArray name:@"FramebufferMemorySize" value:bytesToPrintable(framebuffer.fFramebufferMemorySize)];
	[appDelegate addToList:appDelegate.framebufferInfoArray name:@"UnifiedMemorySize" value:bytesToPrintable(framebuffer.fUnifiedMemorySize)];
	[appDelegate addToList:appDelegate.framebufferInfoArray name:@"Flags" value:[NSString stringWithFormat:@"0x%08X", framebuffer.flags.value]];
	if constexpr (!std::is_same_v<T, FramebufferICLLP> && !std::is_same_v<T, FramebufferICLHP>)
	{
		[appDelegate addToList:appDelegate.framebufferInfoArray name:@"BTTableOffsetIndexSlice" value:[NSString stringWithFormat:@"0x%02X", framebuffer.fBTTableOffsetIndexSlice]];
		[appDelegate addToList:appDelegate.framebufferInfoArray name:@"BTTableOffsetIndexNormal" value:[NSString stringWithFormat:@"0x%02X", framebuffer.fBTTableOffsetIndexNormal]];
		[appDelegate addToList:appDelegate.framebufferInfoArray name:@"BTTableOffsetIndexHDMI" value:[NSString stringWithFormat:@"0x%02X", framebuffer.fBTTableOffsetIndexHDMI]];
	}
	[appDelegate addToList:appDelegate.framebufferInfoArray name:@"CamelliaVersion" value:camilliaVersionToString((CamelliaVersion)framebuffer.camelliaVersion)];
	[appDelegate addToList:appDelegate.framebufferInfoArray name:@"NumTransactionsThreshold" value:[NSString stringWithFormat:@"%d", framebuffer.fNumTransactionsThreshold]];
	[appDelegate addToList:appDelegate.framebufferInfoArray name:@"VideoTurboFreq" value:[NSString stringWithFormat:@"%d", framebuffer.fVideoTurboFreq]];
	if constexpr (!std::is_same_v<T, FramebufferICLLP> && !std::is_same_v<T, FramebufferICLHP>)
	{
		[appDelegate addToList:appDelegate.framebufferInfoArray name:@"BTTArraySliceAddr" value:[NSString stringWithFormat:@"0x%016llX", framebuffer.fBTTArraySliceAddr]];
		[appDelegate addToList:appDelegate.framebufferInfoArray name:@"BTTArrayNormalAddr" value:[NSString stringWithFormat:@"0x%016llX", framebuffer.fBTTArrayNormalAddr]];
		[appDelegate addToList:appDelegate.framebufferInfoArray name:@"BTTArrayHDMIAddr" value:[NSString stringWithFormat:@"0x%016llX", framebuffer.fBTTArrayHDMIAddr]];
	}
	[appDelegate addToList:appDelegate.framebufferInfoArray name:@"SliceCount" value:[NSString stringWithFormat:@"%d", framebuffer.fSliceCount]];
	[appDelegate addToList:appDelegate.framebufferInfoArray name:@"EuCount" value:[NSString stringWithFormat:@"%d", framebuffer.fEuCount]];
}

template <typename T>
void outputPlatformInformationList(AppDelegate *appDelegate, FILE *file, T *platformInformationList)
{
	uint32_t maxStolenMem = 0, totalStolenMem = 0, totalCursorMem = 0, maxOverallMem = 0;
	uint32_t deviceID = 0;
	const char *gpuName = nil, *modelNames = nil;
	
	if constexpr (std::is_same_v<T, FramebufferSNB>)
	{
		for (int i = 0; i < appDelegate.framebufferCount; i++)
		{
			if (g_fbSandyBridge[i] == 0xFFFFFFFF)
				continue;
			
			fprintf(file, "0x%08X (%s, %d connectors, no fbmem)\n", g_fbSandyBridge[i],  platformInformationList[i].fMobile ? "mobile" : "desktop", platformInformationList[i].fPortCount);
		}
	}
	else
	{
		for (int i = 0; i < appDelegate.framebufferCount; i++)
			fprintf(file, "0x%08X (%s, %d connectors%s)\n", platformInformationList[i].framebufferID,  platformInformationList[i].fMobile ? "mobile" : "desktop", platformInformationList[i].fPortCount, platformInformationList[i].fFramebufferMemorySize == 0 ? ", no fbmem" : "");
	}
	
	for (int i = 0; i < appDelegate.framebufferCount; i++)
	{
		if constexpr (std::is_same_v<T, FramebufferSNB>)
		{
			if (g_fbSandyBridge[i] == 0xFFFFFFFF)
				continue;
			
			maxStolenMem = 0 * platformInformationList[i].fFBMemoryCount;
			totalStolenMem = 0; // the assert here does not multiply, why?
			totalCursorMem = platformInformationList[i].fPipeCount * 0x80000; // 32 KB
			maxOverallMem = totalCursorMem + maxStolenMem + platformInformationList[i].fPortCount * 0x1000; // 1 KB
			modelNames = [[appDelegate getModelString:g_fbSandyBridge[i]] UTF8String];
			
			fprintf(file, "\n");
			fprintf(file, "ID: %08X\n", g_fbSandyBridge[i]);
			fprintf(file, "TOTAL STOLEN: %s, TOTAL CURSOR: %s, MAX STOLEN: %s, MAX OVERALL: %s\n", [bytesToPrintable(totalStolenMem) UTF8String], [bytesToPrintable(totalCursorMem) UTF8String], [bytesToPrintable(maxStolenMem) UTF8String], [bytesToPrintable(maxOverallMem) UTF8String]);
			fprintf(file, "GPU Name: Intel HD Graphics 3000\n");
			fprintf(file, "Model Name(s): %s\n", modelNames);
			fprintf(file, "Freq: %d Hz, FreqMax: %d Hz\n", platformInformationList[i].fBacklightFrequency, platformInformationList[i].fBacklightMax);
			fprintf(file, "Mobile: %d, PipeCount: %d, PortCount: %d, FBMemoryCount: %d\n", platformInformationList[i].fMobile, platformInformationList[i].fPipeCount, platformInformationList[i].fPortCount, platformInformationList[i].fFBMemoryCount);
		}
		else if constexpr (std::is_same_v<T, FramebufferIVB>)
		{
			maxStolenMem = platformInformationList[i].fFramebufferMemorySize * platformInformationList[i].fFBMemoryCount;
			totalStolenMem = platformInformationList[i].fFramebufferMemorySize; // the assert here does not multiply, why?
			totalCursorMem = platformInformationList[i].fPipeCount * 0x80000; // 32 KB
			maxOverallMem = totalCursorMem + maxStolenMem + platformInformationList[i].fPortCount * 0x1000; // 1 KB
			deviceID = [appDelegate getGPUDeviceID:platformInformationList[i].framebufferID];
			gpuName = [[appDelegate getGPUString:platformInformationList[i].framebufferID] UTF8String];
			modelNames = [[appDelegate getModelString:platformInformationList[i].framebufferID] UTF8String];
			
			fprintf(file, "\n");
			fprintf(file, "ID: %08X, STOLEN: %s, FBMEM: %s, VRAM: %s\n", platformInformationList[i].framebufferID, [bytesToPrintable(platformInformationList[i].fStolenMemorySize) UTF8String], [bytesToPrintable(platformInformationList[i].fFramebufferMemorySize) UTF8String], [bytesToPrintable(platformInformationList[i].fUnifiedMemorySize) UTF8String]);
			fprintf(file, "TOTAL STOLEN: %s, TOTAL CURSOR: %s, MAX STOLEN: %s, MAX OVERALL: %s\n", [bytesToPrintable(totalStolenMem) UTF8String], [bytesToPrintable(totalCursorMem) UTF8String], [bytesToPrintable(maxStolenMem) UTF8String], [bytesToPrintable(maxOverallMem) UTF8String]);
			if (deviceID != 0)
				fprintf(file, "GPU Name: %s (0x%08X)\n", gpuName, deviceID);
			fprintf(file, "Model Name(s): %s\n", modelNames);
			fprintf(file, "Freq: %d Hz, FreqMax: %d Hz\n", platformInformationList[i].fBacklightFrequency, platformInformationList[i].fBacklightMax);
			fprintf(file, "Mobile: %d, PipeCount: %d, PortCount: %d, FBMemoryCount: %d\n", platformInformationList[i].fMobile, platformInformationList[i].fPipeCount, platformInformationList[i].fPortCount, platformInformationList[i].fFBMemoryCount);
		}
		else if constexpr (std::is_same_v<T, FramebufferHSW>)
		{
			maxStolenMem = platformInformationList[i].fStolenMemorySize * platformInformationList[i].fFBMemoryCount + platformInformationList[i].fFramebufferMemorySize + 0x100000; // 1 MB
			totalStolenMem = calculateStolenHaswell(platformInformationList[i].flags, platformInformationList[i].fStolenMemorySize, platformInformationList[i].fFBMemoryCount, platformInformationList[i].fFramebufferMemorySize);
			totalCursorMem = platformInformationList[i].fPipeCount * 0x80000; // 32 KB
			maxOverallMem = totalCursorMem + maxStolenMem + platformInformationList[i].fPortCount * 0x1000; // 1 KB
			deviceID = [appDelegate getGPUDeviceID:platformInformationList[i].framebufferID];
			gpuName = [[appDelegate getGPUString:platformInformationList[i].framebufferID] UTF8String];
			modelNames = [[appDelegate getModelString:platformInformationList[i].framebufferID] UTF8String];
			
			fprintf(file, "\n");
			fprintf(file, "ID: %08X, STOLEN: %s, FBMEM: %s, VRAM: %s, Flags: 0x%08X\n", platformInformationList[i].framebufferID, [bytesToPrintable(platformInformationList[i].fStolenMemorySize) UTF8String], [bytesToPrintable(platformInformationList[i].fFramebufferMemorySize) UTF8String], [bytesToPrintable(platformInformationList[i].fUnifiedMemorySize) UTF8String], platformInformationList[i].flags.value);
			fprintf(file, "TOTAL STOLEN: %s, TOTAL CURSOR: %s, MAX STOLEN: %s, MAX OVERALL: %s\n", [bytesToPrintable(totalStolenMem) UTF8String], [bytesToPrintable(totalCursorMem) UTF8String], [bytesToPrintable(maxStolenMem) UTF8String], [bytesToPrintable(maxOverallMem) UTF8String]);
			if (deviceID != 0)
				fprintf(file, "GPU Name: %s (0x%08X)\n", gpuName, deviceID);
			fprintf(file, "Model Name(s): %s\n", modelNames);
			fprintf(file, "Camellia: %s, Freq: %d Hz, FreqMax: %d Hz\n", [camilliaVersionToString((CamelliaVersion)platformInformationList[i].camelliaVersion) UTF8String], platformInformationList[i].fBacklightFrequency, platformInformationList[i].fBacklightMax);
			fprintf(file, "Mobile: %d, PipeCount: %d, PortCount: %d, FBMemoryCount: %d\n", platformInformationList[i].fMobile, platformInformationList[i].fPipeCount, platformInformationList[i].fPortCount, platformInformationList[i].fFBMemoryCount);
		}
		else
		{
			maxStolenMem = platformInformationList[i].fStolenMemorySize * platformInformationList[i].fFBMemoryCount + platformInformationList[i].fFramebufferMemorySize + 0x100000; // 1 MB
			totalStolenMem = calculateStolenSkylake(platformInformationList[i].flags, platformInformationList[i].fStolenMemorySize, platformInformationList[i].fFBMemoryCount, platformInformationList[i].fFramebufferMemorySize);
			totalCursorMem = platformInformationList[i].fPipeCount * 0x80000; // 32 KB
			maxOverallMem = totalCursorMem + maxStolenMem + platformInformationList[i].fPortCount * 0x1000; // 1 KB
			deviceID = [appDelegate getGPUDeviceID:platformInformationList[i].framebufferID];
			gpuName = [[appDelegate getGPUString:platformInformationList[i].framebufferID] UTF8String];
			modelNames = [[appDelegate getModelString:platformInformationList[i].framebufferID] UTF8String];
			
			fprintf(file, "\n");
			fprintf(file, "ID: %08X, STOLEN: %s, FBMEM: %s, VRAM: %s, Flags: 0x%08X\n", platformInformationList[i].framebufferID, [bytesToPrintable(platformInformationList[i].fStolenMemorySize) UTF8String], [bytesToPrintable(platformInformationList[i].fFramebufferMemorySize) UTF8String], [bytesToPrintable(platformInformationList[i].fUnifiedMemorySize) UTF8String], platformInformationList[i].flags.value);
			fprintf(file, "TOTAL STOLEN: %s, TOTAL CURSOR: %s, MAX STOLEN: %s, MAX OVERALL: %s\n", [bytesToPrintable(totalStolenMem) UTF8String], [bytesToPrintable(totalCursorMem) UTF8String], [bytesToPrintable(maxStolenMem) UTF8String], [bytesToPrintable(maxOverallMem) UTF8String]);
			if (deviceID != 0)
				fprintf(file, "GPU Name: %s (0x%08X)\n", gpuName, deviceID);
			fprintf(file, "Model Name(s): %s\n", modelNames);
			fprintf(file, "Camellia: %s\n", [camilliaVersionToString((CamelliaVersion)platformInformationList[i].camelliaVersion) UTF8String]);
			fprintf(file, "Mobile: %d, PipeCount: %d, PortCount: %d, FBMemoryCount: %d\n", platformInformationList[i].fMobile, platformInformationList[i].fPipeCount, platformInformationList[i].fPortCount, platformInformationList[i].fFBMemoryCount);
		}
		
		if constexpr (std::is_same_v<T, FramebufferICLLP> || std::is_same_v<T, FramebufferICLHP>)
		{
			for (int j = 0; j < platformInformationList[i].fPortCount; j++)
			{
				ConnectorInfoICL &connectorInfo = platformInformationList[i].connectors[j];
				fprintf(file, "[%d] busID: 0x%02X, pipe: %d, type: 0x%08X, flags: 0x%08X - %s\n", connectorInfo.index, connectorInfo.busID, connectorInfo.pipe, connectorInfo.type, connectorInfo.flags.value, [connectorTypeToString(connectorInfo.type) UTF8String]);
			}
			
			for (int j = 0; j < platformInformationList[i].fPortCount; j++)
			{
				ConnectorInfoICL &connectorInfo = platformInformationList[i].connectors[j];
				fprintf(file, "%s\n", wideConnectorToHex(connectorInfo).c_str());
			}
		}
		else
		{
			for (int j = 0; j < platformInformationList[i].fPortCount; j++)
			{
				ConnectorInfo &connectorInfo = platformInformationList[i].connectors[j];
				fprintf(file, "[%d] busID: 0x%02X, pipe: %d, type: 0x%08X, flags: 0x%08X - %s\n", connectorInfo.index, connectorInfo.busID, connectorInfo.pipe, connectorInfo.type, connectorInfo.flags.value, [connectorTypeToString(connectorInfo.type) UTF8String]);
			}
			
			for (int j = 0; j < platformInformationList[i].fPortCount; j++)
			{
				ConnectorInfo &connectorInfo = platformInformationList[i].connectors[j];
				fprintf(file, "%s\n", connectorToHex(connectorInfo).c_str());
			}
		}
	}
}

#endif /* FBUtilities_hpp */
