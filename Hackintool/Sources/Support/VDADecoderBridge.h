//
//  VDADecoderBridge.h
//  Hackintool
//
//  The one function Swift needs from VDADecoderChecker.cpp. The checker's own header
//  imports VideoDecodeAcceleration, which Swift can't import.
//

#ifndef VDADecoderBridge_h
#define VDADecoderBridge_h

#include <MacTypes.h>

/// Tries to create a hardware H.264 decoder; returns a kVDADecoder status (0 = supported).
OSStatus CreateDecoder(void);

#endif /* VDADecoderBridge_h */
