//
//  FixEDID.h
//  Hackintool
//
//  Created by Andy Vandijck on 6/24/13.
//  Modified by Ben Baker.
//  Copyright © 2019 Andy Vandijck. All rights reserved.
//

#ifndef FixEDID_h
#define FixEDID_h

#include "AppDelegate.h"
#include "Display.h"
#include <stdio.h>

// https://elixir.bootlin.com/linux/latest/source/include/drm/drm_edid.h

struct EstablishedTimings
{
	uint8_t T1;
	uint8_t T2;
	uint8_t ManufacturingReserved;
} __attribute__((packed));

struct StandardTimings
{
	uint8_t HSize; // Need to multiply by 8 then add 248
	uint8_t VFreqAspect;
} __attribute__((packed));

struct DetailedPixelTiming
{
	uint8_t HActiveLo;
	uint8_t HBlankLo;
	uint8_t HActiveHBlankHi;
	uint8_t VActiveLo;
	uint8_t VBlankLo;
	uint8_t VActiveVBlankHi;
	uint8_t HSyncOffsetLo;
	uint8_t HSyncPulseWidthLo;
	uint8_t VSyncOffsetPulseWidthLo;
	uint8_t HSyncVSyncOffsetPulseWidthHi;
	uint8_t WidthMMLo;
	uint8_t HeightMMLo;
	uint8_t WidthHeightMMHi;
	uint8_t HBorder;
	uint8_t VBorder;
	uint8_t Misc;
} __attribute__((packed));

// If it's not pixel timing, it'll be one of the below
struct DetailedDataString
{
	uint8_t String[13];
} __attribute__((packed));

struct DetailedDataMonitorRange
{
	uint8_t MinVFreq;
	uint8_t MaxVFreq;
	uint8_t MinHFreqKHZ;
	uint8_t MaxHFreqKHZ;
	uint8_t PixelClockMHZ; // Need to multiply by 10
	uint8_t Flags;
	union
	{
		struct
		{
			uint8_t Reserved;
			uint8_t HFreqStartKHZ; // Need to multiply by 2
			uint8_t C; // Need to divide by 2
			uint16_t M;
			uint8_t K;
			uint8_t J; // Need to divide by 2
		} __attribute__((packed)) GTF2;
		struct
		{
			uint8_t Version;
			uint8_t Data1; // High 6 bits: extra clock resolution
			uint8_t Data2; // Plus low 2 of above: max hactive
			uint8_t SupportedAspects;
			uint8_t Flags; // Preferred aspect and blanking support
			uint8_t SupportedScalings;
			uint8_t PreferredRefresh;
		} __attribute__((packed)) CVT;
	} Forumula;
} __attribute__((packed));

struct DetailedDataWPIndex
{
	uint8_t WhiteYZLo; // Lower 2 bits each
	uint8_t WhiteXHi;
	uint8_t WhiteYHi;
	uint8_t Gamma; // Need to divide by 100 then add 1
} __attribute__((packed));

struct DetailedDataColorPoint
{
	uint8_t WIndex1;
	uint8_t WPIndex1[3];
	uint8_t WIndex2;
	uint8_t WPIndex2[3];
} __attribute__((packed));

struct CVTTiming
{
	uint8_t Code[3];
} __attribute__((packed));

struct DetailedNonPixel
{
	uint8_t Padding1;
	uint8_t Type; /* FF=Serial, FE=String, FD=Monitor Range, FC=Monitor Name
			  FB=Color Point Data, FA=Standard Timing Data,
			  F9=Undefined, F8=Manufacturing Reserved */
	uint8_t Padding2;
	union
	{
		DetailedDataString String;
		DetailedDataMonitorRange Range;
		DetailedDataWPIndex Color;
		StandardTimings Timings[6];
		CVTTiming CVT[4];
	} Data;
} __attribute__((packed));

struct DetailedTiming
{
	uint16_t PixelClock; // Need to multiply by 10 KHz
	union
	{
		DetailedPixelTiming PixelData;
		DetailedNonPixel OtherData;
	} Data;
} __attribute__((packed));

struct EDID
{
	uint8_t Header[8];
	struct
	{
		uint8_t VendorID[2];
		uint8_t ProductID[2];
		uint32_t Serial;
		uint8_t ManufacturingWeek;
		uint8_t ManufacturingYear;
	} __attribute__((packed)) SerialInfo;
	struct
	{
		uint8_t Version;
		uint8_t Revision;
	} __attribute__((packed)) VersionInfo;
	struct
	{
		uint8_t Input;
		uint8_t WidthCM;
		uint8_t HeightCM;
		uint8_t Gamma;
		uint8_t Features;
	} __attribute__((packed)) BasicParams;
	struct
	{
		uint8_t RedGreenLo;
		uint8_t BlackWhiteLo;
		uint8_t RedX;
		uint8_t RedY;
		uint8_t GreenX;
		uint8_t GreenY;
		uint8_t BlueX;
		uint8_t BlueY;
		uint8_t WhiteX;
		uint8_t WhiteY;
	} __attribute__((packed)) Chroma;
	EstablishedTimings EstablishedTimings;
	StandardTimings StandardTimings[8];
	DetailedTiming DetailedTimings[4];
	uint8_t Extensions;
	uint8_t Checksum;
} __attribute__((packed));

@interface FixEDID : NSObject
{
}

+ (NSString *)getAspectRatio:(EDID &)edid;
+ (void)getEDIDOrigData:(Display *)display edidOrigData:(NSData **)edidOrigData;
+ (void)getEDIDData:(Display *)display edidOrigData:(NSData **)edidOrigData edidData:(NSData **)edidData;
+ (void)makeEDIDFiles:(Display *)display;
+ (void)createDisplayIcons:(NSArray *)displaysArray;

@end

#endif /* FixEDID_h */
