//
//  AudioNode.h
//  PinConfigurator
//
//  Created by Ben Baker on 2/7/19.
//  Copyright © 2019 Ben Baker. All rights reserved.
//

#ifndef AudioNode_h
#define AudioNode_h

#import <Cocoa/Cocoa.h>

#define LONIBBLE(n) ((char)(n) & 0xF)
#define HINIBBLE(n) ((char)(((char)(n) >> 4) & 0xF))

#define HDA_EAPD_BTL_ENABLE_EAPD        0x00000002

enum
{
	kHdaPinCapabilitiesImpendance	= (1 << 0),
	kHdaPinCapabilitiesTrigger		= (1 << 1),
	kHdaPinCapabilitiesPresense		= (1 << 2),
	kHdaPinCapabilitiesHeadphone	= (1 << 3),
	kHdaPinCapabilitiesOutput		= (1 << 4),
	kHdaPinCapabilitiesInput		= (1 << 5),
	kHdaPinCapabilitiesBalanced		= (1 << 6),
	kHdaPinCapabilitiesHDMI			= (1 << 7),
	kHdaPinCapabilitiesEAPD			= (1 << 16),
	kHdaPinCapabilitiesDisplayPort	= (1 << 24),
	kHdaPinCapabilitiesHBR 			= (1 << 27)
};

enum
{
	kHdaConfigDefaultConnUnknown		= 0x0,
	kHdaConfigDefaultConn18Stereo		= 0x1,
	kHdaConfigDefaultConn14Stereo		= 0x2,
	kHdaConfigDefaultConnATAPI			= 0x3,
	kHdaConfigDefaultConnRCA			= 0x4,
	kHdaConfigDefaultConnOptical		= 0x5,
	kHdaConfigDefaultConnDigitalOther	= 0x6,
	kHdaConfigDefaultConnAnalogOther	= 0x7,
	kHdaConfigDefaultConnMultiAnalog	= 0x8,
	kHdaConfigDefaultConnXLR			= 0x9,
	kHdaConfigDefaultConnRJ11			= 0xA,
	kHdaConfigDefaultConnCombo			= 0xB,
	kHdaConfigDefaultConnOther			= 0xF,
};

enum
{
	kHdaConfigDefaultDeviceLineOut			= 0x0,
	kHdaConfigDefaultDeviceSpeaker			= 0x1,
	kHdaConfigDefaultDeviceHeadphoneOut		= 0x2,
	kHdaConfigDefaultDeviceCD				= 0x3,
	kHdaConfigDefaultDeviceSPDIFOut			= 0x4,
	kHdaConfigDefaultDeviceOtherDigitalOut	= 0x5,
	kHdaConfigDefaultDeviceModemLine		= 0x6,
	kHdaConfigDefaultDeviceModemHandset		= 0x7,
	kHdaConfigDefaultDeviceLineIn			= 0x8,
	kHdaConfigDefaultDeviceAux				= 0x9,
	kHdaConfigDefaultDeviceMicIn			= 0xA,
	kHdaConfigDefaultDeviceTelephony		= 0xB,
	kHdaConfigDefaultDeviceSPDIFIn			= 0xC,
	kHdaConfigDefaultDeviceOtherDigitalIn	= 0xD,
	kHdaConfigDefaultDeviceOther			= 0xF,
};

enum
{
	kHdaConfigDefaultLocSpecNA				= 0x0,
	kHdaConfigDefaultLocSpecRear			= 0x1,
	kHdaConfigDefaultLocSpecFront			= 0x2,
	kHdaConfigDefaultLocSpecLeft			= 0x3,
	kHdaConfigDefaultLocSpecRight			= 0x4,
	kHdaConfigDefaultLocSpecTop				= 0x5,
	kHdaConfigDefaultLocSpecBottom			= 0x6,
	kHdaConfigDefaultLocSpecSpecial7		= 0x7,
	kHdaConfigDefaultLocSpecSpecial8		= 0x8,
	kHdaConfigDefaultLocSpecSpecial9		= 0x9,
	
};

enum
{
	kHdaConfigDefaultLocSurfExternal			= 0x0,
	kHdaConfigDefaultLocSurfRearPanel			= 0x0,
	kHdaConfigDefaultLocSurfDriveBay			= 0x0,
	kHdaConfigDefaultLocSurfInternal			= 0x1,
	kHdaConfigDefaultLocSurfRiser				= 0x1,
	kHdaConfigDefaultLocSurfDigitalDisplay		= 0x1,
	kHdaConfigDefaultLocSurfATAPI				= 0x1,
	kHdaConfigDefaultLocSurfSeparate			= 0x2,
	kHdaConfigDefaultLocSurfSpecial				= 0x2,
	kHdaConfigDefaultLocSurfOther				= 0x3,
	kHdaConfigDefaultLocSurfMobileLidInside		= 0x3,
	kHdaConfigDefaultLocSurfMobileLidOutside	= 0x3,
};

enum
{
	kHdaConfigDefaultPortConnJack			= 0x0,
	kHdaConfigDefaultPortConnNone			= 0x1,
	kHdaConfigDefaultPortConnFixedDevice	= 0x2,
	kHdaConfigDefaultPortConnIntJack		= 0x3,
};

enum
{
	kHdaWidgetTypeOutput		= 0x0,
	kHdaWidgetTypeInput			= 0x1,
	kHdaWidgetTypeMixer			= 0x2,
	kHdaWidgetTypeSelector		= 0x3,
	kHdaWidgetTypePinComplex	= 0x4,
	kHdaWidgetTypePower			= 0x5,
	kHdaWidgetTypeVolumeKnob	= 0x6,
	kHdaWidgetTypeBeepGen		= 0x7,
	kHdaWidgetTypeVendor		= 0xF,
};

@interface AudioNode : NSObject<NSCopying>
{
}

- (id)initWithNid:(uint8_t)nid;
- (id)initWithNid:(uint8_t)nid pinDefault:(uint32_t)pinDefault;
- (void) setDefaults:(uint8_t)nid;
- (void) dealloc;
- (NSString *) description;
- (uint32_t) pinDefault;
- (NSString *) pinDefaultString;
- (uint32_t) verb70C:(uint8_t)address;
- (uint32_t) verb71C:(uint8_t)address;
- (uint32_t) verb71D:(uint8_t)address;
- (uint32_t) verb71E:(uint8_t)address;
- (uint32_t) verb71F:(uint8_t)address;
- (NSString *) wakeConfigString:(uint8_t)address;
- (NSString *) pinConfigString:(uint8_t)address;
- (void) updatePinDefault:(uint32_t)pinDefault;
- (void) updatePinCommand:(uint32_t)command data:(uint8_t)data;
- (NSComparisonResult) compareDevice:(AudioNode *)other;
- (BOOL) isIn;
- (BOOL) isOut;
- (BOOL) isDigital;
- (BOOL) hasJack;
- (uint8_t) grossLocation;
- (uint8_t) geometricLocation;
- (void) setGrossLocation:(uint8_t)grossLocation;
- (void) setGeometricLocation:(uint8_t)geometricLocation;
- (NSColor *)jackColor;
- (NSString *)directionString;

@property (nonatomic) uint8_t nid;
@property uint8_t port;
@property uint8_t location;
@property uint8_t device;
@property uint8_t connector;
@property uint8_t color;
@property uint8_t misc;
@property uint8_t group;
@property uint8_t index;
@property uint8_t eapd;
//@property uint32_t pinCaps;
@property (retain) NSString *name;
@property (retain) NSString *nodeString;

@end

#endif
