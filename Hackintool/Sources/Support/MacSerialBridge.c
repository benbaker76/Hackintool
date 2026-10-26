//
//  MacSerialBridge.c
//  Hackintool
//

#include "MacSerialBridge.h"
#include "modelinfo.h"

int32_t macserial_model_count(void)
{
	return APPLE_MODEL_MAX;
}

const char *macserial_product_name(int32_t modelIndex)
{
	if (modelIndex < 0 || modelIndex >= APPLE_MODEL_MAX)
		return NULL;

	return ApplePlatformData[modelIndex].productName;
}

const char *macserial_location_name(int32_t legacyCountryIndex, int32_t modernCountryIndex)
{
	if (legacyCountryIndex >= 0 && legacyCountryIndex < (int32_t)ARRAY_SIZE(AppleLegacyLocationNames))
		return AppleLegacyLocationNames[legacyCountryIndex];

	if (modernCountryIndex >= 0 && modernCountryIndex < (int32_t)ARRAY_SIZE(AppleLocationNames))
		return AppleLocationNames[modernCountryIndex];

	return NULL;
}

SERIALINFO macserial_empty_info(void)
{
	SERIALINFO info = {
		.modelIndex  = -1,
		.decodedYear = -1,
		.decodedWeek = -1,
		.decodedCopy = -1,
		.decodedLine = -1,
		.legacyCountryIdx = -1,
		.modernCountryIdx = -1,
	};

	return info;
}
