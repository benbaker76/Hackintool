//
//  AudioDevice.h
//  Hackintool
//
//  Created by Ben Baker on 2/12/19.
//  Copyright © 2019 Ben Baker. All rights reserved.
//

#ifndef AudioDevice_h
#define AudioDevice_h

#import <Cocoa/Cocoa.h>
#import <stdint.h>

@interface AudioDevice : NSObject
{
}

@property (nonatomic, retain) NSString *bundleID;
@property (nonatomic, retain) NSString *deviceClass;
@property uint32_t deviceID;
@property uint32_t revisionID;
@property uint32_t layoutID;
@property uint32_t alcLayoutID;
@property uint32_t subDeviceID;
@property uint32_t codecAddress;
@property uint32_t codecID;
@property uint32_t codecRevisionID;
@property uint32_t audioDeviceModelID;
@property (nonatomic, retain) NSString *audioDeviceName;
@property (nonatomic, retain) NSString *audioDeviceManufacturerName;
@property (nonatomic, retain) NSString *vendorName;
@property (nonatomic, retain) NSString *deviceName;
@property (nonatomic, retain) NSString *subVendorName;
@property (nonatomic, retain) NSString *subDeviceName;
@property (nonatomic, retain) NSString *codecVendorName;
@property (nonatomic, retain) NSString *codecName;
@property (nonatomic, retain) NSMutableArray *layoutIDArray;
@property (nonatomic, retain) NSMutableArray *revisionArray;
@property (nonatomic, retain) NSData *digitalAudioCapabilities;
@property (nonatomic, retain) NSMutableDictionary *hdaConfigDefaultDictionary;
@property uint32_t minKernel;
@property uint32_t maxKernel;

-(id) initWithDeviceBundleID:(NSString *)bundleID deviceClass:(NSString *)deviceClass audioDeviceName:(NSString *)audioDeviceName audioDeviceManufacturerName:(NSString *)audioDeviceManufacturerName audioDeviceModelID:(uint32_t)audioDeviceModelID deviceID:(uint32_t)deviceID revisionID:(uint32_t)revisionID alcLayoutID:(uint32_t)alcLayoutID subDeviceID:(uint32_t)subDeviceID;

@end

#endif /* AudioDevice_h */
