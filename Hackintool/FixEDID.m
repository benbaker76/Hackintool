//
//  FixEDID.m
//  Hackintool
//
//  Created by Andy Vandijck on 6/24/13.
//  Modified by Ben Baker.
//  Copyright © 2019 Andy Vandijck. All rights reserved.
//

#include "FixEDID.h"
#include "Resolution.h"

#define GetLocalizedString(key) \
[[NSBundle mainBundle] localizedStringForKey:(key) value:@"" table:nil]

#define USE_USBMERGENUB

// Needed to check the EDID header
const uint8_t EDID_Header[8] = { 0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00 };

// Version override - fixes some issues
const uint8_t Version_1_4[2] = { 0x01, 0x04 };

// Monitor Ranges Override - fixes some issues
const uint8_t Monitor_Ranges[18] = { 0x00, 0x00, 0x00, 0xfd, 0x00, 0x38, 0x4c, 0x1e, 0x53, 0x11, 0x00, 0x0a, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20 };

// VendorID 0x0610
const uint8_t AppleDisplay_VID[2] = { 0x06, 0x10 };
// ProductID 0xA012
const uint8_t AppleDisplay_PID[2] = { 0x7c, 0x9c };

// Apple iMac Display fixes
const char *iMac_CapabilityString = "model(iMac Cello) vcp(10 8D B6 C8 C9 DF) ver(2.2)";
const uint8_t iMac_BasicParams[5] = { 0xb5, 0x30, 0x1b, 0x78, 0x22 };
const uint8_t iMac_ConnectFlags[4] = { 0x84, 0x49, 0x00, 0x00 };
const uint8_t iMac_ControllerID[4] = { 0x01, 0x00, 0x00, 0x00 };
const uint8_t iMac_FirmwareLevel[4] = { 0x01, 0x00, 0x00, 0x00 };
const uint8_t iMac_MCCSVersion[4] = { 0x00, 0x02, 0x02, 0x00 };
const uint8_t iMac_TechnologyType[4] = { 0xff, 0xff, 0x02, 0x03 };
const uint8_t iMac_Serial[10] = { 0x06, 0x10, 0x12, 0xa0, 0x00, 0x00, 0x00, 0x00, 0x1c, 0x16 };
const uint8_t iMac_Chroma[10] = { 0x6f, 0xb1, 0xa7, 0x55, 0x4c, 0x9e, 0x25, 0x0c, 0x50, 0x54 };
const uint8_t iMac_Details_Name[18] = { 0x00, 0x00, 0x00, 0xfc, 0x00, 0x69, 0x4d, 0x61, 0x63, 0x0a, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20 };
const uint8_t iMac_EDID[256] = {    0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00, 0x06, 0x10, 0x12, 0xa0, 0x00, 0x00, 0x00, 0x00,
                                    0x1c, 0x16, 0x01, 0x04, 0xb5, 0x30, 0x1b, 0x78, 0x22, 0x6f, 0xb1, 0xa7, 0x55, 0x4c, 0x9e, 0x25,
                                    0x0c, 0x50, 0x54, 0x00, 0x00, 0x00, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
                                    0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x1a, 0x36, 0x80, 0xa0, 0x70, 0x38, 0x1f, 0x40, 0x30, 0x20,
                                    0x35, 0x00, 0xdb, 0x0b, 0x11, 0x00, 0x00, 0x1a, 0x8d, 0x0e, 0xc0, 0xa0, 0x30, 0x1c, 0x10, 0x20,
                                    0x30, 0x20, 0x35, 0x00, 0xdb, 0x0b, 0x11, 0x00, 0x00, 0x1a, 0x00, 0x00, 0x00, 0xfc, 0x00, 0x69,
                                    0x4d, 0x61, 0x63, 0x0a, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x00, 0x00, 0x00, 0x00,
                                    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0xe7 };
uint32_t iMacVendorID = 0x0610;
uint32_t iMacProductID = 0xA012;

// Apple iMac Retina Display fixes
const char *iMacRetina_CapabilityString = "(prot(backlight) type(led) model(iMac) vcp(02 10 52 8D C8 C9 DE DF FC FD FE) mccs_ver(2.2))";
const uint8_t iMacRetina_BasicParams[5] = { 0xb5, 0x30, 0x1b, 0x78, 0x22 };
const uint8_t iMacRetina_ConnectFlags[4] = { 0x84, 0x49, 0x00, 0x00 };
const uint8_t iMacRetina_ControllerID[4] = { 0x02, 0x04, 0x11, 0xff };
const uint8_t iMacRetina_FirmwareLevel[4] = { 0x00, 0x00, 0x02, 0x04 };
const uint8_t iMacRetina_MCCSVersion[4] = { 0x00, 0x02, 0x02, 0x00 };
const uint8_t iMacRetina_Serial[10] = { 0x06, 0x10, 0x05, 0xb0, 0x00, 0x00, 0x00, 0x00, 0x1c, 0x16 };
const uint8_t iMacRetina_Chroma[10] = { 0x6f, 0xb1, 0xa7, 0x55, 0x4c, 0x9e, 0x25, 0x0c, 0x50, 0x54 };
const uint8_t iMacRetina_Details_Name[18] = { 0x00, 0x00, 0x00, 0xfc, 0x00, 0x69, 0x4d, 0x61, 0x63, 0x0a, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20 };
const uint8_t iMacRetina_EDID[128] = {  0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00, 0x06, 0x10, 0x05, 0xb0, 0x00, 0x00, 0x00, 0x00,
                                        0x1c, 0x16, 0x01, 0x04, 0xb5, 0x3c, 0x22, 0x78, 0x22, 0x6f, 0xb1, 0xa7, 0x55, 0x4c, 0x9e, 0x25,
                                        0x0c, 0x50, 0x54, 0x00, 0x00, 0x00, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
                                        0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x56, 0x5e, 0x00, 0xa0, 0xa0, 0xa0, 0x29, 0x50, 0x30, 0x20,
                                        0x35, 0x00, 0x55, 0x50, 0x21, 0x00, 0x00, 0x1a, 0x1a, 0x1d, 0x00, 0x80, 0x51, 0xd0, 0x1c, 0x20,
                                        0x40, 0x80, 0x35, 0x00, 0x55, 0x50, 0x21, 0x00, 0x00, 0x1c, 0x00, 0x00, 0x00, 0xfc, 0x00, 0x69,
                                        0x4d, 0x61, 0x63, 0x0a, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x00, 0x00, 0x00, 0x00,
                                        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x8e };
uint32_t iMacRetinaVendorID = 0x0610;
uint32_t iMacRetinaProductID = 0xB005;

// Apple MacBook Pro Display fixes
const uint8_t MBP_BasicParams[5] = { 0xa5, 0x1d, 0x12, 0x78, 0x02 };
const uint8_t MBP_ConnectFlags[4] = { 0x00, 0x08, 0x00, 0x00 };
const uint8_t MBP_Serial[10] = { 0x06, 0x10, 0x14, 0xa0, 0x00, 0x00, 0x00, 0x00, 0x0a, 0x16 };
const uint8_t MBP_Chroma[10] = { 0x6f, 0xb1, 0xa7, 0x55, 0x4c, 0x9e, 0x25, 0x0c, 0x50, 0x54 };
const uint8_t MBP_Details_Name[18] = { 0x00, 0x00, 0x00, 0xfc, 0x00, 0x43, 0x6f, 0x6c, 0x6f, 0x72, 0x20, 0x4c, 0x43, 0x44, 0x0a, 0x20, 0x20, 0x20 };
const uint8_t MBP_EDID[128] = { 0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00, 0x06, 0x10, 0x14, 0xa0, 0x00, 0x00, 0x00, 0x00,
                                0x0a, 0x16, 0x01, 0x04, 0xa5, 0x1d, 0x12, 0x78, 0x02, 0x6f, 0xb1, 0xa7, 0x55, 0x4c, 0x9e, 0x25,
                                0x0c, 0x50, 0x54, 0x00, 0x00, 0x00, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
                                0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0xe2, 0x68, 0x00, 0xa0, 0xa0, 0x40, 0x2e, 0x60, 0x30, 0x20,
                                0x36, 0x00, 0x1e, 0xb3, 0x10, 0x00, 0x00, 0x1a, 0x00, 0x00, 0x00, 0xfc, 0x00, 0x43, 0x6f, 0x6c,
                                0x6f, 0x72, 0x20, 0x4c, 0x43, 0x44, 0x0a, 0x20, 0x20, 0x20, 0x00, 0x00, 0x00, 0x10, 0x00, 0x00,
                                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10,
                                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x8d };
uint32_t MBPVendorID = 0x0610;
uint32_t MBPProductID = 0xA014;

