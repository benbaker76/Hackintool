//
//  Resolution.h
//  Hackintool
//
//  Created by Ben Baker on 2/12/19.
//  Copyright © 2019 Ben Baker. All rights reserved.
//

#ifndef Resolution_h
#define Resolution_h

#import <Cocoa/Cocoa.h>

typedef enum
{
	kHiDPI1,
	kHiDPI2,
	kHiDPI3,
	kHiDPI4,
	kNonScaled,
	kAuto
} HiDPIType;

@interface Resolution : NSObject
{
}

@property uint32_t width;
@property uint32_t height;
@property HiDPIType type;

-(id) initWithWidth:(uint32_t)width height:(uint32_t)height type:(HiDPIType)type;

@end

#endif /* Resolution_h */
