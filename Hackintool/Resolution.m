//
//  Resolution.m
//  Hackintool
//
//  Created by Ben Baker on 2/12/19.
//  Copyright © 2019 Ben Baker. All rights reserved.
//

#import "Resolution.h"

@implementation Resolution

-(id) initWithWidth:(uint32_t)width height:(uint32_t)height type:(HiDPIType)type
{
	if (self = [super init])
	{
		self.width = width;
		self.height = height;
		self.type = type;
	}
	
	return self;
}

@end