// Apple MacBook Air Display fixes
const uint8_t MBA_BasicParams[5] = { 0x95, 0x1a, 0x0e, 0x78, 0x02 };
const uint8_t MBA_ConnectFlags[4] = { 0x00, 0x08, 0x00, 0x00 };
const uint8_t MBA_Serial[10] = { 0x06, 0x10, 0xf2, 0x9c, 0x00, 0x00, 0x00, 0x00, 0x1a, 0x15 };
const uint8_t MBA_Chroma[10] = { 0xef, 0x05, 0x97, 0x57, 0x54, 0x92, 0x27, 0x22, 0x50, 0x54 };
const uint8_t MBA_Details_Name[18] = { 0x00, 0x00, 0x00, 0xfc, 0x00, 0x43, 0x6f, 0x6c, 0x6f, 0x72, 0x20, 0x4c, 0x43, 0x44, 0x0a, 0x20, 0x20, 0x20 };
const uint8_t MBA_EDID[128] = { 0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00, 0x06, 0x10, 0xf2, 0x9c, 0x00, 0x00, 0x00, 0x00,
                                0x1a, 0x15, 0x01, 0x04, 0x95, 0x1a, 0x0e, 0x78, 0x02, 0xef, 0x05, 0x97, 0x57, 0x54, 0x92, 0x27,
                                0x22, 0x50, 0x54, 0x00, 0x00, 0x00, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
                                0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x20, 0x1c, 0x56, 0x86, 0x50, 0x00, 0x20, 0x30, 0x0e, 0x38,
                                0x13, 0x00, 0x00, 0x90, 0x10, 0x00, 0x00, 0x18, 0x00, 0x00, 0x00, 0x10, 0x00, 0x00, 0x00, 0x00,
                                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xfe, 0x00, 0x4c,
                                0x50, 0x31, 0x31, 0x36, 0x57, 0x48, 0x34, 0x2d, 0x54, 0x4a, 0x41, 0x33, 0x00, 0x00, 0x00, 0xfc,
                                0x00, 0x43, 0x6f, 0x6c, 0x6f, 0x72, 0x20, 0x4c, 0x43, 0x44, 0x0a, 0x20, 0x20, 0x20, 0x00, 0xbd };
uint32_t MBAVendorID = 0x0610;
uint32_t MBAProductID = 0x9CF2;

// Apple Cinema HD Display fixes
const uint8_t CHD_BasicParams[5] = { 0x80, 0x40, 0x28, 0x78, 0x2A };
const uint8_t CHD_ConnectFlags[4] = { 0xc4, 0x41, 0x00, 0x00 };
const uint8_t CHD_Serial[10] = { 0x06, 0x10, 0x32, 0x92, 0x7c, 0x9f, 0x00, 0x02, 0x2a, 0x10 };
const uint8_t CHD_Chroma[10] = { 0xfe, 0x87, 0xa3, 0x57, 0x4a, 0x9c, 0x25, 0x13, 0x50, 0x54 };
const uint8_t CHD_Details_Name[18] = { 0x00, 0x00, 0x00, 0xfc, 0x00, 0x43, 0x69, 0x6e, 0x65, 0x6d, 0x61, 0x20, 0x48, 0x44, 0x0a, 0x00, 0x00, 0x00 };
const uint8_t CHD_Details_Serial[18] = { 0x00, 0x00, 0x00, 0xff, 0x00, 0x43, 0x59, 0x36, 0x34, 0x32, 0x30, 0x5a, 0x36, 0x55, 0x47, 0x31, 0x0a, 0x00 };
const uint8_t CHD_EDID[128] = { 0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00, 0x06, 0x10, 0x32, 0x92, 0xbe, 0x70, 0x00, 0x02,
                                0x20, 0x10, 0x01, 0x03, 0x80, 0x40, 0x28, 0x78, 0x28, 0xfe, 0x87, 0xa3, 0x57, 0x4a, 0x9c, 0x25,
                                0x13, 0x50, 0x54, 0x00, 0x00, 0x00, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
                                0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0xbc, 0x1b, 0x00, 0xa0, 0x50, 0x20, 0x17, 0x30, 0x30, 0x20,
                                0x36, 0x00, 0x81, 0x91, 0x21, 0x00, 0x00, 0x1a, 0xb0, 0x68, 0x00, 0xa0, 0xa0, 0x40, 0x2e, 0x60,
                                0x30, 0x20, 0x36, 0x00, 0x81, 0x91, 0x21, 0x00, 0x00, 0x1a, 0x00, 0x00, 0x00, 0xff, 0x00, 0x43,
                                0x59, 0x36, 0x33, 0x32, 0x31, 0x35, 0x55, 0x55, 0x47, 0x31, 0x0a, 0x00, 0x00, 0x00, 0x00, 0xfc,
                                0x00, 0x43, 0x69, 0x6e, 0x65, 0x6d, 0x61, 0x20, 0x48, 0x44, 0x0a, 0x00, 0x00, 0x00, 0x01, 0x2d };
uint32_t CHDVendorID = 0x0610;
uint32_t CHDProductID = 0x9232;

// Apple Thunderbolt Display fixes
const char *TDB_CapabilityString = "prot(monitor) type(LCD) model(Thunderbolt Display) cmds(01 02 03 E3 F3) VCP(02 05 10 52 62 66 8D 93 B6 C0 C8 C9 CA D6(01 02 03 04) DF E9 EB ED FD) mccs_ver(2.2)";
const uint8_t TDB_BasicParams[5] = { 0xb5, 0x3c, 0x22, 0x78, 0x22 };
const uint8_t TDB_ConnectFlags[4] = { 0x00, 0x00, 0x00, 0x00 };
const uint8_t TDB_ControllerID[4] = { 0x00, 0x00, 0x00, 0xff };
const uint8_t TDB_FirmwareLevel[4] = { 0xff, 0xff, 0x01, 0x38 };
const uint8_t TDB_MCCSVersion[4] = { 0x00, 0x02, 0x02, 0x00 };
const uint8_t TDB_TechnologyType[4] = { 0x00, 0xff, 0x02, 0x03 };
const uint8_t TDB_Serial[10] = { 0x06, 0x10, 0x27, 0x92, 0x1f, 0x00, 0x23, 0x16, 0x23, 0x16 };
const uint8_t TDB_Chroma[10] = { 0x6f, 0xb1, 0xa7, 0x55, 0x4c, 0x9e, 0x25, 0x0c, 0x50, 0x54 };
const uint8_t TDB_Details_Name[18] = { 0x00, 0x00, 0x00, 0xfc, 0x00, 0x54, 0x68, 0x75, 0x6e, 0x64, 0x65, 0x72, 0x62, 0x6f, 0x6c, 0x74, 0x0a, 0x20 };
const uint8_t TDB_Details_Serial[18] = { 0x00, 0x00, 0x00, 0xff, 0x00, 0x43, 0x30, 0x32, 0x4a, 0x39, 0x30, 0x30, 0x58, 0x46, 0x32, 0x47, 0x43, 0x0a };
const uint8_t TDB_EDID[128] = { 0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00, 0x06, 0x10, 0x27, 0x92, 0x66, 0x0d, 0x0a, 0x19,
                                0x0a, 0x19, 0x01, 0x04, 0xb5, 0x3c, 0x22, 0x78, 0x22, 0x6f, 0xb1, 0xa7, 0x55, 0x4c, 0x9e, 0x25,
                                0x0c, 0x50, 0x54, 0x00, 0x00, 0x00, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
                                0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x56, 0x5e, 0x00, 0xa0, 0xa0, 0xa0, 0x29, 0x50, 0x30, 0x20,
                                0x35, 0x00, 0x55, 0x50, 0x21, 0x00, 0x00, 0x1a, 0x1a, 0x1d, 0x00, 0x80, 0x51, 0xd0, 0x1c, 0x20,
                                0x40, 0x80, 0x35, 0x00, 0x55, 0x50, 0x21, 0x00, 0x00, 0x1c, 0x00, 0x00, 0x00, 0xff, 0x00, 0x43,
                                0x30, 0x32, 0x50, 0x43, 0x32, 0x59, 0x57, 0x46, 0x32, 0x47, 0x43, 0x0a, 0x00, 0x00, 0x00, 0xfc,
                                0x00, 0x54, 0x68, 0x75, 0x6e, 0x64, 0x65, 0x72, 0x62, 0x6f, 0x6c, 0x74, 0x0a, 0x20, 0x01, 0xad };
uint32_t TDBVendorID = 0x0610;
uint32_t TDBProductID = 0x9227;

