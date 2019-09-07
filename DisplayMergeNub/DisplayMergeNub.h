#ifndef _IOKIT_DisplayMergeNub_H
#define _IOKIT_DisplayMergeNub_H

#include <IOKit/IOService.h>

class DisplayMergeNub : public IOService
{
    OSDeclareDefaultStructors(DisplayMergeNub)
    
public:
    IOService *			probe(IOService *provider, SInt32 *score) override;
    bool                start(IOService *provider) override;
    virtual bool 		MergeDictionaryIntoProvider(IOService *  provider, OSDictionary *  mergeDict);
    virtual bool		MergeDictionaryIntoDictionary(OSDictionary *  sourceDictionary,  OSDictionary *  targetDictionary);

};
    
#endif
