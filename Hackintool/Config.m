//
//  Config.m
//  Hackintool
//
//  Created by Ben Baker on 1/29/19.
//  Copyright © 2019 Ben Baker. All rights reserved.
//

#include "Config.h"
#include "IORegTools.h"
#include "MiscTools.h"
#include "IORegTools.h"
#include "DiskUtilities.h"
#include "Disk.h"
#include <CoreFoundation/CoreFoundation.h>

#define GetLocalizedString(key) \
[[NSBundle mainBundle] localizedStringForKey:(key) value:@"" table:nil]

@implementation Config

+ (bool)mountBootEFI:(AppDelegate *)appDelegate efiVolumeURL:(NSURL **)efiVolumeURL
{
	Disk *efiBootDisk;
	
	if (!tryGetEFIBootDisk(appDelegate.disksArray, &efiBootDisk))
		return false;
	
	if ([efiBootDisk.volumePath path] != nil)
	{
		*efiVolumeURL = efiBootDisk.volumePath;
		
		return true;
	}
	
	NSAlert *alert = [[[NSAlert alloc] init] autorelease];
	[alert setMessageText:GetLocalizedString(@"Mount Boot EFI Partition?")];
	[alert setInformativeText:GetLocalizedString(@"Your Boot EFI Partition is not mounted.")];
	[alert addButtonWithTitle:GetLocalizedString(@"Cancel")];
	[alert addButtonWithTitle:GetLocalizedString(@"Mount")];
	[alert setAlertStyle:NSWarningAlertStyle];
	
	[alert beginSheetModalForWindow:appDelegate.window completionHandler:^(NSModalResponse returnCode)
	 {
		 [NSApp stopModalWithCode:returnCode];
	 }];
	
	if ([NSApp runModalForWindow:appDelegate.window] == NSAlertFirstButtonReturn)
		return false;
	
	NSString *stdoutString = nil, *stderrString = nil;
	
	if ([efiBootDisk mount:&stdoutString stderrString:&stderrString])
	{
		*efiVolumeURL = efiBootDisk.volumePath;
		
		return true;
	}
	
	return false;
}

+ (bool)openConfig:(AppDelegate *)appDelegate configDictionary:(NSMutableDictionary **)configDictionary configPath:(NSString **)configPath
{
	NSSavePanel *savePanel = [NSSavePanel savePanel];
	[savePanel setMessage:GetLocalizedString(@"Please select your existing config.plist to overwrite.\nData is written non-destructively and a backup will be created first.")];
	[savePanel setNameFieldStringValue:@"config.plist"];
	[savePanel setAllowedFileTypes:@[@"plist"]];
	NSURL *efiVolumeURL = nil;
	
	if ([Config mountBootEFI:appDelegate efiVolumeURL:&efiVolumeURL])
		[savePanel setDirectoryURL:[efiVolumeURL URLByAppendingPathComponent:[appDelegate isBootloaderOpenCore] ? @"EFI/OC" : @"EFI/CLOVER"]];
	
	[savePanel beginSheetModalForWindow:appDelegate.window completionHandler:^(NSModalResponse returnCode)
	 {
		 [NSApp stopModalWithCode:returnCode];
	 }];
	
	if ([NSApp runModalForWindow:appDelegate.window] != NSOKButton)
		return false;
	
	*configPath = [[savePanel URL] path];
	NSString *fileName = [*configPath lastPathComponent];
	
	if (![[NSFileManager defaultManager] fileExistsAtPath:*configPath])
	{
		if (![appDelegate showAlert:[NSString stringWithFormat:@"\"%@\" doesn't exist. Do you want to create it?", fileName] text:[NSString stringWithFormat:@"\"%@\" does not exist. You can create a new one.", fileName]])
			return false;
		
		*configDictionary = [[NSMutableDictionary alloc] init];
		
		return true;
	}
	
	NSError *error = nil;
	NSString *backupPath = appendSuffixToPath(*configPath, @"-backup");
	
	if ([[NSFileManager defaultManager] fileExistsAtPath:backupPath])
		[[NSFileManager defaultManager] removeItemAtPath:backupPath error:&error];
	
	[[NSFileManager defaultManager] copyItemAtPath:*configPath toPath:backupPath error:&error];
	
	*configDictionary = [NSMutableDictionary dictionaryWithContentsOfFile:*configPath];
	
	return true;
}

+ (BOOL)doesMatchOS:(NSString *)matchOS
{
	if (matchOS == nil)
		return YES;
	
	NSOperatingSystemVersion osVersion = [[NSProcessInfo processInfo] operatingSystemVersion];
	
	NSString *majorMinorPatchVersion = [NSString stringWithFormat:@"%ld.%ld.%ld", osVersion.majorVersion, osVersion.minorVersion, osVersion.patchVersion];
	NSString *majorMinorVersion = [NSString stringWithFormat:@"%ld.%ld.x", osVersion.majorVersion, osVersion.minorVersion];
	NSString *majorVersion = [NSString stringWithFormat:@"%ld.x.x", osVersion.majorVersion];
	
	if ([matchOS containsString:majorMinorPatchVersion])
		return YES;
	
	if ([matchOS containsString:majorMinorVersion])
		return YES;
	
	if ([matchOS containsString:majorVersion])
		return YES;
	
	return NO;
}

@end
