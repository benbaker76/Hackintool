//
//  MacSerialBridge.h
//  Hackintool
//
//  Accessors for macserial's model and location tables, which are static
//  arrays that Swift can't reach directly.
//

#ifndef MacSerialBridge_h
#define MacSerialBridge_h

#include <stddef.h>
#include <stdint.h>
#include "macserial.h"

/// Number of Mac models macserial knows (APPLE_MODEL_MAX).
int32_t macserial_model_count(void);

/// Model identifier ("iMac19,1") for a model index, or NULL.
const char *macserial_product_name(int32_t modelIndex);

/// Manufacturing location name for the indices in SERIALINFO, or NULL.
const char *macserial_location_name(int32_t legacyCountryIndex, int32_t modernCountryIndex);

/// A SERIALINFO with the "unknown" markers macserial expects.
SERIALINFO macserial_empty_info(void);

#endif /* MacSerialBridge_h */