// Apple LED Cinema Display fixes
const uint8_t LED_BasicParams[5] = { 0xa5, 0x34, 0x20, 0x78, 0x26 };
const uint8_t LED_ConnectFlags[4] = { 0x84, 0x41, 0x00, 0x00 };
const uint8_t LED_Serial[10] = { 0x06, 0x10, 0x36, 0x92, 0x00, 0x22, 0x0d, 0x02, 0x03, 0x13 };
const uint8_t LED_Chroma[10] = { 0x6e, 0xa1, 0xa7, 0x55, 0x4c, 0x9d, 0x25, 0x0e, 0x50, 0x54 };
const uint8_t LED_Details_Name[18] = { 0x00, 0x00, 0x00, 0xfc, 0x00, 0x4c, 0x45, 0x44, 0x20, 0x43, 0x69, 0x6e, 0x65, 0x6d, 0x61, 0x0a, 0x20, 0x20 };
const uint8_t LED_Details_Serial[18] = { 0x00, 0x00, 0x00, 0xff, 0x00, 0x32, 0x41, 0x39, 0x30, 0x33, 0x34, 0x31, 0x5a, 0x30, 0x4b, 0x30, 0x0a, 0x20 };
const uint8_t LED_EDID[128] = { 0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00, 0x06, 0x10, 0x36, 0x92, 0x89, 0x70, 0x73, 0x02,
                                0x25, 0x13, 0x01, 0x04, 0xa5, 0x34, 0x20, 0x78, 0x26, 0x6e, 0xa1, 0xa7, 0x55, 0x4c, 0x9d, 0x25,
                                0x0e, 0x50, 0x54, 0x00, 0x00, 0x00, 0xd1, 0x00, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
                                0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x28, 0x3c, 0x80, 0xa0, 0x70, 0xb0, 0x23, 0x40, 0x30, 0x20,
                                0x36, 0x00, 0x06, 0x44, 0x21, 0x00, 0x00, 0x1a, 0x00, 0x00, 0x00, 0xff, 0x00, 0x32, 0x41, 0x39,
                                0x33, 0x37, 0x32, 0x35, 0x54, 0x30, 0x4b, 0x30, 0x0a, 0x20, 0x00, 0x00, 0x00, 0xfc, 0x00, 0x4c,
                                0x45, 0x44, 0x20, 0x43, 0x69, 0x6e, 0x65, 0x6d, 0x61, 0x0a, 0x20, 0x20, 0x00, 0x00, 0x00, 0x00,
                                0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0xfc };
uint32_t LEDVendorID = 0x0610;
uint32_t LEDProductID = 0x9236;

@implementation FixEDID

+ (void)calcEDIDChecksum:(EDID &)edid
{
	uint8_t *x = (uint8_t *)&edid;
	uint8_t sum = 0;
	uint32_t i = 0;
	
	for (i = 0; i < 127; i++)
		sum += x[i];
	
	edid.Checksum = (uint8_t)((((unsigned short)0x100) - sum) & 0xFF);
}

+ (bool)hasNameType:(DetailedTiming &)detailedTimings
{
	return (detailedTimings.PixelClock == 0 && detailedTimings.Data.PixelData.HActiveLo == 0 && detailedTimings.Data.OtherData.Type == 0xFC);
}

+ (bool)hasRangeType:(DetailedTiming &)detailedTimings
{
	return (detailedTimings.PixelClock == 0 && detailedTimings.Data.PixelData.HActiveLo == 0 && detailedTimings.Data.OtherData.Type == 0xFD);
}

+ (bool)hasSerialType:(DetailedTiming &)detailedTimings
{
	return (detailedTimings.PixelClock == 0 && detailedTimings.Data.PixelData.HActiveLo == 0 && detailedTimings.Data.OtherData.Type == 0xFF);
}

+ (bool)hasPixelTimingType:(DetailedTiming &)detailedTimings
{
	if (detailedTimings.PixelClock == 0 && detailedTimings.Data.PixelData.HActiveLo == 0)
	{
		switch(detailedTimings.Data.OtherData.Type)
		{
			case 0x00:
			case 0x01:
			case 0x02:
			case 0x03:
			case 0x04:
			case 0x05:
			case 0x06:
			case 0x07:
			case 0x08:
			case 0x09:
			case 0x0A:
			case 0x0B:
			case 0x0C:
			case 0x0D:
			case 0x0E:
			case 0x0F:
			case 0x10:
			case 0xF7:
			case 0xF8:
			case 0xF9:
			case 0xFA:
			case 0xFB:
			case 0xFC:
			case 0xFD:
			case 0xFE:
			case 0xFF:
				return false;
		}
	}
	
	return true;
}

+ (bool)hasOtherType:(DetailedTiming &)detailedTimings
{
	if (detailedTimings.PixelClock == 0 && detailedTimings.Data.PixelData.HActiveLo == 0)
	{
		switch(detailedTimings.Data.OtherData.Type)
		{
			case 0x00:
			case 0x01:
			case 0x02:
			case 0x03:
			case 0x04:
			case 0x05:
			case 0x06:
			case 0x07:
			case 0x08:
			case 0x09:
			case 0x0A:
			case 0x0B:
			case 0x0C:
			case 0x0D:
			case 0x0E:
			case 0x0F:
			case 0x10:
			case 0xF7:
			case 0xF8:
			case 0xF9:
			case 0xFA:
			case 0xFB:
			case 0xFE:
				return true;
			case 0xFC: // Don't override set name
			case 0xFD: // XXX: Probably don't want to override monitor ranges...
			case 0xFF: // XXX: Probably don't want to override serial number...
				return false;
		}
	}
	
	return false;
}

+ (uint32_t)calcGCD:(uint32_t)a b:(uint32_t)b
{
	return (b == 0 ? a : [FixEDID calcGCD:b b:a % b]);
}

+ (NSString *)getAspectRatio:(EDID &)edid
{
	NSString *aspectRatio = @"Ratio N/A";
	DetailedTiming detailedTiming;
	uint32_t hres = 0, vres = 0, gcd = 0;
	
	if ([FixEDID hasPixelTimingType:edid.DetailedTimings[0]])
		detailedTiming = edid.DetailedTimings[0];
	else if ([FixEDID hasPixelTimingType:edid.DetailedTimings[1]])
		detailedTiming = edid.DetailedTimings[1];
	else if ([FixEDID hasPixelTimingType:edid.DetailedTimings[2]])
		detailedTiming = edid.DetailedTimings[2];
	else if ([FixEDID hasPixelTimingType:edid.DetailedTimings[3]])
		detailedTiming = edid.DetailedTimings[3];
	
	hres = (detailedTiming.Data.PixelData.HActiveLo + ((detailedTiming.Data.PixelData.HActiveHBlankHi & 0xF0) << 4));
	vres = (detailedTiming.Data.PixelData.VActiveLo + ((detailedTiming.Data.PixelData.VActiveVBlankHi & 0xF0) << 4));
	
	gcd = [FixEDID calcGCD:hres b:vres];
	
	if (gcd == 0)
		return aspectRatio;
	
	aspectRatio = [NSString stringWithFormat:@"%d:%d", (hres / gcd), (vres / gcd)];
	
	return aspectRatio;
}

// https://comsysto.github.io/Display-Override-PropertyList-File-Parser-and-Generator-with-HiDPI-Support-For-Scaled-Resolutions/
// https://gist.github.com/ejdyksen/8302862
// https://github.com/xzhih/one-key-hidpi
// ---------------------------------------------
// 1. 1080p Display
//    - HiDPI1: 1920x1080 1680x945 1440x810 1280x720 1024x576
// 2. 2K Display
//    - HiDPI1: 2048x1152 1920x1080 1680x945 1440x810 1280x720
//    - HiDPI2: 1024x576
//    - HiDPI3: 960x540
//    - HiDPI4: 2048x1152
// 3. Manual Input Resolution
//    - Auto (HiDPI3 / HiDPI2)
// ---------------------------------------------
// - HiDPI2: 1280x720 960x540 640x360
// - HiDPI3: 840x472 720x405 640x360 576x324 512x288 420x234 400x225 320x180
// - HiDPI4: 1920x1080 1680x945 1440x810 1280x720 1024x576 960x540 640x360
// ---------------------------------------------
// - NonScaled: <xxxxxxxx yyyyyyyy>
// - HiDPI1: <xxxxxxxx yyyyyyyy 00>
// - HiDPI2: <xxxxxxxx yyyyyyyy 00000001 00200000>
// - HiDPI3: <xxxxxxxx yyyyyyyy 00000001>
// - HiDPI4: <xxxxxxxx yyyyyyyy 00000009 00a00000>
// ---------------------------------------------
+ (NSData *)getResolutionData:(uint8_t *)resBytes width:(uint32_t)width height:(uint32_t)height hiDPIType:(HiDPIType)hiDPIType
{
	if (hiDPIType != kNonScaled)
	{
		width *= 2;
		height *= 2;
	}
	
	resBytes[0] = (width >> 24) & 0xFF;
	resBytes[1] = (width >> 16) & 0xFF;
	resBytes[2] = (width >> 8) & 0xFF;
	resBytes[3] = width & 0xFF;
	
	resBytes[4] = (height >> 24) & 0xFF;
	resBytes[5] = (height >> 16) & 0xFF;
	resBytes[6] = (height >> 8) & 0xFF;
	resBytes[7] = height & 0xFF;
	
	resBytes[8] = 0x00;
	resBytes[9] = 0x00;
	resBytes[10] = 0x00;
	resBytes[11] = (hiDPIType == kHiDPI4 ? 0x09 : 0x01);
	
	resBytes[12] = 0x00;
	resBytes[13] = (hiDPIType == kHiDPI4 ? 0xA0 : 0x20);
	resBytes[14] = 0x00;
	resBytes[15] = 0x00;
	
	uint32_t resBytesSize = 0;
	
	switch(hiDPIType)
	{
		case kHiDPI1:
			resBytesSize = 9;
			break;
		case kHiDPI2:
		case kHiDPI4:
			resBytesSize = 16;
			break;
		case kHiDPI3:
			resBytesSize = 12;
			break;
		case kNonScaled:
			resBytesSize = 8;
			break;
		case kAuto:
			return nil;
	}
	
	return [NSData dataWithBytes:resBytes length:resBytesSize];
}

