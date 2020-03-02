//
//  AudioNode.m
//  PinConfigurator
//
//  Created by Ben Baker on 2/7/19.
//  Copyright © 2019 Ben Baker. All rights reserved.
//

#import "AudioNode.h"
#import "NSString+Pin.h"
#import "NSColor+Pin.h"
#import <AppKit/AppKit.h>

@implementation AudioNode

- (id)init
{
	self = [super init];
	
	if (self)
		[self setDefaults:0];
	
	return self;
}

- (id)initWithNid:(uint8_t)nID
{
	self = [self init];
	
	if (self)
		[self setDefaults:nID];
	
	return self;
}

- (id)initWithNid:(uint8_t)nid pinDefault:(uint32_t)pinDefault
{
	self = [self initWithNid:nid];
	
	if (self)
		[self updatePinDefault:pinDefault];
	
	return self;
}

- (void) setDefaults:(uint8_t)nid
{
	[self setNid:nid];
	self.name = nil;
	self.port = 4;
	self.location = 0;
	self.device = 0;
	self.connector = 0;
	self.color = 0;
	self.misc = 0;
	self.group = 0xF;
	self.index = 0;
	self.eapd = 0;
}

- (void) dealloc
{
	[_name release];
	[_nodeString release];
	
	[super dealloc];
}

- (id)copyWithZone:(nullable NSZone *)zone
{
	AudioNode *audioNode = [[AudioNode alloc] initWithNid:_nid];
	
	[audioNode setName:_name];
	[audioNode setPort:_port];
	[audioNode setLocation:_location];
	[audioNode setDevice:_device];
	[audioNode setConnector:_connector];
	[audioNode setColor:_color];
	[audioNode setMisc:_misc];
	[audioNode setGroup:_group];
	[audioNode setIndex:_index];
	[audioNode setEapd:_eapd];
	[audioNode setNodeString:_nodeString];

	return audioNode;
}

- (NSString *) description
{
	NSString *direction = (_device <= 5 ? @"[Out]" : @" [In]");
	NSString *color = [NSString pinColor:_color];
	NSString *connector = [NSString pinConnector:_connector];
	NSString *port = [NSString pinPort:_port];
	NSString *location = [NSString pinLocation:[self grossLocation] geometricLocation:[self geometricLocation]];
	NSString *defaultDevice = [NSString pinDefaultDevice:_device];
	NSString *pinDefault = [self pinDefaultString];
	return [NSString stringWithFormat:@"%@ %@ 0x%@ %@, %@, %@, %@, %@, %d.%d", _name, direction, pinDefault, defaultDevice, location, port, connector, color, _group, _index];
}

- (uint32_t) pinDefault
{
	return ((_port << 30) | (_location << 24) | (_device << 20) | (_connector << 16) | (_color << 12) | (_misc << 8) | (_group << 4) | _index);
}

- (NSString *) pinDefaultString
{
	return [NSString stringWithFormat:@"%08X", [self pinDefault]];
}

- (uint32_t) verb70C:(uint8_t)address
{
	return (((address & 0xF) << 28) | ((_nid & 0xFF) << 20) | (0x70C << 8) | (_eapd & 0x3));
}

- (uint32_t) verb71C:(uint8_t)address
{
	return (((address & 0xF) << 28) | ((_nid & 0xFF) << 20) | (0x71C << 8) | ((_group & 0xF) << 4) | (_index & 0xF));
}

- (uint32_t) verb71D:(uint8_t)address
{
	return (((address & 0xF) << 28) | ((_nid & 0xFF) << 20) | (0x71D << 8) | ((_color & 0xF) << 4) | (_misc & 0xF));
}

- (uint32_t) verb71E:(uint8_t)address
{
	return (((address & 0xF) << 28) | ((_nid & 0xFF) << 20) | (0x71E << 8) | ((_device & 0xF) << 4) | (_connector & 0xF));
}

- (uint32_t) verb71F:(uint8_t)address
{
	return (((address & 0xF) << 28) | ((_nid & 0xFF) << 20) | (0x71F << 8) | ((_port & 0x3) << 6) | (_location & 0x3F));
}

- (NSString *) wakeConfigString:(uint8_t)address
{
	return [NSString stringWithFormat:@" %08X", [self verb70C:address]];
}

- (NSString *) pinConfigString:(uint8_t)address
{
	NSString *configString = [NSString stringWithFormat:@"%08X %08X %08X %08X", [self verb71C:address], [self verb71D:address], [self verb71E:address], [self verb71F:address]];
	
	if (_eapd & HDA_EAPD_BTL_ENABLE_EAPD)
		configString = [configString stringByAppendingString:[self wakeConfigString:address]];
	
	return configString;
}

- (void) updatePinDefault:(uint32_t)pinDefault
{
	_index = pinDefault & 0xF;
	_group = (pinDefault >> 4) & 0xF;
	_misc = (pinDefault >> 8) & 0xF;
	_color = (pinDefault >> 12) & 0xF;
	_connector = (pinDefault >> 16) & 0xF;
	_device = (pinDefault >> 20) & 0xF;
	_location = (pinDefault >> 24) & 0x3F;
	_port = (pinDefault >> 30) & 0x3;
}

- (void) updatePinCommand:(uint32_t)command data:(uint8_t)data
{
	switch(command)
	{
		case 0x71C:
			_group = HINIBBLE(data);
			_index = LONIBBLE(data);
			break;
		case 0x71D:
			_color = HINIBBLE(data);
			_misc = LONIBBLE(data);
			break;
		case 0x71E:
			_device = HINIBBLE(data);
			_connector = LONIBBLE(data);
			break;
		case 0x71F:
			_port = (data >> 6) & 0x3;
			_location = data & 0x3F;
			break;
	}
}

- (NSComparisonResult) compareDevice:(AudioNode *)other
{
	int result = [self group] - [other group];
	
	if (result == 0)
		result = [self index] - [other index];
	
	if (result == 0)
		return NSOrderedSame;
	
	return (result < 0 ? NSOrderedAscending : NSOrderedDescending);
}

- (void) setNid:(uint8_t)nid
{
	_nid = nid;
	[self setNodeString:[NSString stringWithFormat:@"%02d (0x%02X)", _nid, _nid]];
}

- (BOOL) isIn
{
	return (_device > kHdaConfigDefaultDeviceModemHandset && _device <= kHdaConfigDefaultDeviceOtherDigitalIn);
}

- (BOOL) isOut
{
	return (_device <= kHdaConfigDefaultDeviceModemHandset);
}

- (BOOL) isDigital
{
	return (_device == kHdaConfigDefaultDeviceSPDIFOut || _device == kHdaConfigDefaultDeviceOtherDigitalOut || _device == kHdaConfigDefaultDeviceSPDIFIn || _device == kHdaConfigDefaultDeviceOtherDigitalIn);
}

- (BOOL) hasJack
{
	return ([self geometricLocation] == 1 || [self geometricLocation] == 2);
}

- (uint8_t) grossLocation
{
	return (_location >> 4) & 0x3;
}

- (uint8_t) geometricLocation
{
	return (_location & 0xF);
}

- (void) setGrossLocation:(uint8_t)grossLocation
{
	_location = ((grossLocation & 0x3) << 4) | (_location & 0xF);
}

- (void) setGeometricLocation:(uint8_t)geometricLocation
{
	_location = (_location & 0x30) | (geometricLocation & 0xF);
}

- (NSColor *)jackColor
{
	return [NSColor pinColor:_color];
}

- (NSString *)directionString
{
	return [NSString pinDirection:_device];
}

@end
