//
//  Display.m
//  Hackintool
//
//  Created by Ben Baker on 2/12/19.
//  Copyright © 2019 Ben Baker. All rights reserved.
//

#import "Display.h"

@implementation Display

-(id) initWithName:(NSString *)name index:(uint32_t) index port:(uint32_t)port vendorID:(uint32_t)vendorID productID:(uint32_t)productID serialNumber:(uint32_t)serialNumber edid:(NSData *)edid prefsKey:(NSString *)prefsKey isInternal:(bool)isInternal videoPath:(NSString *)videoPath videoID:(uint32_t)videoID resolutionsArray:(NSMutableArray *)resolutionsArray directDisplayID:(CGDirectDisplayID)directDisplayID
{
	if (self = [super init])
	{
		self.name = name;
		self.index = index;
		self.port = port;
		self.vendorID = vendorID;
		self.productID = productID;
		self.vendorIDOverride = vendorID;
		self.productIDOverride = productID;
		self.serialNumber = serialNumber;
		self.eDID = edid;
		self.prefsKey = prefsKey;
		self.isInternal = isInternal;
		self.videoPath = videoPath;
		self.videoID = videoID;
		self.resolutionsArray = resolutionsArray;
		self.directDisplayID = directDisplayID;
		self.eDIDIndex = 0;
		self.iconIndex = 0;
		self.resolutionIndex = 0;
		self.fixMonitorRanges = false;
		self.injectAppleVID = false;
		self.injectApplePID = true;
		self.forceRGBMode = true;
		self.patchColorProfile = true;
		self.ignoreDisplayPrefs = true;
	}
	
	return self;
}

- (void)dealloc
{
	[_name release];
	[_eDID release];
	[_prefsKey release];
	[_resolutionsArray release];
	
	[super dealloc];
}

@end
