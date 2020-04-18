/**
 *   010 Editor v8.0.1 Binary Template
 *
 *      File: Intel Framebuffer kexts from 10.13.3
 *   Authors: vit9696
 *   Version: 0.5
 *   Purpose: Intel Framebuffer decoding
 *
 * Copyright (c) 2018 vit9696
 *
 * Thanks to bcc9, Piker-Alpha, joevt and all the others who reversed Intel Framebuffer code.
 */

#include "IntelFramebuffer.h"
#include <stdio.h>
#include <sys/stat.h>
#include <iostream>
#include <fstream>
#include <vector>
#include <stdint.h>
#include <assert.h>
#include <string>
#include <iostream>
#include <algorithm>
#include <stdarg.h>
#include <memory>

using namespace std;

#define KEXT_OFFSET		0x20000

#define GetLocalizedString(key) \
[[NSBundle mainBundle] localizedStringForKey:(key) value:@"" table:nil]

NSArray *g_framebufferArray = @[@"FramebufferID", @"ModelNameAddr", @"Mobile", @"PipeCount", @"PortCount", @"FBMemoryCount", @"StolenMemorySize", @"FramebufferMemorySize", @"CursorMemorySize", @"UnifiedMemorySize", @"BacklightFrequency", @"BacklightMax", @"Flags", @"BTTableOffsetIndexSlice", @"BTTableOffsetIndexNormal", @"BTTableOffsetIndexHDMI", @"CamelliaVersion", @"NumTransactionsThreshold", @"VideoTurboFreq", @"BTTArraySliceAddr", @"BTTArrayNormalAddr", @"BTTArrayHDMIAddr", @"SliceCount", @"EuCount"];
NSArray *g_connectorArray = @[@"Index", @"BusID", @"Pipe", @"Type", @"Flags"];
NSArray *g_connectorTypeArray = @[@"Zero", @"Dummy", @"LVDS", @"DigitalDVI", @"SVID", @"VGA", @"DP", @"HDMI", @"AnalogDVI"];
NSArray *g_camelliaArray = @[@"Disabled", @"V1", @"V2", @"V3", @"Unsupported"];
//NSArray *g_fbNameArray = @[@"Sandy Bridge", @"Ivy Bridge", @"Haswell", @"Broadwell", @"Skylake", @"Kaby Lake", @"Coffee Lake", @"Cannon Lake", @"Ice Lake (LP)", @"Ice Lake (HP)", @"Tiger Lake"];
//NSArray *g_fbShortNameArray = @[@"SNB", @"IVB", @"HSW", @"BDW", @"SKL", @"KBL", @"CFL", @"CNL", @"ICLLP", @"ICLHP", @"TGL"];
NSArray *g_fbNameArray = @[@"Sandy Bridge", @"Ivy Bridge", @"Haswell", @"Broadwell", @"Skylake", @"Kaby Lake", @"Coffee Lake", @"Ice Lake (LP)"];
NSArray *g_fbShortNameArray = @[@"SNB", @"IVB", @"HSW", @"BDW", @"SKL", @"KBL", @"CFL", @"ICLLP"];

const uint32_t g_fbSandyBridge[] = { 0x00010000, 0x00020000, 0x00030010, 0x00030030, 0x00040000, 0xFFFFFFFF, 0xFFFFFFFF, 0x00030020, 0x00050000 };

