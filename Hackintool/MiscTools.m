//
//  MiscTools.m
//  Hackintool
//
//  Created by Ben Baker on 1/29/19.
//  Copyright © 2019 Ben Baker. All rights reserved.
//

#include "MiscTools.h"
#include <CoreFoundation/CoreFoundation.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <sys/wait.h>
#include <poll.h>
#include <dlfcn.h>
#include <objc/runtime.h>
#include <objc/message.h>
#include <libxml/tree.h>
#include "IORegTools.h"
#include "Authorization.h"

#define WEXISTATUS(status) (((status) & 0xff00) >> 8)

bool getStdioOutput(FILE *pipe, NSString **stdoutString, bool waitForExit)
{
	if (pipe == NULL)
		return false;
	
	int stat = 0;
	int pipeFD = fileno(pipe);
	
	if (pipeFD <= 0)
		return false;
	
	if (waitForExit)
	{
		pid_t pid = fcntl(pipeFD, F_GETOWN, 0);
		while ((pid = waitpid(pid, &stat, WNOHANG)) == 0);
	}
	
	NSFileHandle *stdoutHandle = [[NSFileHandle alloc] initWithFileDescriptor:pipeFD closeOnDealloc:YES];
	NSData *stdoutData = [stdoutHandle readDataToEndOfFile];
	NSMutableData *stdoutMutableData = [NSMutableData dataWithData:stdoutData];
	((char *)[stdoutMutableData mutableBytes])[[stdoutData length] - 1] = '\0';
	*stdoutString = [[NSString stringWithCString:(const char *)[stdoutMutableData bytes] encoding:NSASCIIStringEncoding] retain];
	[stdoutHandle release];
	
	return true;
}

bool launchCommand(NSString *launchPath, NSString *currentDirectoryPath, NSArray *arguments, NSString **stdoutString)
{
	*stdoutString = nil;
	
	@try
	{
		NSPipe *pipe = [NSPipe pipe];
		NSFileHandle *file = pipe.fileHandleForReading;
		
		NSTask *task = [[NSTask alloc] init];
		task.currentDirectoryPath = currentDirectoryPath;
		task.launchPath = launchPath;
		task.arguments = arguments;
		task.standardOutput = pipe;
		task.standardError = pipe;
		
		[task launch];
		NSMutableData *data = [[file readDataToEndOfFile] mutableCopy];
		[task waitUntilExit];

		[data appendData:[file readDataToEndOfFile]];
		[file closeFile];
		
		[task release];
		
		*stdoutString = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
	}
	@catch (NSException *ex)
	{
		return false;
	}
	
	return true;
}

bool launchCommand(NSString *launchPath, NSArray *arguments, NSString **stdoutString)
{
	return launchCommand(launchPath, @"/", arguments, stdoutString);
}

bool launchCommand(NSString *launchPath, NSArray *arguments, id object, SEL outputNotification, SEL errorNotification, SEL completeNotification)
{
	@try
	{
		NSPipe *outputPipe = [NSPipe pipe];
		NSPipe *errorPipe = [NSPipe pipe];
		
		NSFileHandle *outputFile = outputPipe.fileHandleForReading;
		NSFileHandle *errorFile = errorPipe.fileHandleForReading;
		
		NSTask *task = [[NSTask alloc] init];
		task.currentDirectoryPath = @"/";
		task.launchPath = launchPath;
		task.arguments = arguments;
		task.standardOutput = outputPipe;
		task.standardError = errorPipe;
		task.standardInput = [NSPipe pipe];
		
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
			NSData *outputData = [outputFile availableData];
			while ([outputData length] > 0)
			{
				dispatch_async(dispatch_get_main_queue(), ^{
					[object performSelector:outputNotification withObject:[NSNotification notificationWithName:@"FileOutputNotification" object:task userInfo:@{@"Data":outputData}]];
				});
				outputData = [outputFile availableData];
			}
		});
		
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
			NSData *errorData = [errorFile availableData];
			while ([errorData length] > 0)
			{
				dispatch_async(dispatch_get_main_queue(), ^{
					[object performSelector:errorNotification withObject:[NSNotification notificationWithName:@"FileErrorNotification" object:task userInfo:@{@"Data":errorData}]];
				});
				errorData = [errorFile availableData];
			}
		});
		
		[task launch];
		[task waitUntilExit];
		
		dispatch_async(dispatch_get_main_queue(), ^{
			[object performSelector:completeNotification withObject:[NSNotification notificationWithName:@"TaskCompleteNotification" object:task userInfo:nil]];
		});
		
		[task release];
	}
	@catch (NSException *ex)
	{
		return false;
	}
	
	return true;
}

