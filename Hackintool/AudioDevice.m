//
//  AudioDevice.m
//  Hackintool
//
//  Created by Ben Baker on 2/12/19.
//  Copyright © 2019 Ben Baker. All rights reserved.
//

#import "AudioDevice.h"

@implementation AudioDevice

-(id) initWithDeviceBundleID:(NSString *)bundleID deviceClass:(NSString *)deviceClass deviceID:(uint32_t)deviceID revisionID:(uint32_t)revisionID alcLayoutID:(uint32_t)alcLayoutID subDeviceID:(uint32_t)subDeviceID pinConfigurations:(NSData *)pinConfigurations
{
	if (self = [super init])
	{
		self.bundleID = bundleID;
		self.deviceClass = deviceClass;
		self.deviceID = deviceID;
		self.revisionID = revisionID;
		self.alcLayoutID = alcLayoutID;
		self.subDeviceID = subDeviceID;
		self.pinConfigurations = pinConfigurations;
	}
	
	return self;
}

- (void)dealloc
{
	[_bundleID release];
	[_deviceClass release];
	[_vendorName release];
	[_deviceName release];
	[_codecVendorName release];
	[_codecName release];
	[_layoutIDArray release];
	[_revisionArray release];
	[_pinConfigurations release];
	[_digitalAudioCapabilities release];
	
	[super dealloc];
}

@end