NSArray *g_framebufferFlagsArray = @[@"FBAvoidFastLinkTraining", @"FBFramebufferCommonMemory", @"FBFramebufferCompression", @"FBEnableSliceFeatures", @"FBDynamicFBCEnable", @"FBUseVideoTurbo", @"FBForcePowerAlwaysConnected", @"FBDisableHighBitrateMode2", @"FBBoostPixelFrequencyLimit", @"FBLimit4KSourceSize", @"FBAlternatePWMIncrement1", @"FBAlternatePWMIncrement2", @"FBDisableFeatureIPS", @"FBUnknownFlag_2000", @"FBAllowConnectorRecover", @"FBUnknownFlag_8000", @"FBUnknownFlag_10000", @"FBUnknownFlag_20000", @"FBDisableGFMPPFM", @"FBUnknownFlag_80000", @"FBUnknownFlag_100000", @"FBEnableDynamicCDCLK", @"FBUnknownFlag_400000", @"FBSupport5KSourceSize"];
NSArray *g_connectorFlagsArray = @[@"CNAlterAppertureRequirements", @"CNUnknownFlag_2", @"CNUnknownFlag_4", @"CNConnectorAlwaysConnected", @"CNUnknownFlag_10", @"CNUnknownFlag_20", @"CNDisableBlitTranslationTable", @"CNUnknownFlag_80", @"CNUnknownFlag_100", @"CNUnknownFlag_200", @"CNUnknownFlag_400", @"CNUnknownFlag_800", @"CNUnknownFlag_1000", @"CNUnknownFlag_2000", @"CNUnknownFlag_4000", @"CNUnknownFlag_8000"];

string stringFormat(const string fmt_str, ...)
{
	int final_n, n = ((int)fmt_str.size()) * 2; /* Reserve two times as much as the length of the fmt_str */
	unique_ptr<char[]> formatted;
	va_list ap;
	while(1)
	{
		formatted.reset(new char[n]); /* Wrap the plain char array into the unique_ptr */
		strcpy(&formatted[0], fmt_str.c_str());
		va_start(ap, fmt_str);
		final_n = vsnprintf(&formatted[0], n, fmt_str.c_str(), ap);
		va_end(ap);
		if (final_n < 0 || final_n >= n)
			n += abs(final_n - n + 1);
		else
			break;
	}
	return string(formatted.get());
}

void outputBuffer(uint32_t *buffer, size_t maxSize)
{
	for (int i=0; i<roundUp((uint32_t)maxSize / 4, 8); i+=8)
	{
		printf("%08X %08X %08X %08X %08X %08X %08X %08X\n", (i < maxSize ? *(buffer) : 0xFFFFFFFF), (i + 4 < maxSize ? *(buffer+1) : 0xFFFFFFFF), (i + 8 < maxSize ? *(buffer+2) : 0xFFFFFFFF), (i + 12 < maxSize ? *(buffer+3) : 0xFFFFFFFF), (i + 16 < maxSize ? *(buffer+4) : 0xFFFFFFFF), (i + 20 < maxSize ? *(buffer+5) : 0xFFFFFFFF), (i + 24 < maxSize ? *(buffer+6) : 0xFFFFFFFF), (i + 28 < maxSize ? *(buffer+7) : 0xFFFFFFFF));
		buffer += 8;
	}
}

uint32_t calculateStolenHaswell(FramebufferFlags &flags, uint32_t fStolenMemorySize, uint32_t fFBMemoryCount, uint32_t fFramebufferMemorySize)
{
	uint32_t fTotalStolen = 0x100000; /* a constant */
	
	if (flags.bits.FBFramebufferCommonMemory) /* formerly FBUnknownFlag_2 */
		fTotalStolen += fStolenMemorySize;
	else
		fTotalStolen += fStolenMemorySize * fFBMemoryCount;
	/* Prior to Skylake fFramebufferMemorySize is taken into account unconditionally */
	
	fTotalStolen += fFramebufferMemorySize;
	
	return fTotalStolen;
}

uint32_t calculateStolenSkylake(FramebufferFlags &flags, uint32_t fStolenMemorySize, uint32_t fFBMemoryCount, uint32_t fFramebufferMemorySize)
{
	uint32_t fTotalStolen = 0x100000; /* a constant */
	
	if (flags.bits.FBFramebufferCommonMemory) /* formerly FBUnknownFlag_2 */
		fTotalStolen += fStolenMemorySize;
	else
		fTotalStolen += fStolenMemorySize * fFBMemoryCount;
	
	if (flags.bits.FBFramebufferCompression)
		fTotalStolen += fFramebufferMemorySize;
	
	return fTotalStolen;
}