bool launchCommandAsAdmin(NSString *launchPath, NSArray *arguments, NSString **stdoutString)
{
	OSStatus status = 0;
	AuthorizationRef authorization = NULL;
	
	if ((status = getAuthorization(&authorization)) != errAuthorizationSuccess)
		return status;
	
	AuthorizationItem adminAuthorization = { "system.privilege.admin", 0, NULL, 0 };
	AuthorizationRights rightSet = { 1, &adminAuthorization };
	
	status = AuthorizationCopyRights(authorization, &rightSet, kAuthorizationEmptyEnvironment, kAuthorizationFlagPreAuthorize | kAuthorizationFlagInteractionAllowed | kAuthorizationFlagExtendRights, NULL);
	
	callAuthorizationGrantedCallback(status);
	
	if (status != errAuthorizationSuccess)
		return false;
	
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	FILE *pipe = NULL;
	NSUInteger count = [arguments count];
	char **args = (char **)calloc(count + 1, sizeof(char *));
	
	for(uint32_t i = 0; i < count; i++)
		args[i] = (char *)[arguments[i] UTF8String];
	
	args[count] = NULL;
	
	status = AuthorizationExecuteWithPrivileges(authorization, [launchPath UTF8String], kAuthorizationFlagDefaults, args, &pipe);
	
	free(args);
	
	[pool drain];
	
	if (status == errAuthorizationSuccess)
	{
		getStdioOutput(pipe, stdoutString, false);
		
		if ([*stdoutString length] > 0)
			*stdoutString = [*stdoutString stringByAppendingString:@"\n"];
	}
	
	//fclose(pipe);
	
	return (status == errAuthorizationSuccess);
}

