//
//  NSString+Pin.m
//  PinConfigurator
//
//  Created by Ben Baker on 2/7/19.
//  Copyright © 2019 Ben Baker. All rights reserved.
//

#import "NSString+Pin.h"
#import "AudioNode.h"

@implementation NSString (Pin)

#define GetLocalizedString(key) \
[[NSBundle mainBundle] localizedStringForKey:(key) value:@"" table:nil]

const char *gPinColorArray[] = { "Unknown", "Black", "Gray", "Blue", "Green", "Red", "Orange", "Yellow", "Purple", "Pink", "Reserved1", "Unknown", "Unknown", "Reserved2", "White", "Other" };
const char *gPinMisc[] = { "Jack Detect Override", "Reserved", "Reserved", "Reserved" };
const char *gPinDefaultDeviceArray[] = { "Line Out", "Speaker", "HP Out", "CD", "SPDIF Out", "Digital Other Out", "Modem Line Side", "Modem Handset Side", "Line In", "AUX", "Mic In", "Telephony", "SPDIF In", "Digital Other In", "Reserved", "Other" };
const char *gPinConnector[] = { "Unknown", "1/8\" Stereo/Mono", "1/4\" Stereo/Mono", "ATAPI Internal", "RCA", "Optical", "Other Digital", "Other Analog", "Multichannel Analog", "XLR/Professional", "RJ-11 (Modem)", "Combination", "Unknown", "Unknown", "Unknown", "Other" };
const char *gPinPort[] = { "Jack", "No Connection", "Fixed", "Jack + Internal" };
const char *gPinGeometricLocation[] = { "N/A", "Rear", "Front", "Left", "Right", "Top", "Bottom", "Special", "Special", "Special", "Reserved", "Reserved", "Reserved", "Reserved", "Reserved", "Reserved" };
const char *gPinGrossLocation[] = { "External", "Internal", "Separate", "Other" };
const char *gPinGrossSpecial7[] = { "Rear Panel", "Riser", "Special", "Mobile Lid-Inside" };
const char *gPinGrossSpecial8[] = { "Drive Bay", "Digital Display", "Special", "Mobile Lid-Outside" };
const char *gPinGrossSpecial9[] = { "Special", "ATAPI", "Special", "Special" };
const char *gPinEAPD[] = { "BTL", "EAPD", "L/R Swap" };

+ (NSString *)pinDirection:(uint8_t)value;
{
	NSString *pinDirection = @"--";
	
	if (value <= kHdaConfigDefaultDeviceModemHandset)
		pinDirection = GetLocalizedString(@"Out");
	else if (value > kHdaConfigDefaultDeviceModemHandset && value <= kHdaConfigDefaultDeviceOtherDigitalIn)
		pinDirection = GetLocalizedString(@"In");
	
	return pinDirection;
}

+ (NSString *)pinColor:(uint8_t)value
{
	return GetLocalizedString([NSString stringWithUTF8String:gPinColorArray[value & 0xF]]);
}

+ (NSString *)pinMisc:(uint8_t)value
{
	return GetLocalizedString([NSString stringWithUTF8String:gPinMisc[value & 0x3]]);
}

+ (NSString *)pinDefaultDevice:(uint8_t)value
{
	return GetLocalizedString([NSString stringWithUTF8String:gPinDefaultDeviceArray[value & 0xF]]);
}

+ (NSString *)pinConnector:(uint8_t)value
{
	return GetLocalizedString([NSString stringWithUTF8String:gPinConnector[value & 0xF]]);
}

+ (NSString *)pinPort:(uint8_t)value
{
	return GetLocalizedString([NSString stringWithUTF8String:gPinPort[value & 0x3]]);
}

+ (NSString *)pinGrossLocation:(uint8_t)value;
{
	return GetLocalizedString([NSString stringWithUTF8String:gPinGrossLocation[value]]);
}

+ (NSString *)pinLocation:(uint8_t)grossLocation geometricLocation:(uint8_t)geometricLocation;
{
	if (geometricLocation == 0x7)
		return GetLocalizedString([NSString stringWithUTF8String:gPinGrossSpecial7[grossLocation]]);
	else if (geometricLocation == 0x8)
		return GetLocalizedString([NSString stringWithUTF8String:gPinGrossSpecial8[grossLocation]]);
	else if (geometricLocation == 0x9)
		return GetLocalizedString([NSString stringWithUTF8String:gPinGrossSpecial9[grossLocation]]);

	return GetLocalizedString([NSString stringWithUTF8String:gPinGeometricLocation[geometricLocation]]);
}

+ (NSString *)pinEAPD:(uint8_t)value;
{
	return GetLocalizedString([NSString stringWithUTF8String:gPinEAPD[value & 0x7]]);
}

+ (NSString *)pinConfigDescription:(uint8_t *)value
{
	if (!value || strlen((const char *)value) != 8)
		return @"Invalid pin config";
	
	uint8_t cad = value[0] - 48;
	const char *name = (const char *)&value[2];
	uint8_t command = value[5];
	uint8_t port = strtol((const char *)&value[6], 0, 16);
	uint8_t connector = strtol((const char *)&value[7], 0, 16);
	uint8_t grossLocation = (connector >> 4);
	uint8_t geometricLocation = (connector & 0xF);
	NSString *configDescription = 0;
	uint32_t hid = (uint32_t)strtol(name, 0, 16);
	
	switch (command)
	{
		case 0x43:
		case 0x63:
			configDescription = [NSString stringWithFormat:@" command: %c \n\t   group: %c \n\t   index: %c", command, value[6], value[7]];
			break;
		case 0x44:
		case 0x64:
			configDescription = [NSString stringWithFormat:@" command: %c \n\t   color: %@ (%c) \n\t    misc: %c", command, [NSString pinColor:port], value[6], value[7]];
			break;
		case 0x45:
		case 0x65:
			configDescription = [NSString stringWithFormat:@" command: %c \n\t  device: %@ (%c)\n\t    conn: %@ (%c)", command, [NSString pinDefaultDevice:port], value[6], [NSString pinConnector:connector], value[7]];
			break;
		case 0x46:
		case 0x66:
			configDescription = [NSString stringWithFormat:@" command: %c \n\t    port: %@ (%c) \n\tlocation: %@ (%c)", command, [NSString pinPort:port], value[6], [NSString pinLocation:grossLocation geometricLocation:geometricLocation], value[7]];
			break;
		default:
			break;
	}
	
	return [NSString stringWithFormat:@"{\n\t     cad: %d \n\t     hid: %d (%s)\n\t%@\n}", cad, hid, name, configDescription];
}

+ (NSString *)pinDefaultDescription:(uint8_t *)value
{
	return @"";
}

@end