NSString *bytesToPrintable(uint32_t bytes)
{
	NSString *out;
	
	if (bytes >= 1024 * 1024)
	{
		if (bytes % (1024 * 1024) == 0)
			out = [NSString stringWithFormat:@"%d MB", bytes / 1024 / 1024];
		else
			out = [NSString stringWithFormat:@"%d MB (%d bytes)", bytes / 1024 / 1024, bytes];
	}
	else if (bytes >= 1024)
	{
		if (bytes % (1024) == 0)
			out = [NSString stringWithFormat:@"%d KB", bytes / 1024];
		else
			out = [NSString stringWithFormat:@"%d KB (%d bytes)", bytes / 1024, bytes];
	}
	else
		out = [NSString stringWithFormat:@"%d bytes", bytes];
	
	return out;
}

NSString *camilliaVersionToString(CamelliaVersion camelliaVersion)
{
	NSArray *fieldArray = @[@(CamelliaDisabled), @(CamelliaV1), @(CamelliaV2), @(CamelliaV3), @(CamelliaUnsupported)];
	NSInteger fieldIndex = [fieldArray indexOfObject:@(camelliaVersion)];
	return GetLocalizedString(g_camelliaArray[fieldIndex]);
}

NSString *connectorTypeToString(ConnectorType connectorType)
{
	NSArray *fieldArray = @[@(ConnectorZero), @(ConnectorDummy), @(ConnectorLVDS), @(ConnectorDigitalDVI), @(ConnectorSVID), @(ConnectorVGA), @(ConnectorDP), @(ConnectorHDMI), @(ConnectorAnalogDVI)];
	NSInteger fieldIndex = [fieldArray indexOfObject:@(connectorType)];
	return GetLocalizedString(g_connectorTypeArray[fieldIndex]);
}

string wideConnectorToPrintable(ConnectorInfoICL &con)
{
	string out;
	out = stringFormat("[%d] busID: 0x%02X, pipe: %d, type: 0x%08X, flags: 0x%08X - %s", con.index, con.busID, con.pipe, con.type, con.flags.value, [connectorTypeToString(con.type) UTF8String]);
	return out;
}

string connectorToHex(ConnectorInfo &c)
{
	string out;
	out = stringFormat("%02X%02X%02X%02X %08X %08X", (uint8_t)c.index, c.busID, c.pipe, c.pad,
			((c.type>>24)&0xff) | ((c.type<<8)&0xff0000) | ((c.type>>8)&0xff00) | ((c.type<<24)&0xff000000),
			((c.flags.value>>24)&0xff) | ((c.flags.value<<8)&0xff0000) | ((c.flags.value>>8)&0xff00) | ((c.flags.value<<24)&0xff000000));
	return out;
}

string wideConnectorToHex(ConnectorInfoICL &c)
{
	string out;
	out = stringFormat("%08X %08X %08X %08X %08X %08X",
			((c.index>>24)&0xff) | ((c.index<<8)&0xff0000) | ((c.index>>8)&0xff00) | ((c.index<<24)&0xff000000),
			((c.busID>>24)&0xff) | ((c.busID<<8)&0xff0000) | ((c.busID>>8)&0xff00) | ((c.busID<<24)&0xff000000),
			((c.pipe>>24)&0xff) | ((c.pipe<<8)&0xff0000) | ((c.pipe>>8)&0xff00) | ((c.pipe<<24)&0xff000000),
			((c.pad>>24)&0xff) | ((c.pad<<8)&0xff0000) | ((c.pad>>8)&0xff00) | ((c.pad<<24)&0xff000000),
			((c.type>>24)&0xff) | ((c.type<<8)&0xff0000) | ((c.type>>8)&0xff00) | ((c.type<<24)&0xff000000),
			((c.flags.value>>24)&0xff) | ((c.flags.value<<8)&0xff0000) | ((c.flags.value>>8)&0xff00) | ((c.flags.value<<24)&0xff000000));
	return out;
}

