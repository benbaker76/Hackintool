//
//  MiscTools.h
//  Hackintool
//
//  Created by Ben Baker on 1/29/19.
//  Copyright © 2019 Ben Baker. All rights reserved.
//

#ifndef MiscTools_h
#define MiscTools_h

#import "AppDelegate.h"
#import <stdio.h>
#import <string>

using std::string;

#define strHexDec(x) strtol([x UTF8String], NULL, 16)
#define membersize(type, member) sizeof(((type *)0)->member)

#define GetLocalizedString(key) \
[[NSBundle mainBundle] localizedStringForKey:(key) value:@"" table:nil]

template <class T, size_t N>
constexpr size_t arrsize(const T (&array)[N])
{
	return N;
}

OSStatus AuthorizationExecuteWithPrivilegesStdErr(AuthorizationRef authorization, const char *pathToTool, AuthorizationFlags options, char * const *arguments, FILE **communicationsPipe, FILE **errPipe);
bool getStdioOutput(FILE *pipe, NSString **stdoutString, bool waitForExit);
bool launchCommand(NSString *launchPath, NSString *currentDirectoryPath, NSArray *arguments, NSString **stdoutString);
bool launchCommand(NSString *launchPath, NSArray *arguments, NSString **stdoutString);
bool launchCommand(NSString *launchPath, NSArray *arguments, id object, SEL outputNotification, SEL errorNotification, SEL completeNotification);
bool launchCommandAsAdmin(NSString *launchPath, NSArray *arguments, NSString **stdoutString);
bool launchCommandAsAdmin(NSString *launchPath, NSArray *arguments, NSString **stdoutString, NSString **stderrString);
NSData *getNSDataUInt32(uint32_t uint32Value);
NSString *getBase64String(uint32_t uint32Value);
NSString *getByteString(uint32_t uint32Value);
NSMutableString *getByteString(NSData *data);
NSMutableString *getByteString(NSData *data, NSString *prefix);
NSMutableString *getByteString(NSData *data, NSString *delimiter, NSString *prefix, bool lineBreak, bool upperCase);
NSMutableString *getByteStringClassic(NSData *data);
NSMutableData *getReverseData(NSData *data);
uint32_t getReverseBytes(uint32_t value);
NSString *getTempPath();
string replaceAll(string& str, const string& from, const string& to);
bool getUInt32PropertyValue(AppDelegate *appDelegate, NSDictionary *propertyDictionary, NSString *propertyName, uint32_t *propertyValue);
bool applyFindAndReplacePatch(NSData *findData, NSData *replaceData, uint8_t *findAddress, uint8_t *replaceAddress, size_t maxSize, uint32_t count);
NSData *stringToData(NSString *dataString);
NSString *decimalToBinary(unsigned long long integer);
unsigned long long binaryToDecimal(NSString *str);
NSString *getKernelName();
NSString *getHostName();
NSString *getOSName();
NSString *getStorageSizeString(NSNumber *value);
NSString *getMemSize();
NSString *getCPUInfo();
bool getMetalInfo(CGDirectDisplayID directDisplayID, NSString **name, bool &isDefault, bool &isLowPower, bool &isHeadless);
bool getMetalInfo(NSString **name, bool &isLowPower, bool &isHeadless);
NSString *appendSuffixToPath(NSString *path, NSString *suffix);
NSColor *getColorAlpha(NSColor *color, float alpha);
bool getRegExArray(NSString *regExPattern, NSString *valueString, uint32_t itemCount, NSMutableArray **itemArray);
uint32_t getIntFromString(NSString *valueString);
uint32_t getIntFromData(NSData *data);
uint32_t getHexIntFromString(NSString *valueString);
void sendNotificationTitle(id delegate, NSString *title, NSString *subtitle, NSString *text, NSString *actionButtonTitle, NSString *otherButtonTitle, bool hasActionButton);
bool tryFormatXML(NSString *rawXML, NSString **xmlString, bool formattingAllowed);
NSMutableData *getNSDataFromString(NSString *hexString, NSString *separator);
NSMutableArray *getHexArrayFromString(NSString *hexString, NSString *separator);
NSString *getHexStringFromArray(NSMutableArray *numberArray);
NSString *getStringFromHexString(NSString *hexString);
NSArray *translateArray(NSArray *array);
NSString *trimNewLine(NSString *string);
NSString *getUUID();

#endif /* MiscTools_hpp */