// https://svn.ajdeveloppement.org/ajcommons/branches/1.1/c-src/MacOSXAuthProcess.c
bool launchCommandAsAdmin(NSString *launchPath, NSArray *arguments, NSString **stdoutString, NSString **stderrString)
{
	OSStatus status;
	*stdoutString = nil;
	*stderrString = nil;
	char stdoutPath[] = "/tmp/AuthorizationExecuteWithPrivilegesXXXXXXX.stdout";
	char stderrPath[] = "/tmp/AuthorizationExecuteWithPrivilegesXXXXXXX.stderr";
	char command[1024];
	const char **args;
	int i;
	int stdoutFd = 0, stderrFd = 0;
	pid_t pid = 0;
	
	AuthorizationRef authorization = NULL;
	
	if ((status = getAuthorization(&authorization)) != errAuthorizationSuccess)
		return status;
	
	AuthorizationItem adminAuthorization = { "system.privilege.admin", 0, NULL, 0 };
	AuthorizationRights rightSet = { 1, &adminAuthorization };
	
	status = AuthorizationCopyRights(authorization, &rightSet, kAuthorizationEmptyEnvironment, kAuthorizationFlagPreAuthorize | kAuthorizationFlagInteractionAllowed | kAuthorizationFlagExtendRights, NULL);
	
	callAuthorizationGrantedCallback(status);
	
	if (status != errAuthorizationSuccess)
		return false;
	
	// Create temporary file for stdout
	{
		stdoutFd = mkstemps(stdoutPath, strlen(".stdout"));
		
		// create a pipe on that path
		close(stdoutFd);
		unlink(stdoutPath);
		
		if (mkfifo(stdoutPath, S_IRWXU | S_IRWXG) != 0)
			return false;
		
		if (stdoutFd < 0)
			return false;
	}
	
	// Create temporary file for stderr
	{
		stderrFd = mkstemps(stderrPath, strlen(".stderr"));
		
		// create a pipe on that path
		close(stderrFd);
		unlink(stderrPath);
		
		if (mkfifo(stderrPath, S_IRWXU | S_IRWXG) != 0)
			return false;
		
		if (stderrFd < 0)
			return false;
	}
	
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	// Create command to be executed
	args = (const char **)malloc(sizeof(char *)*(arguments.count + 5));
	args[0] = "-c";
	snprintf(command, sizeof(command), "echo $$; \"$@\" 1>%s 2>%s", stdoutPath, stderrPath);
	args[1] = command;
	args[2] = "";
	args[3] = (char *)[launchPath UTF8String];
	
	for (i = 0; i < arguments.count; ++i)
		args[i + 4] = [arguments[i] UTF8String];
	
	args[arguments.count + 4] = 0;
	
	// for debugging: log the executed command
	//printf ("/bin/sh"); for (i = 0; args[i] != 0; ++i) { printf (" \"%s\"", args[i]); } printf ("\n");
	
	FILE *commPipe;
	
	// Execute command
	status = AuthorizationExecuteWithPrivileges(authorization, "/bin/sh",  kAuthorizationFlagDefaults, (char **)args, &commPipe);
	
	free(args);
	
	[pool drain];
	
	if (status != noErr)
	{
		unlink(stdoutPath);
		unlink(stderrPath);
		return false;
	}
	
	// Read the first line of stdout => it's the pid
	{
		NSMutableString *stdoutMutableString = [NSMutableString string];
		stdoutFd = fileno(commPipe);
		char ch = 0;
		
		while ((read(stdoutFd, &ch, sizeof(ch)) == 1) && (ch != '\n'))
			[stdoutMutableString appendFormat:@"%c", ch];
		
		if (ch != '\n')
		{
			// we shouldn't get there
			unlink (stdoutPath);
			unlink (stderrPath);
			
			return false;
		}
		
		pid = [stdoutMutableString intValue];
		
		close(stdoutFd);
	}
	
	stdoutFd = open(stdoutPath, O_RDONLY, 0);
	stderrFd = open(stderrPath, O_RDONLY, 0);
	
	unlink(stdoutPath);
	unlink(stderrPath);
	
	if (stdoutFd < 0 || stderrFd < 0)
	{
		close(stdoutFd);
		close(stderrFd);
		
		return false;
	}
	
	int outFlags = fcntl(stdoutFd, F_GETFL);
	int errFlags = fcntl(stderrFd, F_GETFL);
	fcntl(stdoutFd, F_SETFL, outFlags | O_NONBLOCK);
	fcntl(stderrFd, F_SETFL, errFlags | O_NONBLOCK);
	
	NSMutableString *stdoutMutableString = [NSMutableString string];
	NSMutableString *stderrMutableString = [NSMutableString string];
	char ch = 0;
	int stat = 0, retval = 0;
	struct pollfd stdoutPollFd, stderrPollFd;
	stdoutPollFd.fd = stdoutFd;
	stdoutPollFd.events = POLLIN;
	stderrPollFd.fd = stderrFd;
	stderrPollFd.events = POLLIN;
	
	while (waitpid(pid, &stat, WNOHANG) != pid)
	{
		if ((retval = poll(&stdoutPollFd, 1, 100)) > 0)
		{
			if (stdoutPollFd.revents & POLLIN)
			{
				while (read(stdoutFd, &ch, sizeof(ch)) == 1)
					[stdoutMutableString appendFormat:@"%c", ch];
			}
		}
		
		if ((retval = poll(&stderrPollFd, 1, 100)) > 0)
		{
			if (stderrPollFd.revents & POLLIN)
			{
				while (read(stderrFd, &ch, sizeof(ch)) == 1)
					[stderrMutableString appendFormat:@"%c", ch];
			}
		}
		
		//if (WIFEXITED(stat) || WIFSIGNALED(stat) || WIFSTOPPED(stat))
		//	break;
	}
	
	if ((retval = poll(&stdoutPollFd, 1, 100)) > 0)
	{
		if (stdoutPollFd.revents & POLLIN)
		{
			while (read(stdoutFd, &ch, sizeof(ch)) == 1)
				[stdoutMutableString appendFormat:@"%c", ch];
		}
	}
	
	if ((retval = poll(&stderrPollFd, 1, 100)) > 0)
	{
		if (stderrPollFd.revents & POLLIN)
		{
			while (read(stderrFd, &ch, sizeof(ch)) == 1)
				[stderrMutableString appendFormat:@"%c", ch];
		}
	}
	
	*stdoutString = [NSString stringWithString:stdoutMutableString];
	*stderrString = [NSString stringWithString:stderrMutableString];
	
	close(stdoutFd);
	close(stderrFd);
	
	return true;
}

