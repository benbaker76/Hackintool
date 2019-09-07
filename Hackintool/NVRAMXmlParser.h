//
//  NVRAMXmlParser.h
//  Hackintool
//
//  Created by Ben Baker on 1/25/19.
//  Copyright © 2019 Ben Baker. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

enum ElementType
{
	None,
	Array,
	Dictionary
};

@interface NVRAMXmlParser : NSResponder <NSXMLParserDelegate>
{
	NSMutableArray *_rootArray;
	NSMutableArray *_array;
	NSMutableDictionary *_dictionary;
	NSString *_key;
	NSString *_elementName;
	NSString *_lastElementName;
}

-(NSString *)getValue:(NSArray *)valueArray;

+(instancetype)initWithString:(NSString *)string encoding:(NSStringEncoding)encoding;

@end