+ (NSMutableArray *)getResolutionArray:(NSArray *)resolutionArray
{
	NSMutableArray *resDataArray = [NSMutableArray array];
	
	for (Resolution *resolution in resolutionArray)
	{
		uint8_t resBytes[16];
		
		if (resolution.type == kAuto)
		{
			//[resDataArray addObject:[FixEDID getResolutionData:resBytes width:resolution.width height:resolution.height hiDPIType:kNonScaled]];
			[resDataArray addObject:[FixEDID getResolutionData:resBytes width:resolution.width height:resolution.height hiDPIType:kHiDPI3]];
			[resDataArray addObject:[FixEDID getResolutionData:resBytes width:resolution.width height:resolution.height hiDPIType:kHiDPI2]];
		}
		else
			[resDataArray addObject:[FixEDID getResolutionData:resBytes width:resolution.width height:resolution.height hiDPIType:resolution.type]];
	}
	
	return resDataArray;
}

+ (void)fixMonitorRanges:(EDID &)edid
{
	BOOL detailsSet = NO;
	
	for (uint32_t i = 0; i < 4; i++)
	{
		if ([FixEDID hasRangeType:edid.DetailedTimings[i]])
		{
			memcpy(&edid.DetailedTimings[i], Monitor_Ranges, sizeof(Monitor_Ranges));
			detailsSet = YES;
			break;
		}
	}
	
	for (uint32_t i = 0; i < 4; i++)
	{
		if ([FixEDID hasOtherType:edid.DetailedTimings[i]])
		{
			memcpy(&edid.DetailedTimings[i], Monitor_Ranges, sizeof(Monitor_Ranges));
			detailsSet = YES;
			break;
		}
	}
	
	if (!detailsSet)
	{
		for (uint32_t i = 3; i >= 0; i--)
		{
			if (![FixEDID hasNameType:edid.DetailedTimings[i]] &&
				![FixEDID hasSerialType:edid.DetailedTimings[i]] &&
				![FixEDID hasRangeType:edid.DetailedTimings[i]])
			{
				memcpy(&edid.DetailedTimings[i], Monitor_Ranges, sizeof(Monitor_Ranges));
				break;
			}
		}
	}
}

+ (void)makeEDID:(EDID &)edid serial:(const uint8_t *)serial chroma:(const uint8_t *)chroma
		baseParams:(const uint8_t *)baseParams detailedTimings:(const uint8_t *)detailedTimings
{
	BOOL detailsSet = NO;
	
	memcpy(&edid.SerialInfo, serial, 10);
	memcpy(&edid.Chroma, chroma, 10);
	memcpy(&edid.BasicParams, baseParams, 5);
	memcpy(&edid.VersionInfo, Version_1_4, sizeof(Version_1_4));
	
	for (uint32_t i = 0; i < 4; i++)
	{
		if ([FixEDID hasNameType:edid.DetailedTimings[i]])
		{
			memcpy(&edid.DetailedTimings[i], detailedTimings, sizeof(DetailedTiming));
			detailsSet = YES;
			break;
		}
	}
	
	for (uint32_t i = 0; i < 4; i++)
	{
		if ([FixEDID hasOtherType:edid.DetailedTimings[i]])
		{
			memcpy(&edid.DetailedTimings[i], detailedTimings, sizeof(DetailedTiming));
			detailsSet = YES;
			break;
		}
	}
	
	if (!detailsSet)
	{
		for (uint32_t i = 3; i >= 0; i--)
		{
			if (![FixEDID hasNameType:edid.DetailedTimings[i]] &&
				![FixEDID hasSerialType:edid.DetailedTimings[i]] &&
				![FixEDID hasRangeType:edid.DetailedTimings[i]])
			{
				memcpy(&edid.DetailedTimings[i], detailedTimings, sizeof(DetailedTiming));
				break;
			}
		}
	}
}

+ (void)makeEDID:(EDID &)edid serial:(const uint8_t *)serial chroma:(const uint8_t *)chroma baseParams:(const uint8_t *)baseParams
	  detailsName:(const uint8_t *)detailsName detailsSerial:(const uint8_t *)detailsSerial
{
	BOOL detailsSet = NO;
	
	memcpy(&edid.SerialInfo, serial, 10);
	memcpy(&edid.Chroma, chroma, 10);
	memcpy(&edid.BasicParams, baseParams, 5);
	memcpy(&edid.VersionInfo, Version_1_4, sizeof(Version_1_4));
	
	for (uint32_t i = 0; i < 4; i++)
	{
		if ([FixEDID hasNameType:edid.DetailedTimings[i]])
		{
			memcpy(&edid.DetailedTimings[i], detailsName, sizeof(DetailedTiming));
			detailsSet = YES;
			break;
		}
	}
	
	for (uint32_t i = 0; i < 4; i++)
	{
		if ([FixEDID hasOtherType:edid.DetailedTimings[i]])
		{
			memcpy(&edid.DetailedTimings[i], detailsName, sizeof(DetailedTiming));
			detailsSet = YES;
			break;
		}
	}
	
	if (!detailsSet)
	{
		for (uint32_t i = 3; i >= 0; i--)
		{
			if (![FixEDID hasNameType:edid.DetailedTimings[i]] &&
				![FixEDID hasSerialType:edid.DetailedTimings[i]] &&
				![FixEDID hasRangeType:edid.DetailedTimings[i]])
			{
				memcpy(&edid.DetailedTimings[i], detailsName, sizeof(DetailedTiming));
				detailsSet = YES;
				break;
			}
		}
	}
	
	detailsSet = NO;
	
	for (uint32_t i = 0; i < 4; i++)
	{
		if ([FixEDID hasSerialType:edid.DetailedTimings[i]])
		{
			memcpy(&edid.DetailedTimings[i], detailsSerial, sizeof(DetailedTiming));
			detailsSet = YES;
			break;
		}
	}
	
	for (uint32_t i = 0; i < 4; i++)
	{
		if ([FixEDID hasOtherType:edid.DetailedTimings[i]])
		{
			memcpy(&edid.DetailedTimings[i], detailsSerial, sizeof(DetailedTiming));
			detailsSet = YES;
			break;
		}
	}
	
	if (!detailsSet)
	{
		for (uint32_t i = 3; i >= 0; i--)
		{
			if (![FixEDID hasNameType:edid.DetailedTimings[i]] &&
				![FixEDID hasSerialType:edid.DetailedTimings[i]] &&
				![FixEDID hasRangeType:edid.DetailedTimings[i]])
			{
				memcpy(&edid.DetailedTimings[i], detailsSerial, sizeof(DetailedTiming));
				detailsSet = YES;
				break;
			}
		}
	}
}

