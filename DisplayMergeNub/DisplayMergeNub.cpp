/*
 * Copyright � 1998-2012 Apple Inc.  All rights reserved.
 * 
 * @APPLE_LICENSE_HEADER_START@
 * 
 * This file contains Original Code and/or Modifications of Original Code
 * as defined in and that are subject to the Apple Public Source License
 * Version 2.0 (the 'License'). You may not use this file except in
 * compliance with the License. Please obtain a copy of the License at
 * http://www.opensource.apple.com/apsl/ and read it before using this
 * file.
 * 
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
 * Please see the License for the specific language governing rights and
 * limitations under the License.
 * 
 * @APPLE_LICENSE_HEADER_END@
 */


#include <IOKit/IOKitKeys.h>
#include <IOKit/IOLib.h>

#include "DisplayMergeNub.h"
OSDefineMetaClassAndStructors(DisplayMergeNub, IOService)

static bool haveCreatedRef = false;

bool
DisplayMergeNub::start(IOService *provider)
{
	extern kmod_info_t kmod_info;
	
    IOLog("%s %s\n", kmod_info.name, kmod_info.version);
    IOLog("Copyright © 2013-2014 AnV Software\n");

    return (true);
}

//================================================================================================
//
//  probe()
//
//  This is a special Display driver which will always fail to probe. However, the probe
//  will have a side effect, which is that it merge a property dictionary into his provider's
//  parent NUB in the IOService if the device and vendor match
//
//================================================================================================
//
IOService *
DisplayMergeNub::probe(IOService *provider, SInt32 *score)
{
#pragma unused (score)
    OSDictionary *providerDict = (OSDictionary*)getProperty("IOProviderMergeProperties");
    OSNumber *providerVendor = (OSNumber*)provider->getProperty("DisplayVendorID");
    OSNumber *providerDevice = (OSNumber*)provider->getProperty("DisplayProductID");
    OSString *providerDisplayPrefs = (OSString*)provider->getProperty("IODisplayPrefsKey");
    OSNumber *vendorValue = (OSNumber*)getProperty("DisplayVendorID");
    OSNumber *deviceValue = (OSNumber*)getProperty("DisplayProductID");
    OSString *displayPrefs = (OSString*)getProperty("IODisplayPrefsKey");
    OSBoolean *ignoreDisplayPrefs = (OSBoolean*)getProperty("IgnoreDisplayPrefs");
    OSString *displayOverrideClass = (OSString*)providerDict->getObject("IOClass");

    if ((providerDict) && (providerVendor->unsigned64BitValue() == vendorValue->unsigned64BitValue()) && (providerDevice->unsigned64BitValue() == deviceValue->unsigned64BitValue()))
    {
          //   provider->getPropertyTable()->merge(providerDict);		// merge will verify that this really is a dictionary
        if ((!strncmp(providerDisplayPrefs->getCStringNoCopy(), displayPrefs->getCStringNoCopy(), providerDisplayPrefs->getLength())) || (ignoreDisplayPrefs->isTrue()))
        {
            if (displayOverrideClass)
            {
                provider->setName(displayOverrideClass->getCStringNoCopy());
            }

            MergeDictionaryIntoProvider( provider, providerDict);
        }
    }
    
    return (NULL);								// always fail the probe!
}

//================================================================================================
//
//  MergeDictionaryIntoProvider
//
//  We will iterate through the dictionary that we want to merge into our provider.  If
//  the dictionary entry is not an OSDictionary, we will set that property into our provider.  If it is a
//  OSDictionary, we will get our provider's entry and merge our entry into it, recursively.
//
//================================================================================================
//
bool
DisplayMergeNub::MergeDictionaryIntoProvider(IOService * provider, OSDictionary * dictionaryToMerge)
{
    const OSSymbol * 		dictionaryEntry = NULL;
    OSCollectionIterator * 	iter = NULL;
    bool			result = false;

    if (!provider || !dictionaryToMerge)
        return (false);

	//
	// rdar://4041566 -- Trick the C++ run-time into keeping us loaded.
	//
	if (haveCreatedRef == false) 
	{
		haveCreatedRef = true;
		getMetaClass()->instanceConstructed();
	}
	
    // Get the dictionary whose entries we need to merge into our provider and get
    // an iterator to it.
    //
    iter = OSCollectionIterator::withCollection((OSDictionary *)dictionaryToMerge);
    if ( iter != NULL )
    {
        // Iterate through the dictionary until we run out of entries
        //
        while ( NULL != (dictionaryEntry = (const OSSymbol *)iter->getNextObject()) )
        {
            const char *	str = NULL;
            OSDictionary *	sourceDictionary = NULL;
            OSDictionary *	providerDictionary = NULL;
            OSObject *		providerProperty = NULL;

            // Get the symbol name for debugging
            //
            str = dictionaryEntry->getCStringNoCopy();

            // Check to see if our destination already has the same entry.  If it does
            // we assume that it is a dictionary.  Perhaps we should check that
            //
            providerProperty = provider->getProperty(dictionaryEntry);
            if ( providerProperty )
            {
                providerDictionary = OSDynamicCast(OSDictionary, providerProperty);
            }

            // See if our source entry is also a dictionary
            //
            sourceDictionary = OSDynamicCast(OSDictionary, dictionaryToMerge->getObject(dictionaryEntry));

            if ( providerDictionary &&  sourceDictionary )
            {
                // Need to merge our entry into the provider's dictionary.  However, we don't have a copy of our dictionary, just
                // a reference to it.  So, we need to make a copy of our provider's dictionary
                //
                OSDictionary *		localCopyOfProvidersDictionary;
                UInt32			providerSize;
                UInt32			providerSizeAfterMerge;

                localCopyOfProvidersDictionary = OSDictionary::withDictionary( providerDictionary, 0);
                if ( localCopyOfProvidersDictionary == NULL )
                {
                    break;
                }

                // Get the size of our provider's dictionary so that we can check later whether it changed
                //
                providerSize = providerDictionary->getCapacity();

                // Note that our providerDictionary *might* change
                // between the time we copied it and when we write it out again.  If so, we will obviously overwrite anychanges
                //
                result = MergeDictionaryIntoDictionary(  sourceDictionary, localCopyOfProvidersDictionary);

                if ( result )
                {
                    // Get the size of our provider's dictionary so to see if it's changed  (Yes, the size could remain the same but the contents
                    // could have changed, but this gives us a first approximation.  We're not doing anything with this result, although we could
                    // remerge
                    //
                    providerSizeAfterMerge = providerDictionary->getCapacity();

                    result = provider->setProperty( dictionaryEntry, localCopyOfProvidersDictionary );
                    if ( !result )
                    {
                        break;
                    }
                }
                else
                {
                    // If we got an error merging dictionaries, then just bail out without doing anything
                    //
                    break;
                }
           }
            else
            {
                result = provider->setProperty(dictionaryEntry, dictionaryToMerge->getObject(dictionaryEntry));
                if ( !result )
                {
                    break;
                }
            }
        }
        iter->release();
    }
    return (result);
}


