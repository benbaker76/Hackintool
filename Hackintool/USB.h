//
//  USB.h
//  Hackintool
//
//  Created by Ben Baker on 1/29/19.
//  Copyright © 2019 Ben Baker. All rights reserved.
//

#ifndef USB_h
#define USB_h

#import "AppDelegate.h"
#include <IOKit/usb/IOUSBLib.h>

typedef struct
{
	AppDelegate *appDelegate;
	io_object_t removedIter;
	IOUSBDeviceInterface650 **deviceInterface;
	//IOUSBDeviceInterface **deviceInterface;
	CFStringRef deviceName;
	uint32_t locationID;
} MyPrivateData;

enum UsbConnector
{
	TypeA			= 0x00,	// Type ‘A’ connector
	MiniAB			= 0x01,	// Mini-AB connector
	ExpressCard		= 0x02,	// ExpressCard
	USB3StandardA	= 0x03,	// USB 3 Standard-A connector
	USB3StandardB	= 0x04,	// USB 3 Standard-B connector
	USB3MicroB		= 0x05,	// USB 3 Micro-B connector
	USB3MicroAB		= 0x06,	// USB 3 Micro-AB connector
	USB3PowerB		= 0x07,	// USB 3 Power-B connector
	TypeCUSB2Only	= 0x08, // Type C connector - USB2-only
	// These only implement the USB2 signal pair, and do not implement the SS signal
	// pairs
	TypeCSSSw		= 0x09, // Type C connector - USB2 and SS with Switch
	// These implement the USB2 signal pair, and a Functional Switch with a physical
	// Multiplexer that is used to dynamically connect one of the two receptacle SuperSpeed
	// signal pairs to a single USB Host Controller port as function of the Type-C plug
	// orientation.
	TypeCSS			= 0x0A, // Type C connector - USB2 and SS without Switch
	// These implement the USB2 signal pair and a Functional Switch by connecting each
	// receptacle SuperSpeed signal pair to a separate USB Host Controller port.
	// 0x0B – 0xFE: Reserved
	Internal		= 0xFF	// Proprietary connector
};

void usbUnRegisterEvents();
void usbRegisterEvents(AppDelegate *appDelegate);
void usbDeviceNotification(void *refCon, io_service_t service, natural_t messageType, void *messageArgument);
void destroyPrivateData(MyPrivateData *privateDataRef);
void usbDeviceAdded(void *refCon, io_iterator_t iterator);
//void usbDeviceRemoved(void *refCon, io_iterator_t iterator);
NSString *getUSBConnectorType(UsbConnector usbConnector);
NSString *getUSBConnectorSpeed(uint8_t speed);
void exportUSBPortsKext(AppDelegate *appDelegate);
void exportUSBPortsSSDT(AppDelegate *appDelegate);
void exportUSBPorts(AppDelegate *appDelegate);

#endif /* USB_hpp */