+ (void)makeIOProviderMergeProperties:(NSMutableDictionary **)ioProviderMergeProperties edidData:(NSData *)edidData display:(Display *)display resDataArray:(NSArray *)resDataArray
								   appleSense:(uint32_t)appleSense connectFlags:(const uint8_t *)connectFlags productID:(uint32_t)productID vendorID:(uint32_t) vendorID
{
	NSString *productName = display.name;
	NSString *displayClass = (display.isInternal ? @"AppleBacklightDisplay" : @"AppleDisplay");
	
	if ([resDataArray count] > 0)
		*ioProviderMergeProperties = [NSMutableDictionary dictionaryWithObjectsAndKeys:productName, @"DisplayProductName", @(productID), @"DisplayProductID", @(vendorID), @"DisplayVendorID", @(2), @"AppleDisplayType", @(appleSense), @"AppleSense", edidData, @"IODisplayEDID", [NSData dataWithBytes:connectFlags length:4], @"IODisplayConnectFlags", [[display.prefsKey stringByDeletingLastPathComponent] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%x-%x", displayClass, vendorID, productID]], @"IODisplayPrefsKey", displayClass, @"IOClass", resDataArray, @"scale-resolutions", nil];
	else
		*ioProviderMergeProperties = [NSMutableDictionary dictionaryWithObjectsAndKeys:productName, @"DisplayProductName", @(productID), @"DisplayProductID", @(vendorID), @"DisplayVendorID", @(2), @"AppleDisplayType", @(appleSense), @"AppleSense", edidData, @"IODisplayEDID", [NSData dataWithBytes:connectFlags length:4], @"IODisplayConnectFlags", [[display.prefsKey stringByDeletingLastPathComponent] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%x-%x", displayClass, vendorID, productID]], @"IODisplayPrefsKey", displayClass, @"IOClass", nil];
}

+ (void)makeIOProviderMergeProperties:(NSMutableDictionary **)ioProviderMergeProperties edidData:(NSData *)edidData display:(Display *)display resDataArray:(NSArray *)resDataArray
						   displayGUID:(unsigned long long)displayGUID connectFlags:(const uint8_t *)connectFlags productID:(uint32_t)productID vendorID:(uint32_t)vendorID
{
	NSString *productName = display.name;
	NSString *displayClass = (display.isInternal ? @"AppleBacklightDisplay" : @"AppleDisplay");
	
	if ([resDataArray count] > 0)
		*ioProviderMergeProperties = [NSMutableDictionary dictionaryWithObjectsAndKeys:productName, @"DisplayProductName", @(productID), @"DisplayProductID", @(vendorID), @"DisplayVendorID", @(displayGUID), @"IODisplayGUID", edidData, @"IODisplayEDID", [NSData dataWithBytes:connectFlags length:4], @"IODisplayConnectFlags", [[display.prefsKey stringByDeletingLastPathComponent] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%x-%x", displayClass, vendorID, productID]], @"IODisplayPrefsKey", displayClass, @"IOClass", resDataArray, @"scale-resolutions", nil];
	else
		*ioProviderMergeProperties = [NSMutableDictionary dictionaryWithObjectsAndKeys:productName, @"DisplayProductName", @(productID), @"DisplayProductID", @(vendorID), @"DisplayVendorID", @(displayGUID), @"IODisplayGUID", edidData, @"IODisplayEDID", [NSData dataWithBytes:connectFlags length:4], @"IODisplayConnectFlags", [[display.prefsKey stringByDeletingLastPathComponent] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%x-%x", displayClass, vendorID, productID]], @"IODisplayPrefsKey", displayClass, @"IOClass", nil];
}

+ (void)makeIOProviderMergeProperties:(NSMutableDictionary **)ioProviderMergeProperties edidData:(NSData *)edidData display:(Display *)display resDataArray:(NSArray *)resDataArray
					  capabilityString:(const char *)capabilityString connectFlags:(const uint8_t *)connectFlags controllerID:(const uint8_t *)controllerID
						 firmwareLevel:(const uint8_t *)firmwareLevel mccsVersion:(const uint8_t *)mccsVersion technologyType:(const uint8_t *)technologyType
							appleSense:(uint32_t)appleSense productID:(uint32_t)productID vendorID:(uint32_t)vendorID
{
	NSString *productName = display.name;
	NSString *displayClass = (display.isInternal ? @"AppleBacklightDisplay" : @"AppleDisplay");
	
	if ([resDataArray count] > 0)
		*ioProviderMergeProperties = [NSMutableDictionary dictionaryWithObjectsAndKeys:productName, @"DisplayProductName", @(productID), @"DisplayProductID", @(vendorID), @"DisplayVendorID", @(2), @"AppleDisplayType", @(appleSense), @"AppleSense", edidData, @"IODisplayEDID", [NSData dataWithBytes:capabilityString length:strlen(capabilityString)], @"IODisplayCapabilityString", [NSData dataWithBytes:connectFlags length:4], @"IODisplayConnectFlags", [NSData dataWithBytes:controllerID length:4], @"IODisplayControllerID", [NSData dataWithBytes:firmwareLevel length:4], @"IODisplayFirmwareLevel", [NSData dataWithBytes:mccsVersion length:4], @"IODisplayMCCSVersion", [NSData dataWithBytes:technologyType length:4], @"IODisplayTechnologyType", [[display.prefsKey stringByDeletingLastPathComponent] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%x-%x", displayClass, vendorID, productID]], @"IODisplayPrefsKey", displayClass, @"IOClass", resDataArray, @"scale-resolutions", nil];
	else
		*ioProviderMergeProperties = [NSMutableDictionary dictionaryWithObjectsAndKeys:productName, @"DisplayProductName", @(productID), @"DisplayProductID", @(vendorID), @"DisplayVendorID", @(2), @"AppleDisplayType", @(appleSense), @"AppleSense", edidData, @"IODisplayEDID", [NSData dataWithBytes:capabilityString length:strlen(capabilityString)], @"IODisplayCapabilityString", [NSData dataWithBytes:connectFlags length:4], @"IODisplayConnectFlags", [NSData dataWithBytes:controllerID length:4], @"IODisplayControllerID", [NSData dataWithBytes:firmwareLevel length:4], @"IODisplayFirmwareLevel", [NSData dataWithBytes:mccsVersion length:4], @"IODisplayMCCSVersion", [NSData dataWithBytes:technologyType length:4], @"IODisplayTechnologyType", [[display.prefsKey stringByDeletingLastPathComponent] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%x-%x", displayClass, vendorID, productID]], @"IODisplayPrefsKey", displayClass, @"IOClass", nil];
}

+ (void)makeIOProviderMergeProperties:(NSMutableDictionary **)ioProviderMergeProperties edidData:(NSData *)edidData display:(Display *)display resDataArray:(NSArray *)resDataArray
					  capabilityString:(const char *)capabilityString connectFlags:(const uint8_t *)connectFlags controllerID:(const uint8_t *)controllerID
						 firmwareLevel:(const uint8_t *)firmwareLevel mccsVersion:(const uint8_t *)mccsVersion
							appleSense:(uint32_t)appleSense productID:(uint32_t)productID vendorID:(uint32_t)vendorID
{
	NSString *productName = display.name;
	NSString *displayClass = (display.isInternal ? @"AppleBacklightDisplay" : @"AppleDisplay");
	
	if ([resDataArray count] > 0)
		*ioProviderMergeProperties = [NSMutableDictionary dictionaryWithObjectsAndKeys:productName, @"DisplayProductName", @(productID), @"DisplayProductID", @(vendorID), @"DisplayVendorID", @(2), @"AppleDisplayType", @(appleSense), @"AppleSense", edidData, @"IODisplayEDID", [NSData dataWithBytes:capabilityString length:strlen(capabilityString)], @"IODisplayCapabilityString", [NSData dataWithBytes:connectFlags length:4], @"IODisplayConnectFlags", [NSData dataWithBytes:controllerID length:4], @"IODisplayControllerID", [NSData dataWithBytes:firmwareLevel length:4], @"IODisplayFirmwareLevel", [NSData dataWithBytes:mccsVersion length:4], @"IODisplayMCCSVersion", [NSNumber numberWithBool:YES], @"DisplayParameterHandlerUsesCharPtr", [[display.prefsKey stringByDeletingLastPathComponent] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%x-%x", displayClass, vendorID, productID]], @"IODisplayPrefsKey", displayClass, @"IOClass", resDataArray, @"scale-resolutions", nil];
	else
		*ioProviderMergeProperties = [NSMutableDictionary dictionaryWithObjectsAndKeys:productName, @"DisplayProductName", @(productID), @"DisplayProductID", @(vendorID), @"DisplayVendorID", @(2), @"AppleDisplayType", @(appleSense), @"AppleSense", edidData, @"IODisplayEDID", [NSData dataWithBytes:capabilityString length:strlen(capabilityString)], @"IODisplayCapabilityString", [NSData dataWithBytes:connectFlags length:4], @"IODisplayConnectFlags", [NSData dataWithBytes:controllerID length:4], @"IODisplayControllerID", [NSData dataWithBytes:firmwareLevel length:4], @"IODisplayFirmwareLevel", [NSData dataWithBytes:mccsVersion length:4], @"IODisplayMCCSVersion", [NSNumber numberWithBool:YES], @"DisplayParameterHandlerUsesCharPtr", [[display.prefsKey stringByDeletingLastPathComponent] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%x-%x", displayClass, vendorID, productID]], @"IODisplayPrefsKey", displayClass, @"IOClass", nil];
}

+ (void)makeIOProviderMergeProperties:(NSMutableDictionary **)ioProviderMergeProperties edidData:(NSData *)edidData display:(Display *)display resDataArray:(NSArray *)resDataArray
					  capabilityString:(const char *)capabilityString connectFlags:(const uint8_t *)connectFlags controllerID:(const uint8_t *)controllerID
						 firmwareLevel:(const uint8_t *)firmwareLevel mccsVersion:(const uint8_t *)mccsVersion technologyType:(const uint8_t *)technologyType
							 productID:(uint32_t)productID vendorID:(uint32_t)vendorID displaySerial:(uint32_t)displaySerial
{
	NSString *productName = display.name;
	NSString *displayClass = (display.isInternal ? @"AppleBacklightDisplay" : @"AppleDisplay");
	
	if ([resDataArray count] > 0)
		*ioProviderMergeProperties = [NSMutableDictionary dictionaryWithObjectsAndKeys:productName, @"DisplayProductName", @(productID), @"DisplayProductID", @(vendorID), @"DisplayVendorID", @(displaySerial), @"DisplaySerialNumber", edidData, @"IODisplayEDID", [NSData dataWithBytes:capabilityString length:strlen(capabilityString)], @"IODisplayCapabilityString", [NSData dataWithBytes:connectFlags length:4], @"IODisplayConnectFlags", [NSData dataWithBytes:controllerID length:4], @"IODisplayControllerID", [NSData dataWithBytes:firmwareLevel length:4], @"IODisplayFirmwareLevel", [NSData dataWithBytes:mccsVersion length:4], @"IODisplayMCCSVersion", [NSData dataWithBytes:technologyType length:4], @"IODisplayTechnologyType", [[display.prefsKey stringByDeletingLastPathComponent] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%x-%x", displayClass, vendorID, productID]], @"IODisplayPrefsKey", displayClass, @"IOClass", resDataArray, @"scale-resolutions", nil];
	else
		*ioProviderMergeProperties = [NSMutableDictionary dictionaryWithObjectsAndKeys:productName, @"DisplayProductName", @(productID), @"DisplayProductID", @(vendorID), @"DisplayVendorID", @(displaySerial), @"DisplaySerialNumber", edidData, @"IODisplayEDID", [NSData dataWithBytes:capabilityString length:strlen(capabilityString)], @"IODisplayCapabilityString", [NSData dataWithBytes:connectFlags length:4], @"IODisplayConnectFlags", [NSData dataWithBytes:controllerID length:4], @"IODisplayControllerID", [NSData dataWithBytes:firmwareLevel length:4], @"IODisplayFirmwareLevel", [NSData dataWithBytes:mccsVersion length:4], @"IODisplayMCCSVersion", [NSData dataWithBytes:technologyType length:4], @"IODisplayTechnologyType", [[display.prefsKey stringByDeletingLastPathComponent] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%x-%x", displayClass, vendorID, productID]], @"IODisplayPrefsKey", displayClass, @"IOClass", nil];
}

+ (void)getEDIDOrigData:(Display *)display edidOrigData:(NSData **)edidOrigData
{
	EDID edid {};
	*edidOrigData = display.eDID;
	
	if (edidOrigData != nil)
		return;
	
	switch(display.eDIDIndex)
	{
		case 0: // Display
			memcpy(&edid, iMacRetina_EDID, 128);
			break;
		case 2: // iMac
			memcpy(&edid, iMac_EDID, 128);
			break;
		case 3: // RetinaiMac
			memcpy(&edid, iMacRetina_EDID, 128);
			break;
		case 4: // MacbookPro
			memcpy(&edid, MBP_EDID, 128);
			break;
		case 5: // MacbookAir
			memcpy(&edid, MBA_EDID, 128);
			break;
		case 6: // CinemaHD
			memcpy(&edid, CHD_EDID, 128);
			break;
		case 7: // Thunderbolt
			memcpy(&edid, TDB_EDID, 128);
			break;
		case 8: // LEDCinema
			memcpy(&edid, LED_EDID, 128);
			break;
	}
	
	edid.SerialInfo.VendorID[0] = display.vendorID >> 16;
	edid.SerialInfo.VendorID[1] = display.vendorID & 0xFFFF;
	
	edid.SerialInfo.ProductID[0] = display.productID & 0xFFFF;
	edid.SerialInfo.ProductID[1] = display.productID >> 16;
	
	*edidOrigData = [NSData dataWithBytes:&edid length:128];
}

+ (void)getEDIDData:(Display *)display edidOrigData:(NSData **)edidOrigData edidData:(NSData **)edidData
{
	EDID edid {};

	[self getEDIDOrigData:display edidOrigData:edidOrigData];
	
	if ((*edidOrigData).bytes == nil)
		return;
	
	if ((*edidOrigData).length < sizeof(EDID))
		return;
	
	memcpy(&edid, (*edidOrigData).bytes, sizeof(EDID));
	
	switch(display.eDIDIndex)
	{
		case 0: // Display
			if (display.vendorID != display.vendorIDOverride)
			{
				edid.SerialInfo.VendorID[0] = display.vendorIDOverride >> 16;
				edid.SerialInfo.VendorID[1] = display.vendorIDOverride & 0xFFFF;
			}
			
			if (display.productID != display.productIDOverride)
			{
				edid.SerialInfo.ProductID[0] = display.productIDOverride & 0xFFFF;
				edid.SerialInfo.ProductID[1] = display.productIDOverride >> 16;
			}
			
			if (display.injectAppleVID)
				memcpy(&edid.SerialInfo.VendorID, AppleDisplay_VID, sizeof(AppleDisplay_VID));
			
			if (display.injectApplePID)
				memcpy(&edid.SerialInfo.ProductID, AppleDisplay_PID, sizeof(AppleDisplay_PID));
			
			if (display.forceRGBMode)
				edid.BasicParams.Gamma &= ~(0B11000); // Setting Color Support to RGB 4:4:4 Only
			
			if (display.patchColorProfile)
				memcpy(&edid.Chroma, iMac_Chroma, sizeof(iMac_Chroma));
			
			if (display.fixMonitorRanges)
				[FixEDID fixMonitorRanges:edid];
			
			[FixEDID calcEDIDChecksum:edid];
			break;
		case 2: // iMac
			[FixEDID makeEDID:edid serial:iMac_Serial chroma:iMac_Chroma baseParams:iMac_BasicParams detailedTimings:iMac_Details_Name];
			
			if (display.fixMonitorRanges)
				[FixEDID fixMonitorRanges:edid];
			
			[FixEDID calcEDIDChecksum:edid];
			break;
		case 3: // RetinaiMac
			[FixEDID makeEDID:edid serial:iMacRetina_Serial chroma:iMacRetina_Chroma baseParams:iMacRetina_BasicParams detailedTimings:iMacRetina_Details_Name];
			
			if (display.fixMonitorRanges)
				[FixEDID fixMonitorRanges:edid];
			
			[FixEDID calcEDIDChecksum:edid];
			break;
		case 4: // MacbookPro
			[FixEDID makeEDID:edid serial:MBP_Serial chroma:MBP_Chroma baseParams:MBP_BasicParams detailedTimings:MBP_Details_Name];
			
			if (display.fixMonitorRanges)
				[FixEDID fixMonitorRanges:edid];
			
			[FixEDID calcEDIDChecksum:edid];
			break;
		case 5: // MacbookAir
			[FixEDID makeEDID:edid serial:MBA_Serial chroma:MBA_Chroma baseParams:MBA_BasicParams detailedTimings:MBA_Details_Name];
			
			if (display.fixMonitorRanges)
				[FixEDID fixMonitorRanges:edid];
			
			[FixEDID calcEDIDChecksum:edid];
			break;
		case 6: // CinemaHD
			[FixEDID makeEDID:edid serial:CHD_Serial chroma:CHD_Chroma baseParams:CHD_BasicParams detailsName:CHD_Details_Name detailsSerial:CHD_Details_Serial];
			
			if (display.fixMonitorRanges)
				[FixEDID fixMonitorRanges:edid];
			
			[FixEDID calcEDIDChecksum:edid];
			break;
		case 7: // Thunderbolt
			[FixEDID makeEDID:edid serial:TDB_Serial chroma:TDB_Chroma baseParams:TDB_BasicParams detailsName:TDB_Details_Name detailsSerial:TDB_Details_Serial];
			
			if (display.fixMonitorRanges)
				[FixEDID fixMonitorRanges:edid];
			
			[FixEDID calcEDIDChecksum:edid];
			break;
		case 8: // LEDCinema
			[FixEDID makeEDID:edid serial:LED_Serial chroma:LED_Chroma baseParams:LED_BasicParams detailsName:LED_Details_Name detailsSerial:LED_Details_Serial];
			
			if (display.fixMonitorRanges)
				[FixEDID fixMonitorRanges:edid];
			
			[FixEDID calcEDIDChecksum:edid];
			break;
	}
	
	*edidData = [NSData dataWithBytes:(*edidOrigData).bytes length:(*edidOrigData).length];
	
	memcpy((void *)(*edidData).bytes, &edid, sizeof(EDID));
}

+ (void)makeEDIDFiles:(Display *)display
{
	NSString *displayClass = (display.isInternal ? @"AppleBacklightDisplay" : @"AppleDisplay");
	NSArray *resDataArray = [FixEDID getResolutionArray:display.resolutionsArray];
	NSMutableDictionary *ioProviderMergeProperties = nil;
	NSString *productName = display.name;
	NSNumber *productIDNumber = @0;
	NSNumber *vendorIDNumber = @0;
	NSData *edidOrigData = nil, *edidData = nil;

	[FixEDID getEDIDData:display edidOrigData:&edidOrigData edidData:&edidData];
	
	switch(display.eDIDIndex)
	{
		case 0: // Display
			if ([resDataArray count] > 0)
				ioProviderMergeProperties = [NSMutableDictionary dictionaryWithObjectsAndKeys:productName, @"DisplayProductName", edidData, @"IODisplayEDID", resDataArray, @"scale-resolutions", nil];
			else
				ioProviderMergeProperties = [NSMutableDictionary dictionaryWithObjectsAndKeys:productName, @"DisplayProductName", edidData, @"IODisplayEDID", nil];
			
			productIDNumber = @(display.productIDOverride);
			vendorIDNumber = @(display.vendorIDOverride);
			
#ifdef USE_USBMERGENUB
			if (display.productID != [productIDNumber unsignedIntValue])
				ioProviderMergeProperties[@"DisplayProductID"] = productIDNumber;
			if (display.vendorID != [vendorIDNumber unsignedIntValue])
				ioProviderMergeProperties[@"DisplayVendorID"] = vendorIDNumber;
#endif
			break;
		case 2: // iMac
			[FixEDID makeIOProviderMergeProperties:&ioProviderMergeProperties edidData:edidData display:display resDataArray:resDataArray
								  capabilityString:iMac_CapabilityString connectFlags:iMac_ConnectFlags controllerID:iMac_ControllerID
									 firmwareLevel:iMac_FirmwareLevel mccsVersion:iMac_MCCSVersion technologyType:iMac_TechnologyType
										appleSense:0x073E productID:iMacProductID vendorID:iMacVendorID];
			
			productIDNumber = @(iMacProductID);
			vendorIDNumber = @(iMacVendorID);
			break;
		case 3: // RetinaiMac
			[FixEDID makeIOProviderMergeProperties:&ioProviderMergeProperties edidData:edidData display:display resDataArray:resDataArray
								  capabilityString:iMacRetina_CapabilityString connectFlags:iMacRetina_ConnectFlags controllerID:iMacRetina_ControllerID
									 firmwareLevel:iMacRetina_FirmwareLevel mccsVersion:iMacRetina_MCCSVersion
										appleSense:0x073E productID:iMacRetinaProductID vendorID:iMacRetinaVendorID];
			
			productIDNumber = @(iMacRetinaProductID);
			vendorIDNumber = @(iMacRetinaVendorID);
			break;
		case 4: // MacbookPro
			[FixEDID makeIOProviderMergeProperties:&ioProviderMergeProperties edidData:edidData display:display resDataArray:resDataArray
									   displayGUID:0x610000000000000ULL connectFlags:MBP_ConnectFlags productID:MBPProductID vendorID:MBPVendorID];
			
			productIDNumber = @(MBPProductID);
			vendorIDNumber = @(MBPVendorID);
			break;
		case 5: // MacbookAir
			[FixEDID makeIOProviderMergeProperties:&ioProviderMergeProperties edidData:edidData display:display resDataArray:resDataArray
									   displayGUID:0x610000000000000ULL connectFlags:MBA_ConnectFlags  productID:MBAProductID vendorID:MBAVendorID];
			
			productIDNumber = @(MBAProductID);
			vendorIDNumber = @(MBAVendorID);
			break;
		case 6: // CinemaHD
			[FixEDID makeIOProviderMergeProperties:&ioProviderMergeProperties edidData:edidData display:display resDataArray:resDataArray
										appleSense:0x9000 connectFlags:CHD_ConnectFlags productID:CHDProductID vendorID:CHDVendorID];
			
			productIDNumber = @(CHDProductID);
			vendorIDNumber = @(CHDVendorID);
			break;
		case 7: // Thunderbolt
			[FixEDID makeIOProviderMergeProperties:&ioProviderMergeProperties edidData:edidData display:display resDataArray:resDataArray
								  capabilityString:TDB_CapabilityString connectFlags:TDB_ConnectFlags controllerID:TDB_ControllerID
									 firmwareLevel:TDB_FirmwareLevel mccsVersion:TDB_MCCSVersion technologyType:TDB_TechnologyType
										 productID:TDBProductID vendorID:TDBVendorID displaySerial:0x1623001F];
			
			productIDNumber = @(TDBProductID);
			vendorIDNumber = @(TDBVendorID);
			break;
		case 8: // LEDCinema
			[FixEDID makeIOProviderMergeProperties:&ioProviderMergeProperties edidData:edidData display:display resDataArray:resDataArray
										appleSense:0x073E connectFlags:LED_ConnectFlags productID:LEDProductID vendorID:LEDVendorID];
			
			productIDNumber = @(LEDProductID);
			vendorIDNumber = @(LEDVendorID);
			break;
	}

	NSDictionary *edidOverride;
	
	if ([resDataArray count] > 0)
		edidOverride = [NSDictionary dictionaryWithObjectsAndKeys:productName, @"DisplayProductName", productIDNumber, @"DisplayProductID", vendorIDNumber, @"DisplayVendorID", edidData, @"IODisplayEDID", resDataArray, @"scale-resolutions", nil];
	else
		edidOverride = [NSDictionary dictionaryWithObjectsAndKeys:productName, @"DisplayProductName", productIDNumber, @"DisplayProductID", vendorIDNumber, @"DisplayVendorID", edidData, @"IODisplayEDID", nil];
	
	NSString *desktopPath = [NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES) objectAtIndex:0];
#ifdef USE_USBMERGENUB
	NSString *driverName = [NSString stringWithFormat:@"Display-%x-%x.kext", display.vendorID, display.productID];
#else
	NSString *driverName = @"DisplayMergeNub.kext";
#endif
	NSString *driverPath = nil;
	NSString *driverBinCSTarget = nil;
	NSString *driverBinPath = nil;
	NSString *driverBinResPath = nil;
	NSString *driverInfoPath = nil;
	NSError *err;
	NSAlert *alert;
	NSString *errorstring;
	
#if MAC_OS_X_VERSION_MIN_REQUIRED >= 1050
	driverPath = [desktopPath stringByAppendingPathComponent:driverName];
	driverPath = [driverPath stringByAppendingPathComponent:@"Contents"];
	driverBinCSTarget = [driverPath stringByAppendingPathComponent:@"_CodeSignature"];
	driverBinPath = [driverPath stringByAppendingPathComponent:@"MacOS"];
	driverInfoPath = [driverPath stringByAppendingPathComponent:@"Info.plist"];
	
#ifdef USE_USBMERGENUB
	if ([[NSFileManager defaultManager] createDirectoryAtPath:driverPath withIntermediateDirectories:YES attributes:nil error:&err] == NO)
#else
	if ([[NSFileManager defaultManager] createDirectoryAtPath:driverBinPath withIntermediateDirectories:YES attributes:nil error:&err] == NO)
#endif
	{
		errorstring = [err localizedDescription];
		errorstring = [errorstring stringByAppendingString:@"\n"];
		errorstring = [errorstring stringByAppendingString:[err localizedFailureReason]];
		
		alert = [[NSAlert alloc] init];
		[alert addButtonWithTitle:GetLocalizedString(@"OK")];
		[alert setIcon:[[NSApplication sharedApplication] applicationIconImage]];
		[alert setMessageText:GetLocalizedString(@"Error occured while making kext path!")];
		[alert setInformativeText:errorstring];
		[alert runModal];
		[alert release];
	}
#else
	driverPath = [desktopPath stringByAppendingPathComponent:@"DisplayMergeNub.kext"];
	[[NSFileManager defaultManager] createDirectoryAtPath:driverPath attributes:nil];
	driverPath = [driverPath stringByAppendingPathComponent:@"Contents"];
	[[NSFileManager defaultManager] createDirectoryAtPath:driverPath attributes:nil];
	driverBinCSTarget = [driverPath stringByAppendingPathComponent:@"_CodeSignature"];
	driverBinPath = [driverPath stringByAppendingPathComponent:@"MacOS"];
#ifndef USE_USBMERGENUB
	[[NSFileManager defaultManager] createDirectoryAtPath:driverBinPath attributes:nil];
#endif
	driverBinResPath = [driverBinPath stringByAppendingPathComponent:@"DisplayMergeNub"];
	driverPath = [driverPath stringByAppendingPathComponent:@"Info.plist"];
#endif
	
#ifndef USE_USBMERGENUB
	char copyPath[512];
	char copyCSPath[512];
	driverBinResPath = [[NSBundle mainBundle] resourcePath];
	driverBinResPath = [driverBinResPath stringByAppendingPathComponent:@"DisplayMergeNub"];
	NSString *driverBinCSPath = [driverBinResPath stringByAppendingPathComponent:@"_CodeSignature"];
	driverBinResPath = [driverBinResPath stringByAppendingPathComponent:@"DisplayMergeNub"];
	
	snprintf(copyPath, sizeof(copyPath), "/bin/cp -f \"%s\" \"%s\"", [driverBinResPath cStringUsingEncoding:NSUTF8StringEncoding], [driverBinPath cStringUsingEncoding:NSUTF8StringEncoding]);
	system(copyPath);
	
	snprintf(copyCSPath, sizeof(copyPath), "/bin/cp -Rf \"%s\" \"%s\"", [driverBinCSPath cStringUsingEncoding:NSUTF8StringEncoding], [driverBinCSTarget cStringUsingEncoding:NSUTF8StringEncoding]);
	system(copyCSPath);
#endif
	
	NSString *edidOrigBinPath = [desktopPath stringByAppendingPathComponent:[NSString stringWithFormat:@"EDID-%x-%x-orig", display.vendorID, display.productID]];
	NSString *edidBinPath = [desktopPath stringByAppendingPathComponent:[NSString stringWithFormat:@"EDID-%x-%x", display.vendorID, display.productID]];
	
	edidOrigBinPath = [edidOrigBinPath stringByAppendingPathExtension:@"bin"];
	edidBinPath = [edidBinPath stringByAppendingPathExtension:@"bin"];
	
	NSString *newDisplayOverridePath = [desktopPath stringByAppendingPathComponent:[NSString stringWithFormat:@"DisplayVendorID-%x", display.vendorID]];
	
#if MAC_OS_X_VERSION_MIN_REQUIRED >= 1050
	if ([[NSFileManager defaultManager] createDirectoryAtPath:newDisplayOverridePath withIntermediateDirectories:YES attributes:nil error:&err] == NO)
	{
		errorstring = [err localizedDescription];
		errorstring = [errorstring stringByAppendingString:@"\n"];
		errorstring = [errorstring stringByAppendingString:[err localizedFailureReason]];
		
		alert = [[NSAlert alloc] init];
		[alert addButtonWithTitle:GetLocalizedString(@"OK")];
		[alert setIcon:[[NSApplication sharedApplication] applicationIconImage]];
		[alert setMessageText:GetLocalizedString(@"Error occured while making displayoverride path!")];
		[alert setInformativeText:errorstring];
		[alert runModal];
		[alert release];
	}
#else
	[[NSFileManager defaultManager] createDirectoryAtPath:newDisplayOverridePath attributes:nil];
#endif
	
	newDisplayOverridePath = [newDisplayOverridePath stringByAppendingPathComponent:[NSString stringWithFormat:@"DisplayProductID-%x", display.productID]];
	
	[edidOverride writeToFile:newDisplayOverridePath atomically:YES];
	[edidOrigData writeToFile:edidOrigBinPath atomically:YES];
	[edidData writeToFile:edidBinPath atomically:YES];
	
#ifdef USE_USBMERGENUB
	[ioProviderMergeProperties removeObjectForKey:@"IOClass"];
	NSDictionary *monInjection = [NSDictionary dictionaryWithObjectsAndKeys:@"com.apple.driver.AppleUSBMergeNub", @"CFBundleIdentifier", @"AppleUSBMergeNub", @"IOClass", displayClass, @"IOProviderClass", @(5000), @"IOProbeScore", @(display.productID), @"DisplayProductID", @(display.vendorID), @"DisplayVendorID", ioProviderMergeProperties, @"IOProviderMergeProperties", nil];
#else
	NSDictionary *monInjection = [NSDictionary dictionaryWithObjectsAndKeys:@"com.AnV.Software.driver.AppleMonitor", @"CFBundleIdentifier", @"DisplayMergeNub", @"IOClass", displayClass, @"IOProviderClass", @(display.productID), @"DisplayProductID", @(display.vendorID), @"DisplayVendorID", @(display.ignoreDisplayPrefs), @"IgnoreDisplayPrefs", display.prefsKey, @"IODisplayPrefsKey", ioProviderMergeProperties, @"IOProviderMergeProperties", nil];
#endif
	NSDictionary *ioKitPersonalities = [NSDictionary dictionaryWithObjectsAndKeys:monInjection, @"Monitor Apple ID Injection", nil];
#ifdef USE_USBMERGENUB
	NSDictionary *driverDict = [NSDictionary dictionaryWithObjectsAndKeys:@"English", @"CFBundleDevelopmentRegion", @"com.AnV.Software.driver.AppleMonitor", @"CFBundleIdentifier", @"6.0", @"CFBundleInfoDictionaryVersion", @"Display Injector", @"CFBundleName", @"KEXT", @"CFBundlePackageType", @"????", @"CFBundleSignature", @"9.9.9", @"CFBundleVersion", @"Copyright (C) 2013 AnV Software", @"CFBundleGetInfoString", ioKitPersonalities, @"IOKitPersonalities", @"Root", @"OSBundleRequired", nil];
#else
	NSDictionary *osBundleLibraries = [NSDictionary dictionaryWithObjectsAndKeys:@"8.0.0b1", @"com.apple.kpi.bsd", @"8.0.0b1", @"com.apple.kpi.iokit", @"8.0.0b1", @"com.apple.kpi.libkern", nil];
	NSDictionary *driverDict = [NSDictionary dictionaryWithObjectsAndKeys:@"English", @"CFBundleDevelopmentRegion", @"com.AnV.Software.driver.AppleMonitor", @"CFBundleIdentifier", @"DisplayMergeNub", @"CFBundleExecutable", @"6.0", @"CFBundleInfoDictionaryVersion", @"Display Injector", @"CFBundleName", @"KEXT", @"CFBundlePackageType", @"????", @"CFBundleSignature", @"9.9.9", @"CFBundleVersion", @"9.9.9", @"CFBundleShortVersionString", @"Copyright (C) 2013 AnV Software", @"CFBundleGetInfoString", @"", @"DTCompiler", @"4G2008a", @"DTPlatformBuild", @"GM", @"DTPlatformVersion", @"12C37", @"DTSDKBuild", @"Custom", @"DTSDKName", @"0452", @"DTXcode" , @"4G2008a", @"DTXcodeBuild", osBundleLibraries, @"OSBundleLibraries", ioKitPersonalities, @"IOKitPersonalities", @"Root", @"OSBundleRequired", @"8.8.8", @"OSBundleCompatibleVerson", nil];
#endif
	
	[driverDict writeToFile:driverInfoPath atomically:YES];
	
	NSString *displayEDIDKextPath = [desktopPath stringByAppendingPathComponent:driverName];
	
	NSArray *fileURLs = [NSArray arrayWithObjects:[NSURL fileURLWithPath:displayEDIDKextPath], nil];
	[[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:fileURLs];
}

+ (void)createDisplayIcons:(NSArray *)displaysArray
{
	NSString *desktopPath = [NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES) objectAtIndex:0];
	NSString *srcIconPlistPath = @"/System/Library/Displays/Contents/Resources/Overrides/Icons.plist";
	NSString *dstIconPlistPath =  [desktopPath stringByAppendingPathComponent:@"Icons.plist"];
	NSDictionary *iconPlistDictionary = [NSDictionary dictionaryWithContentsOfFile:srcIconPlistPath];
	NSMutableDictionary *vendorsDictionary = [iconPlistDictionary objectForKey:@"vendors"];
	
	for (Display *display in displaysArray)
	{
		NSString *picon = nil;
		NSString *dicon = nil;
		uint32_t iconX = 0, iconY = 0, iconWidth = 0, iconHeight = 0;
		
		switch (display.iconIndex)
		{
			case 0: // Default
				[vendorsDictionary removeObjectForKey:[NSString stringWithFormat:@"%x", display.vendorID]];
				continue;
			case 1: // iMac
				picon = @"/System/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-610/DisplayProductID-a032.tiff";
				dicon = @"com.apple.cinema-display";
				iconX = 33;
				iconY = 68;
				iconWidth = 160;
				iconHeight = 90;
				break;
			case 2: // MacBook
				picon = @"/System/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-610/DisplayProductID-a030-e1e1df.tiff";
				dicon = @"com.apple.cinema-display";
				iconX = 52;
				iconY = 66;
				iconWidth = 122;
				iconHeight = 76;
				break;
			case 3: // MacBook Pro
				picon = @"/System/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-610/DisplayProductID-a028-9d9da0.tiff";
				dicon = @"com.apple.cinema-display";
				iconX = 40;
				iconY = 62;
				iconWidth = 147;
				iconHeight = 92;
				break;
			case 4: // LG Display
				picon = @"/System/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-1e6d/DisplayProductID-5b11.tiff";
				dicon = @"/System/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-1e6d/DisplayProductID-5b11.icns";
				iconX = 11;
				iconY = 47;
				iconWidth = 202;
				iconHeight = 114;
				break;
		}
		
		NSDictionary *iconDictionary = [NSDictionary dictionaryWithObjectsAndKeys:picon, @"display-resolution-preview-icon", @(iconX), @"resolution-preview-x", @(iconY), @"resolution-preview-y", @(iconWidth), @"resolution-preview-width", @(iconHeight), @"resolution-preview-height", dicon, @"display-icon", nil];
		NSDictionary *productsDictionary = [NSDictionary dictionaryWithObjectsAndKeys:iconDictionary, [NSString stringWithFormat:@"%x", display.productID], nil];
		[vendorsDictionary setObject:productsDictionary forKey:[NSString stringWithFormat:@"%x", display.vendorID]];
	}
	
	[iconPlistDictionary writeToFile:dstIconPlistPath atomically:YES];
}

@end
