//
//  Hackintool-Bridging-Header.h
//  Hackintool
//
//  C and C++ code exposed to Swift. Everything else in the app is Swift.
//

#ifndef Hackintool_Bridging_Header_h
#define Hackintool_Bridging_Header_h

// GfxUtil: EFI device path parsing.
#include <IOKit/IOKitLib.h>
#include "efidevp.h"

// MacSerial: serial number decoding and generation.
#include "MacSerialBridge.h"

// VDADecoderChecker (C++): hardware H.264 decode support.
#include "VDADecoderBridge.h"

#endif /* Hackintool_Bridging_Header_h */
