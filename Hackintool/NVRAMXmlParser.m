//
//  NVRAMXmlParser.m
//  Hackintool
//
//  Created by Ben Baker on 1/25/19.
//  Copyright © 2019 Ben Baker. All rights reserved.
//

#import "NVRAMXmlParser.h"

@implementation NVRAMXmlParser

+(instancetype)initWithString:(NSString *)string encoding:(NSStringEncoding)encoding
{
	NVRAMXmlParser *nvramXmlParser = [[[NVRAMXmlParser alloc] init] autorelease];
	NSData *data = [string dataUsingEncoding:encoding];
	NSXMLParser *xmlParser = [[NSXMLParser alloc] initWithData:data];
	[xmlParser setDelegate:nvramXmlParser];
	bool retVal = [xmlParser parse];
	[xmlParser release];
	
	if (!retVal)
		return nil;
	
	return nvramXmlParser;
}

-(id)init
{
	if ((self = [super init]))
	{
		_rootArray = nil;
		_array = nil;
		_dictionary = nil;
		_key = nil;
		_elementName = nil;
		_lastElementName = nil;
	}
	
	return self;
}

- (void)dealloc
{
	[super dealloc];
}

-(void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
	_elementName = elementName;
	NSMutableArray *newArray = nil;
	NSMutableDictionary *newDictionary = nil;
	
	if ([elementName isEqualToString:@"array"])
	{
		if (_lastElementName == nil)
		{
			_rootArray = _array = [NSMutableArray array];
		}
		else if ([_lastElementName isEqualToString:@"array"])
		{
			newArray = [NSMutableArray array];
			[_array addObject:newArray];
			_array = newArray;
		}
		else if ([_lastElementName isEqualToString:@"dict"])
		{
			_dictionary = [NSMutableDictionary dictionary];
			[_array addObject:_dictionary];
		}
		
		_lastElementName = elementName;
	}
	else if  ([elementName isEqualToString:@"dict"])
	{
		if ([_lastElementName isEqualToString:@"array"])
		{
			_dictionary = [NSMutableDictionary dictionary];
			[_array addObject:_dictionary];
		}
		else if ([_lastElementName isEqualToString:@"dict"])
		{
			newDictionary = [NSMutableDictionary dictionary];
			[_dictionary setValue:newDictionary forKey:_key];
			_dictionary = newDictionary;
		}
		
		_lastElementName = elementName;
	}
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
	if ([elementName isEqualToString:@"array"])
		_array = nil;
	else if ([elementName isEqualToString:@"dict"])
		_dictionary = nil;
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
	if  ([_elementName isEqualToString:@"key"])
		_key = [string retain];
	else if  ([_elementName isEqualToString:@"string"])
		[_dictionary setObject:string forKey:_key];
}

-(NSString *)getValue:(NSArray *)valueArray
{
	if (_rootArray == nil)
		return nil;
	
	id object = nil;
	
	for (int i = 0; i < valueArray.count; i++)
	{
		id value = valueArray[i];
		
		if (i == 0)
		{
			if (![value isKindOfClass:[NSNumber class]])
				return nil;
			
			uint32_t index = [value intValue];
			
			if (index >= _rootArray.count)
				return nil;
			
			object = _rootArray[index];
		}
		else
		{
			if (object == nil)
				return nil;
			
			if ([object isKindOfClass:[NSMutableArray class]])
			{
				NSMutableArray *array = (NSMutableArray *)object;
				
				if (![value isKindOfClass:[NSNumber class]])
					return nil;
				
				uint32_t index = [value intValue];
				
				if (index >= array.count)
					return nil;
				
				object = array[index];
				
				if (object == nil)
					return nil;
			}
			else if ([object isKindOfClass:[NSMutableDictionary class]])
			{
				NSMutableDictionary *dictionary = (NSMutableDictionary *)object;
				
				if (![valueArray[i] isKindOfClass:[NSString class]])
					return nil;
				
				NSString *key = value;
				
				object = [dictionary objectForKey:key];
				
				if (object == nil)
					return nil;
			}
		}
	}
	
	if (![object isKindOfClass:[NSString class]])
		return nil;
	
	return (NSString *)object;
}

@end
