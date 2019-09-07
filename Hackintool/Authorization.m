//
//  Authorization.m
//  Hackintool
//
//  Created by Ben Baker on 1/29/19.
//  Copyright © 2019 Ben Baker. All rights reserved.
//

#include "Authorization.h"

AuthorizationRef m_authorization = nil;
AuthorizationGrantedCallback m_callback = nil;
void *m_context = nil;
bool m_authorizationGranted = NO;

void initAuthorization(AuthorizationGrantedCallback callback, void * __nullable context)
{
	m_callback = callback;
	m_context = context;
}

OSErr getAuthorization(AuthorizationRef *authorization)
{
	if (m_authorization != nil)
	{
		*authorization = m_authorization;
		
		return errAuthorizationSuccess;
	}
	
	OSErr status = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment, kAuthorizationFlagDefaults, &m_authorization);
	
	if (status != errAuthorizationSuccess)
		return status;
	
	*authorization = m_authorization;
	
	return errAuthorizationSuccess;
}

OSErr requestAdministratorRights()
{
	OSErr status;
	AuthorizationRef authorization = NULL;
	
	if ((status = getAuthorization(&authorization)) != errAuthorizationSuccess)
		return status;
	
	AuthorizationItem adminAuthorization = { "system.privilege.admin", 0, NULL, 0 };
	AuthorizationRights rightSet = { 1, &adminAuthorization };
	
	status = AuthorizationCopyRights(m_authorization, &rightSet, kAuthorizationEmptyEnvironment, kAuthorizationFlagPreAuthorize | kAuthorizationFlagInteractionAllowed | kAuthorizationFlagExtendRights, NULL);
	
	callAuthorizationGrantedCallback(status);
	
	return status;
}

void callAuthorizationGrantedCallback(OSErr status)
{
	if (status != 0)
		return;
	
	if (m_callback == nil)
		return;
	
	if (m_authorizationGranted)
		return;
	
	m_authorizationGranted = YES;
	
	dispatch_async(dispatch_get_main_queue(), ^{
		m_callback(m_authorization, status, m_context);
	});
}

OSErr freeAuthorization()
{
	if (m_authorization == nil)
		return errAuthorizationSuccess;
	
	//return AuthorizationFree(m_authorization, kAuthorizationFlagDefaults);
	return AuthorizationFree(m_authorization, kAuthorizationFlagDestroyRights);
}