//================================================================================================
//
//  MergeDictionaryIntoDictionary( parentSourceDictionary, parentTargetDictionary)
//
//  This routine will merge the contents of parentSourceDictionary into the targetDictionary, recursively.
//  Note that we are only modifying copies of the parentTargetDictionary, so we don't expect anybody
//  else to be accessing them at the same time.
//
//================================================================================================
//
bool
DisplayMergeNub::MergeDictionaryIntoDictionary(OSDictionary * parentSourceDictionary,  OSDictionary * parentTargetDictionary)
{
    OSCollectionIterator*	srcIterator = NULL;
    OSSymbol*			keyObject = NULL ;
    bool			result = false;

    if (!parentSourceDictionary || !parentTargetDictionary)
        return (false);

    // Get our source dictionary
    //
    srcIterator = OSCollectionIterator::withCollection(parentSourceDictionary) ;

    while (NULL != (keyObject = OSDynamicCast(OSSymbol, srcIterator->getNextObject())))
    {
        const char *	str;
        OSDictionary *	childSourceDictionary = NULL;
        OSDictionary *	childTargetDictionary = NULL;
        OSObject *	childTargetObject = NULL;

        // Get the symbol name for debugging
        //
        str = keyObject->getCStringNoCopy();

        // Check to see if our destination already has the same entry.
        //
        childTargetObject = parentTargetDictionary->getObject(keyObject);
        if ( childTargetObject )
        {
            childTargetDictionary = OSDynamicCast(OSDictionary, childTargetObject);
        }

        // See if our source entry is also a dictionary
        //
        childSourceDictionary = OSDynamicCast(OSDictionary, parentSourceDictionary->getObject(keyObject));

        if ( childTargetDictionary && childSourceDictionary)
        {
            // Our target dictionary already has the entry for this same object AND our
            // source is also a dictionary, so we need to recursively add it.
            //
			// Need to merge our entry into the provider's dictionary.  However, we don't have a copy of our dictionary, just
			// a reference to it.  So, we need to make a copy of our target's dictionary
			//
			OSDictionary *		localCopyOfTargetDictionary;
			UInt32			targetSize;
			UInt32			targetSizeAfterMerge;
			
			localCopyOfTargetDictionary = OSDictionary::withDictionary( childTargetDictionary, 0);
			if ( localCopyOfTargetDictionary == NULL )
			{
				break;
			}
			
			// Get the size of our provider's dictionary so that we can check later whether it changed
			//
			targetSize = childTargetDictionary->getCapacity();
			
			// Note that our targetDictionary *might* change
			// between the time we copied it and when we write it out again.  If so, we will obviously overwrite anychanges
			//
            result = MergeDictionaryIntoDictionary(childSourceDictionary, localCopyOfTargetDictionary) ;
			if ( result )
			{
				// Get the size of our provider's dictionary so to see if it's changed  (Yes, the size could remain the same but the contents
				// could have changed, but this gives us a first approximation.  We're not doing anything with this result, although we could
				// remerge
				//
				targetSizeAfterMerge = childTargetDictionary->getCapacity();
				
				result = parentTargetDictionary->setObject(keyObject, localCopyOfTargetDictionary);
				if ( !result )
				{
					break;
				}
			}
			else
			{
				// If we got an error merging dictionaries, then just bail out without doing anything
				//
				break;
			}
        }
        else
        {
            // We have a property that we need to merge into our parent dictionary.
            //
            result = parentTargetDictionary->setObject(keyObject, parentSourceDictionary->getObject(keyObject)) ;
            if ( !result )
            {
                break;
            }
        }

    }

    srcIterator->release();

    return (result);
}