NSString *getBase64String(uint32_t uint32Value)
{
	NSMutableData *uint32Data = [NSMutableData new];
	[uint32Data appendBytes:&uint32Value length:sizeof(uint32Value)];
	NSString *uint32Base64 = [uint32Data base64EncodedStringWithOptions:0];
	[uint32Data release];
	
	return uint32Base64;
}

NSData *getNSDataUInt32(uint32_t uint32Value)
{
	return [NSData dataWithBytes:&uint32Value length:sizeof(uint32Value)];
}

NSString *getByteString(uint32_t uint32Value)
{
	return [NSString stringWithFormat:@"0x%02X, 0x%02X, 0x%02X, 0x%02X", uint32Value & 0xFF, (uint32Value >> 8) & 0xFF, (uint32Value >> 16) & 0xFF, (uint32Value >> 24) & 0xFF];
}

NSMutableString *getByteString(NSData *data)
{
	return getByteString(data, @", ", @"0x", false, true);
}

NSMutableString *getByteString(NSData *data, NSString *delimiter, NSString *prefix, bool lineBreak, bool upperCase)
{
	NSMutableString *result = [NSMutableString string];
	
	for (int i = 0; i < data.length; i++)
	{
		if (i > 0)
		{
			if (lineBreak && (i % 8) == 0)
				[result appendString:@"\n"];
			else
				[result appendString:delimiter];
		}
		
		[result appendFormat:upperCase ? @"%@%02X" : @"%@%02x", prefix, ((unsigned char *)data.bytes)[i]];
	}
	
	return result;
}

NSMutableString *getByteStringClassic(NSData *data)
{
	NSMutableString *result = [NSMutableString string];
	[result appendString:@"<"];
	
	for (int i = 0; i < data.length; i++)
	{
		if (i > 0)
		{
			if ((i % 4) == 0)
				[result appendString:@" "];
		}

		[result appendFormat:@"%02x", ((unsigned char *)data.bytes)[i]];
	}
	
	[result appendString:@">"];
	
	return result;
}

NSMutableData *getReverseData(NSData *data)
{
	if (data == nil)
		return nil;
	
	NSMutableData *result = [NSMutableData data];

	for(int i = (int)data.length - 1; i >= 0; i--)
		[result appendBytes:&((unsigned char *)data.bytes)[i] length:1];

	return result;
}

uint32_t getReverseBytes(uint32_t value)
{
	return ((value >> 24) & 0xFF) | ((value << 8) & 0xFF0000) | ((value >> 8) & 0xFF00) | ((value << 24) & 0xFF000000);
}

NSString *getTempPath()
{
	NSBundle *mainBundle = [NSBundle mainBundle];
	NSDictionary *infoDictionary = [mainBundle infoDictionary];
	NSString *bundleIdentifier = [infoDictionary objectForKey:@"CFBundleIdentifier"];
	NSString *tempDirectoryPath = nil;
	NSString *tempDirectoryTemplate = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.XXXXXX", bundleIdentifier]];
	const char *tempDirectoryTemplateCString = [tempDirectoryTemplate fileSystemRepresentation];
	char *tempDirectoryNameCString = (char *)malloc(strlen(tempDirectoryTemplateCString) + 1);
	strcpy(tempDirectoryNameCString, tempDirectoryTemplateCString);
	
	char *result = mkdtemp(tempDirectoryNameCString);
	
	if (result)
		tempDirectoryPath = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:tempDirectoryNameCString length:strlen(result)];
	
	free(tempDirectoryNameCString);
	
	return tempDirectoryPath;
}

string replaceAll(string& str, const string& from, const string& to)
{
	if(from.empty())
		return string(from);
	
	string ret = string(str);
	size_t start_pos = 0;
	
	while((start_pos = ret.find(from, start_pos)) != string::npos)
	{
		ret.replace(start_pos, from.length(), to);
		start_pos += to.length();
	}
	
	return ret;
}

bool getUInt32PropertyValue(AppDelegate *appDelegate, NSDictionary *propertyDictionary, NSString *propertyName, uint32_t *propertyValue)
{
	id property = [propertyDictionary objectForKey:propertyName];
	
	if (property == nil)
		return false;
	
	*propertyValue = propertyToUInt32(property);
	
	return true;
}

