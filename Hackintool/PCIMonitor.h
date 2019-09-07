//
//  PCIMonitor.h
//  Hackintool
//
//  Created by Daniel Siemer on 5/5/12.
//  Modified by Ben Baker.
//  Copyright (c) 2012 The Growl Project, LLC. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@protocol PCIMonitorDelegate <NSObject>

-(void)pciDeviceName:(NSString*)deviceName added:(BOOL)added;

@end

@interface PCIMonitor : NSObject

@property (nonatomic, assign) id<PCIMonitorDelegate> delegate;
@property (nonatomic, assign) BOOL notificationsArePrimed;

@property (nonatomic, assign) IONotificationPortRef ioKitNotificationPort;
@property (nonatomic, assign) CFRunLoopSourceRef notificationRunLoopSource;

-(void)registerForPCINotifications;

@end
