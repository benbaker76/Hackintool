//
//  AudioDevice.m
//  Hackintool
//
//  Created by Ben Baker on 2/12/19.
//  Copyright © 2019 Ben Baker. All rights reserved.
//

#import "AudioDevice.h"

@implementation AudioDevice

-(id) initWithDeviceClass:(NSString *)deviceClass deviceID:(uint32_t)deviceID revisionID:(uint32_t)revisionID alcLayoutID:(uint32_t)alcLayoutID subDeviceID:(uint32_t)subDeviceID codecAddress:(uint32_t)codecAddress codecID:(uint32_t)codecID codecRevisionID:(uint32_t)codecRevisionID pinConfigurations:(NSData *)pinConfigurations digitalAudioCapabilities:(NSDictionary *)digitalAudioCapabilities
{
	if (self = [super init])
	{
		_deviceClass = deviceClass;
		_deviceID = deviceID;
		_revisionID = revisionID;
		_alcLayoutID = alcLayoutID;
		_subDeviceID = subDeviceID;
		_codecAddress = codecAddress;
		_codecID = codecID;
		_codecRevisionID = codecRevisionID;
		_pinConfigurations = pinConfigurations;
		_digitalAudioCapabilities = digitalAudioCapabilities;
	}
	
	return self;
}

- (void)dealloc
{
	[_deviceClass release];
	[_pinConfigurations release];
	[_digitalAudioCapabilities release];
	[_codecName release];
	[_layoutIDArray release];
	[_revisionArray release];
	[_hdaConfigDefaultDictionary release];
	[_bundleID release];
	
	[super dealloc];
}

@end
