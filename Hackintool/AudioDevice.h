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

@property (nonatomic, retain) NSString *deviceClass;
@property uint32_t deviceID;
@property uint32_t revisionID;
@property uint32_t alcLayoutID;
@property uint32_t subDeviceID;
@property uint32_t codecAddress;
@property uint32_t codecID;
@property uint32_t codecRevisionID;
@property (nonatomic, retain) NSData *pinConfigurations;
@property (nonatomic, retain) NSDictionary *digitalAudioCapabilities;
@property (nonatomic, retain) NSString *codecVendorName;
@property (nonatomic, retain) NSString *codecName;
@property (nonatomic, retain) NSMutableArray *layoutIDArray;
@property (nonatomic, retain) NSMutableArray *revisionArray;
@property uint32_t minKernel;
@property uint32_t maxKernel;
@property (nonatomic, retain) NSDictionary *hdaConfigDefaultDictionary;
@property (nonatomic, retain) NSString *bundleID;

-(id) initWithDeviceClass:(NSString *)deviceClass deviceID:(uint32_t)deviceID revisionID:(uint32_t)revisionID alcLayoutID:(uint32_t)alcLayoutID subDeviceID:(uint32_t)subDeviceID codecAddress:(uint32_t)codecAddress codecID:(uint32_t)codecID codecRevisionID:(uint32_t)codecRevisionID pinConfigurations:(NSData *)pinConfigurations digitalAudioCapabilities:(NSDictionary *)digitalAudioCapabilities;

@end

#endif /* AudioDevice_h */
