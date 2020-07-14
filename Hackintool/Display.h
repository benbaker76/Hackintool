//
//  Display.h
//  Hackintool
//
//  Created by Ben Baker on 2/12/19.
//  Copyright © 2019 Ben Baker. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>

@interface Display : NSObject
{
}

@property (nonatomic, retain) NSString *name;
@property uint32_t index;
@property uint32_t port;
@property uint32_t vendorID;
@property uint32_t productID;
@property uint32_t vendorIDOverride;
@property uint32_t productIDOverride;
@property uint32_t serialNumber;
@property (nonatomic, retain) NSData *eDID;
@property (nonatomic, retain) NSString *prefsKey;
@property (nonatomic, retain) NSString *videoPath;
@property uint32_t videoID;
@property bool isInternal;
@property (nonatomic, retain) NSMutableArray *resolutionsArray;
@property CGDirectDisplayID directDisplayID;
@property uint32_t eDIDIndex;
@property uint32_t iconIndex;
@property uint32_t resolutionIndex;
@property bool fixMonitorRanges;
@property bool injectAppleVID;
@property bool injectApplePID;
@property bool forceRGBMode;
@property bool patchColorProfile;
@property bool ignoreDisplayPrefs;

-(id) initWithName:(NSString *)name index:(uint32_t) index port:(uint32_t)port vendorID:(uint32_t)vendorID productID:(uint32_t)productID serialNumber:(uint32_t)serialNumber edid:(NSData *)edid prefsKey:(NSString *)prefsKey isInternal:(bool)isInternal videoPath:(NSString *)videoPath videoID:(uint32_t)videoID resolutionsArray:(NSMutableArray *)resolutionsArray directDisplayID:(CGDirectDisplayID)directDisplayID;

@end