string frameIDFromIndex(uint32_t frame, uint32_t index)
{
	string out;
	if (frame != 0)
	{
		/* Ivy and newer */
		out = stringFormat("%08X", frame);
	} else
	{
		/* Sandy Bridge has stupid frame detection logic.
		 * See board-id list below, which enable framebuffer fallbacks.
		 */
		switch (index)
		{
			case 0: out="SNB0 0x10000"; break;
			case 1: out="SNB1 0x20000"; break;
			case 2: out="SNB2 0x30010 or 0x30020"; break;
			case 3: out="SNB3 0x30030"; break;
			case 4: out="SNB4 0x40000"; break;
			case 5: out="SNB5 0x50000"; break;
			case 6: out="SNB6 Not addressible"; break;
			case 7: out="SNB7 Not addressible"; break;
				/* There are 8 frames for sandy aside the default one, but only the first 6 are addressible. */
			default: out="Error";
		}
	}
	return out;
}

uint32_t roundUp(uint32_t value, uint32_t factor)
{
	return (value + (factor - 1)) / factor * factor;
}

uint32_t roundDown(uint32_t value, uint32_t factor)
{
	return (value / factor) * factor;
}

uint32_t swapByteOrder(uint32_t value)
{
	return (value >> 24) | ((value << 8) & 0x00FF0000) | ((value >> 8) & 0x0000FF00) | (value << 24);
}

void copyData(uint8_t** dst, uint8_t** src, size_t size)
{
	*dst = new uint8_t[size];
	memcpy(*dst, *src, size);
}

bool findFirst(const uint8_t *buf, size_t offset, const char *text, size_t size)
{
	bool found = false;
	size_t len = strlen(text);
	const uint8_t *pos = buf + offset;
	const uint8_t *end = buf + size - len;
	
	while (pos < end)
	{
		found = (strncmp((char *)pos, text, len) == 0);
		
		if (found)
			break;
		
		pos++;
	}
	
	return found;
}

bool findFirst(const uint8_t *buf, size_t offset, uint32_t value, size_t size)
{
	bool found = false;
	size_t len = sizeof(value);
	const uint8_t *pos = buf + offset;
	const uint8_t *end = buf + size - len;
	
	while (pos < end)
	{
		found = (*((uint32_t *)pos) == value);
		
		if (found)
			break;
		
		pos++;
	}
	
	return found;
}

bool readFramebuffer(const char *fileName, IntelGen &intelGen, uint8_t **originalFramebufferList, uint8_t **modifiedFramebufferList, uint32_t &framebufferSize, uint32_t &framebufferCount)
{
	intelGen = IGUnknown;
	framebufferSize = 0;
	framebufferCount = 0;
	ifstream file(fileName, ios::in | ios::binary);
	
	if (!file)
		return false;
	
	if (!file.is_open())
		return false;
	
	file.seekg(0, std::ios::end);
	size_t bufferSize = file.tellg();
	file.seekg(0, std::ios::beg);
	uint8_t *buffer = new uint8_t[bufferSize];
	file.read(reinterpret_cast<char *>(buffer), bufferSize);
	file.close();

	bool retVal = readFramebuffer(buffer, bufferSize, intelGen, originalFramebufferList, modifiedFramebufferList, framebufferSize, framebufferCount);
	
	delete[] buffer;
	
	return retVal;
}