bool applyFindAndReplacePatch(NSData *findData, NSData *replaceData, uint8_t *findAddress, uint8_t *replaceAddress, size_t maxSize, uint32_t count)
{
	bool r = false;
	size_t i = 0, patchCount = 0, patchLength = MIN([findData length], [replaceData length]);
	uint8_t *startAddress = findAddress;
	uint8_t *endAddress = findAddress + maxSize - patchLength;
	uint8_t *startReplaceAddress = replaceAddress;
	
	while (startAddress < endAddress)
	{
		for (i = 0; i < patchLength; i++)
		{
			if (startAddress[i] != static_cast<const uint8_t *>([findData bytes])[i])
				break;
		}
		
		if (i == patchLength)
		{
			for (i = 0; i < patchLength; i++)
				startReplaceAddress[i] = static_cast<const uint8_t *>([replaceData bytes])[i];
			
			r = true;
			
			if (++patchCount >= count)
				break;
			
			startAddress += patchLength;
			startReplaceAddress += patchLength;
			continue;
		}
		
		startAddress++;
		startReplaceAddress++;
	}
	
	return r;
}

NSData *stringToData(NSString *dataString, int size)
{
	NSString *hexChars = @"0123456789abcdefABCDEF";
	NSCharacterSet *hexCharSet = [NSCharacterSet characterSetWithCharactersInString:hexChars];
	NSCharacterSet *invalidHexCharSet = [hexCharSet invertedSet];
	NSString *cleanDataString = [dataString stringByReplacingOccurrencesOfString:@"0x" withString:@""];
	cleanDataString = [[cleanDataString componentsSeparatedByCharactersInSet:invalidHexCharSet] componentsJoinedByString:@""];
	
	NSMutableData *result = [[NSMutableData alloc] init];
	
	for (int i = 0; i + size <= cleanDataString.length; i += size)
	{
		NSRange range = NSMakeRange(i, size);
		NSString *hexString = [cleanDataString substringWithRange:range];
		NSScanner *scanner = [NSScanner scannerWithString:hexString];
		unsigned int intValue;
		[scanner scanHexInt:&intValue];
		unsigned char uc = (unsigned char)intValue;
		[result appendBytes:&uc length:1];
	}
	
	NSData *resultData = [NSData dataWithData:result];
	[result release];
	
	return resultData;
}

NSData *stringToData(NSString *dataString)
{
	return stringToData(dataString, 2);
}

NSString *decimalToBinary(unsigned long long integer)
{
	NSString *string = @"" ;
	unsigned long long x = integer;
	do
	{
		string = [[NSString stringWithFormat: @"%llu", x & 1] stringByAppendingString:string];
	}
	while (x >>= 1);
	
	return string;
}

unsigned long long binaryToDecimal(NSString *str)
{
	double j = 0;
	
	for(int i = 0; i < [str length]; i++)
	{
		if ([str characterAtIndex:i] == '1')
			j = j+ pow(2, [str length] - 1 - i);
	}
	
	return (unsigned long long) j;
}

NSString *getKernelName()
{
	char buffer[256];
	size_t length;
	int mib[2];
	
	mib[0] = CTL_KERN;
	mib[1] = KERN_OSTYPE;
	length = sizeof(buffer);
	sysctl(mib, 2, &buffer, &length, NULL, 0);
	NSString *kernOSType = [NSString stringWithUTF8String:buffer];
	
	mib[0] = CTL_KERN;
	mib[1] = KERN_OSRELEASE;
	length = sizeof(buffer);
	sysctl(mib, 2, &buffer, &length, NULL, 0);
	NSString *kernOSRelease = [NSString stringWithUTF8String:buffer];
	
	mib[0] = CTL_HW;
	mib[1] = HW_MACHINE;
	length = sizeof(buffer);
	sysctl(mib, 2, &buffer, &length, NULL, 0);
	NSString *hwMachine = [NSString stringWithUTF8String:buffer];
	
	return [NSString stringWithFormat:@"%@ %@ %@", kernOSType, kernOSRelease, hwMachine];
}

NSString *getHostName()
{
	char buffer[256];
	size_t length;
	int mib[2];
	mib[0] = CTL_KERN;
	mib[1] = KERN_HOSTNAME;
	length = sizeof(buffer);
	sysctl(mib, 2, &buffer, &length, NULL, 0);
	return [NSString stringWithUTF8String:buffer];
}

