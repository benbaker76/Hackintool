//
//  Authorization.h
//  Hackintool
//
//  Created by Ben Baker on 1/29/19.
//  Copyright © 2019 Ben Baker. All rights reserved.
//

#ifndef Authorization_h
#define Authorization_h

typedef void (*AuthorizationGrantedCallback)(AuthorizationRef __nullable authorization, OSErr status, void * __nullable context);

void initAuthorization(AuthorizationGrantedCallback _Nonnull callback, void * __nullable context);
OSErr getAuthorization(AuthorizationRef _Nonnull*_Nonnull authorization);
OSErr requestAdministratorRights();
void callAuthorizationGrantedCallback(OSErr status);
OSErr freeAuthorization();

#endif /* Authorization_hpp */