bool readFramebuffer(const uint8_t *buffer, size_t bufferSize, IntelGen &intelGen, uint8_t **originalFramebufferList, uint8_t **modifiedFramebufferList, uint32_t &framebufferSize, uint32_t &framebufferCount)
{
	intelGen = IGUnknown;
	framebufferSize = 0;
	framebufferCount = 0;

	uint32_t i = 0;
	uint32_t firstID = 0;
	const uint8_t *start = 0;
	const uint8_t *pos = buffer;
	const uint8_t *end = buffer + bufferSize - sizeof(uint32_t);
	
	//uint64_t textSlide = *((uint64_t *)&buf[0x38]);
	bool isLowProfile = FALSE;
	
	while (pos < end)
	{
		/* Skip to platforms... */
		firstID = *((uint32_t *)pos);
		
		if (firstID != FirstSandyBridgeID && firstID != FirstIvyBridgeID &&
			firstID != FirstHaswellID && firstID != FirstBroadwellID &&
			firstID != FirstSkylakeID && firstID != FirstKabyLakeID &&
			firstID != FirstCoffeeLakeID && firstID != FirstCannonLakeID &&
			firstID != FirstIceLakeID)
		{
			pos += sizeof(uint32_t);
			continue;
		}
		
		/* Read platforms from here... */
		while (pos < end && *((uint32_t *)pos) != 0xFFFFFFFF)
		{
			if (firstID == FirstSandyBridgeID)
			{
				if (intelGen == IGUnknown)
				{
					start = pos;
					framebufferSize = sizeof(FramebufferSNB);
				}
				
				intelGen = IGSandyBridge;
				framebufferCount++;
				pos += sizeof(FramebufferSNB);
			}
			else if (firstID == FirstIvyBridgeID)
			{
				if (intelGen == IGUnknown)
				{
					start = pos;
					framebufferSize = sizeof(FramebufferIVB);
				}
				
				intelGen = IGIvyBridge;
				framebufferCount++;
				pos += sizeof(FramebufferIVB);
			}
			else if (firstID == FirstHaswellID)
			{
				if (intelGen == IGUnknown)
				{
					start = pos;
					framebufferSize = sizeof(FramebufferHSW);
				}
				
				intelGen = IGHaswell;
				framebufferCount++;
				pos += sizeof(FramebufferHSW);
			}
			else if (firstID == FirstBroadwellID)
			{
				if (intelGen == IGUnknown)
				{
					start = pos;
					framebufferSize = sizeof(FramebufferBDW);
				}
				
				intelGen = IGBroadwell;
				framebufferCount++;
				pos += sizeof(FramebufferBDW);
			}
			else if (firstID == FirstSkylakeID || firstID == FirstKabyLakeID)
			{
				if (intelGen == IGUnknown)
				{
					start = pos;
					framebufferSize = sizeof(FramebufferSKL);
				}
				
				intelGen = (firstID == FirstSkylakeID ? IGSkylake : IGKabyLake);
				framebufferCount++;
				pos += sizeof(FramebufferSKL);
			}
			else if (firstID == FirstCoffeeLakeID)
			{
				if (intelGen == IGUnknown)
				{
					start = pos;
					framebufferSize = sizeof(FramebufferCFL);
				}
				
				intelGen = IGCoffeeLake;
				framebufferCount++;
				pos += sizeof(FramebufferCFL);
			}
			else if (firstID == FirstCannonLakeID)
			{
				if (intelGen == IGUnknown)
				{
					start = pos;
					framebufferSize = sizeof(FramebufferCNL);
				}
				
				intelGen = IGCannonLake;
				framebufferCount++;
				pos += sizeof(FramebufferCNL);
			}
			else if (firstID == FirstIceLakeID)
			{
				if (intelGen == IGUnknown)
				{
					start = pos;
					//isLowProfile = findFirst(buffer, 0, "ICLLP", bufferSize);
					//isLowProfile = findFirst(buffer, &pos - &buffer, 0x00090325, MIN(PAGE_SIZE, bufferSize));
					isLowProfile = true;
				}
				
				if (isLowProfile)
				{
					intelGen = IGIceLakeLP;
					framebufferSize = sizeof(FramebufferICLLP);
					framebufferCount++;
					pos += sizeof(FramebufferICLLP);
				}
				else
				{
					intelGen = IGIceLakeHP;
					framebufferSize = sizeof(FramebufferICLHP);
					framebufferCount++;
					pos += sizeof(FramebufferICLHP);
				}
			}
			
			/* There is no -1 termination on Sandy */
			if (firstID == FirstSandyBridgeID && i == 7)
				break;
			
			i++;
		}
		
		break;
	}
	
	*originalFramebufferList = new uint8_t[framebufferSize * framebufferCount];
	*modifiedFramebufferList = new uint8_t[framebufferSize * framebufferCount];
	
	memcpy(*originalFramebufferList, start, framebufferSize * framebufferCount);
	memcpy(*modifiedFramebufferList, start, framebufferSize * framebufferCount);
	
	return true;
}