NSString *getOSName()
{
	NSProcessInfo *processInfo = [NSProcessInfo processInfo];
	NSOperatingSystemVersion version = [processInfo operatingSystemVersion];
	NSString *osVersionString = [processInfo operatingSystemVersionString];
	NSString *codeName = @"";
	
	switch(version.majorVersion)
	{
	case 10:
		switch(version.minorVersion)
		{
		case 4:
			codeName = @"Mac OS X Tiger";
			break;
		case 5:
			codeName = @"Mac OS X Leopard";
			break;
		case 6:
			codeName = @"Mac OS X Snow Leopard";
			break;
		case 7:
			codeName = @"Mac OS X Lion";
			break;
		case 8:
			codeName = @"OS X Mountain Lion";
			break;
		case 9:
			codeName = @"OS X Mavericks";
			break;
		case 10:
			codeName = @"OS X Yosemite";
			break;
		case 11:
			codeName = @"OS X El Capitan";
			break;
		case 12:
			codeName = @"macOS Sierra";
			break;
		case 13:
			codeName = @"macOS High Sierra";
			break;
		case 14:
			codeName = @"macOS Mojave";
			break;
		case 15:
			codeName = @"macOS Catalina";
			break;
		}
		break;
	case 11:
		codeName = @"macOS Big Sur";
		break;
	case 12:
		codeName = @"macOS Monterey";
		break;
	case 13:
		codeName = @"macOS Ventura";
		break;
	case 14:
		codeName = @"macOS Sonoma";
		break;
	}
	
	return [NSString stringWithFormat:@"%@ %@", codeName, osVersionString];
}

NSString *getStorageSizeString(NSNumber *value)
{
	double convertedValue = [value doubleValue];
	int multiplyFactor = 0;
	
	NSArray *tokenArray = @[@"bytes", @"KB", @"MB", @"GB", @"TB", @"PB", @"EB", @"ZB", @"YB"];
	
	while (convertedValue > 1024)
	{
		convertedValue /= 1024;
		multiplyFactor++;
	}
	
	return [NSString stringWithFormat:@"%4.2f %@", convertedValue, tokenArray[multiplyFactor]];
}

NSString *getMemSize()
{
	int64_t physicalMemory;
	size_t length;
	int mib[2];
	mib[0] = CTL_HW;
	mib[1] = HW_MEMSIZE;https://linux.die.net/man/1/iconv
	length = sizeof(int64_t);
	sysctl(mib, 2, &physicalMemory, &length, NULL, 0);
	return getStorageSizeString([NSNumber numberWithLong:physicalMemory]);
}

NSString *getCPUInfo()
{
	char buffer[256];
	size_t length = sizeof(buffer);
	sysctlbyname("machdep.cpu.brand_string", buffer, &length, NULL, 0);
	return [NSString stringWithUTF8String:buffer];
}

bool getMetalInfo(CGDirectDisplayID directDisplayID, NSString **name, bool &isDefault, bool &isLowPower, bool &isHeadless)
{
	void *metal = dlopen("/System/Library/Frameworks/Metal.framework/Metal", RTLD_LAZY);
	id (*mtlCreateSystemDefaultDevice)(void) = (id (*)(void))dlsym(metal, "MTLCreateSystemDefaultDevice");
	
	if (!mtlCreateSystemDefaultDevice)
		return false;
	
	id<MTLDevice> device = CGDirectDisplayCopyCurrentMetalDevice(directDisplayID);
	
	if (device == nil)
		return false;
	
	id<MTLDevice> defaultDevice = mtlCreateSystemDefaultDevice();
	
	*name = reinterpret_cast<id (*)(id, SEL)>(objc_msgSend)(reinterpret_cast<id>(device), sel_registerName("name"));
	isDefault = (device == defaultDevice);
	isLowPower = reinterpret_cast<id (*)(id, SEL)>(objc_msgSend)(reinterpret_cast<id>(device), sel_registerName("isLowPower"));
	isHeadless = reinterpret_cast<id (*)(id, SEL)>(objc_msgSend)(reinterpret_cast<id>(device), sel_registerName("isHeadless"));
	
	return true;
}

bool getMetalInfo(NSString **name, bool &isLowPower, bool &isHeadless)
{
	void *metal = dlopen("/System/Library/Frameworks/Metal.framework/Metal", RTLD_LAZY);
	id (*mtlCreateSystemDefaultDevice)(void) = (id (*)(void))dlsym(metal, "MTLCreateSystemDefaultDevice");
	
	if (!mtlCreateSystemDefaultDevice)
		return false;
	
	id<MTLDevice> device = mtlCreateSystemDefaultDevice();
	
	if (device == nil)
		return false;
	
	*name = reinterpret_cast<id (*)(id, SEL)>(objc_msgSend)(reinterpret_cast<id>(device), sel_registerName("name"));
	isLowPower = reinterpret_cast<id (*)(id, SEL)>(objc_msgSend)(reinterpret_cast<id>(device), sel_registerName("isLowPower"));
	isHeadless = reinterpret_cast<id (*)(id, SEL)>(objc_msgSend)(reinterpret_cast<id>(device), sel_registerName("isHeadless"));
	
	return true;
}

NSString *appendSuffixToPath(NSString *path, NSString *suffix)
{
	NSString *containingFolder = [path stringByDeletingLastPathComponent];
	NSString *fullFileName = [path lastPathComponent];
	NSString *fileExtension = [fullFileName pathExtension];
	NSString *fileName = [fullFileName stringByDeletingPathExtension];
	NSString *newFileName = [fileName stringByAppendingString:suffix];
	NSString *newFullFileName = [newFileName stringByAppendingPathExtension:fileExtension];
	
	return [containingFolder stringByAppendingPathComponent:newFullFileName];
}

NSColor *getColorAlpha(NSColor *color, float alpha)
{
	NSColor *resultColor = [color colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
	
	return [NSColor colorWithRed:resultColor.redComponent green:resultColor.greenComponent blue:resultColor.blueComponent alpha:alpha];
}

bool getRegExArray(NSString *regExPattern, NSString *valueString, uint32_t itemCount, NSMutableArray **itemArray)
{
	NSError *regError = nil;
	NSRegularExpression *regEx = [NSRegularExpression regularExpressionWithPattern:regExPattern options:NSRegularExpressionCaseInsensitive error:&regError];
	
	if (regError)
		return false;
	
	NSTextCheckingResult *match = [regEx firstMatchInString:valueString options:0 range:NSMakeRange(0, [valueString length])];
	
	if (match == nil || [match numberOfRanges] != itemCount + 1)
		return false;
	
	*itemArray = [NSMutableArray array];
	
	for (int i = 1; i < match.numberOfRanges; i++)
		[*itemArray addObject:[valueString substringWithRange:[match rangeAtIndex:i]]];
	
	return true;
}

uint32_t getIntFromString(NSString *valueString)
{
	uint32_t value;
	
	NSScanner *scanner = [NSScanner scannerWithString:valueString];
	[scanner scanInt:(int *)&value];
	
	return value;
}

uint32_t getIntFromData(NSData *data)
{
	uint32_t result = 0;

	[data getBytes:&result length:sizeof(result)];
	
	return result;
}

uint32_t getHexIntFromString(NSString *valueString)
{
	uint32_t value;
	
	NSScanner *scanner = [NSScanner scannerWithString:valueString];
	[scanner scanHexInt:&value];
	
	return value;
}

void sendNotificationTitle(id delegate, NSString *title, NSString *subtitle, NSString *text, NSString *actionButtonTitle, NSString *otherButtonTitle, bool hasActionButton)
{
	NSUserNotification *notification = [[NSUserNotification alloc] init];
	
	notification.title = title;
	notification.subtitle = subtitle;
	notification.soundName = NSUserNotificationDefaultSoundName;
	notification.informativeText = text;
	//notification.deliveryDate = deliveryDate;
	
	if(hasActionButton)
	{
		notification.hasActionButton = YES;
		notification.actionButtonTitle = actionButtonTitle;
		notification.otherButtonTitle = otherButtonTitle;
	}
	
	NSUserNotificationCenter *notificationCenter = [NSUserNotificationCenter defaultUserNotificationCenter];
	
	notificationCenter.delegate = delegate;
	
	[notificationCenter deliverNotification:notification];
	[notification release];
}

bool tryFormatXML(NSString *rawXML, NSString **xmlString, bool formattingAllowed)
{
	xmlLineNumbersDefault(1);
	xmlThrDefIndentTreeOutput(1);
	xmlKeepBlanksDefault(0);
	xmlThrDefTreeIndentString(formattingAllowed ? "    " : "");
	
	const char *utf8Str = [rawXML UTF8String];
	xmlDocPtr pXmlDoc = xmlReadMemory(utf8Str, (int)strlen(utf8Str), NULL, NULL, XML_PARSE_NOERROR);
	
	if (pXmlDoc == NULL)
		return false;
	
	xmlNodePtr pXmlRootNode = xmlDocGetRootElement(pXmlDoc);
	xmlNodePtr pXmlRootCopyNode = xmlCopyNode(pXmlRootNode, 1);
	xmlFreeDoc(pXmlDoc);
	
	xmlBufferPtr pXmlBuffer = xmlBufferCreate();
	pXmlDoc = NULL;

	int result = xmlNodeDump(pXmlBuffer, pXmlDoc, pXmlRootCopyNode, 0, formattingAllowed ? 1 : 0);
	
	if (result == -1)
		return false;
	
	*xmlString = [[NSString alloc] initWithBytes:(xmlBufferContent(pXmlBuffer))
									   length:(NSUInteger)(xmlBufferLength(pXmlBuffer))
									 encoding:NSUTF8StringEncoding];
	
	xmlBufferFree(pXmlBuffer);
	
	NSCharacterSet *characterSet = [NSCharacterSet whitespaceAndNewlineCharacterSet];
	*xmlString = [*xmlString stringByTrimmingCharactersInSet:characterSet];
	
	return true;
}

NSMutableData *getNSDataFromString(NSString *hexString, NSString *separator)
{
	NSMutableData *hexValuesData = [NSMutableData data];
	NSArray *hexArray = [hexString componentsSeparatedByString:separator];
	
	for (int i = 0; i < [hexArray count]; i++)
	{
		NSString *hexEntry = hexArray[i];
		uint32_t value = 0;
		NSScanner *scanner = [NSScanner scannerWithString:hexEntry];
		[scanner scanHexInt:&value];
		unsigned char byte = value;
		
		[hexValuesData appendBytes:&byte length:1];
	}
	
	return hexValuesData;
}

NSMutableArray *getHexArrayFromString(NSString *hexString, NSString *separator)
{
	NSMutableArray *hexValuesArray = [NSMutableArray array];
	NSArray *hexArray = [hexString componentsSeparatedByString: @" "];
	
	for (int i = 0; i < [hexArray count]; i++)
	{
		NSString *hexEntry = hexArray[i];
		uint32_t value = 0;
		NSScanner *scanner = [NSScanner scannerWithString:hexEntry];
		[scanner scanHexInt:&value];
		
		[hexValuesArray addObject:@(value)];
	}
	
	return hexValuesArray;
}

NSString *getHexStringFromArray(NSMutableArray *numberArray)
{
	NSMutableString *hexString = [NSMutableString string];
	
	for (int i = 0; i < [numberArray count]; i++)
	{
		NSNumber *number = numberArray[i];
		
		[hexString appendFormat:@"0x%08X", [number intValue]];
		
		if (i < [numberArray count] - 1)
			[hexString appendString:@" "];
	}
	
	return hexString;
}

NSString *getStringFromHexString(NSString *hexString)
{
	if (hexString == nil)
		return nil;
	
	NSMutableString *string = [NSMutableString string];

	for (NSInteger i = 0; i < [hexString length]; i += 2)
	{
		if (i + 2 >= [hexString length])
			break;
		
		NSString *hex = [hexString substringWithRange:NSMakeRange(i, 2)];
		int decimalValue = 0;
		sscanf([hex UTF8String], "%x", &decimalValue);
		[string appendFormat:@"%c", decimalValue];
	}

	return string;
}

NSArray *translateArray(NSArray *array)
{
	NSMutableArray *resultArray = [NSMutableArray array];
	
	for (NSString *value in array)
		[resultArray addObject:GetLocalizedString(value)];
	
	return resultArray;
}

NSString *trimNewLine(NSString *string)
{
	NSRange newLineRange = [string rangeOfString:@"\n"];
	
	if (newLineRange.location == NSNotFound)
		return string;
	
	return [string substringToIndex:newLineRange.location];
}

NSString *getUUID()
{
	uuid_t binuuid;
	uuid_generate_random(binuuid);
	char *uuid = (char *)malloc(37);

	uuid_unparse_upper(binuuid, uuid);
	uuid_unparse(binuuid, uuid);
	
	return [NSString stringWithUTF8String:uuid];
}
