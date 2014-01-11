/**
 * ObjectToXPC
 *
 * Copyright 2011 Aron Cedercrantz. All rights reserved.
 * 
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 * 
 *   1. Redistributions of source code must retain the above copyright notice,
 *      this list of conditions and the following disclaimer.
 * 
 *   2. Redistributions in binary form must reproduce the above copyright notice,
 *      this list of conditions and the following disclaimer in the documentation
 *      and/or other materials provided with the distribution.
 * 
 * THIS SOFTWARE IS PROVIDED BY ARON CEDERCRANTZ ''AS IS'' AND ANY EXPRESS OR
 * IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
 * EVENT SHALL ARON CEDERCRANTZ OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 * INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 * 
 * The views and conclusions contained in the software and documentation are
 * those of the authors and should not be interpreted as representing official
 * policies, either expressed or implied, of Aron Cedercrantz.
 */
#import "ObjectToXPC.h"
#import "ObjectToXPC-Internal.h"

#define CD_FIX_CATEGORY_BUG WM_CD_FIX_CATEGORY_BUG

CD_FIX_CATEGORY_BUG(NSArray_CDXPC);
@implementation NSArray (CDXPC)

+ (id)arrayWithXPCObject:(xpc_object_t)xpcObject
{
	return [[[self class] alloc] initWithXPCObject:xpcObject];
}

- (id)initWithXPCObject:(xpc_object_t)xpcObject
{
	NSAssert(xpc_get_type(xpcObject) == XPC_TYPE_ARRAY, @"xpcObject must be of type XPC_TYPE_ARRAY.");
	
	NSUInteger capacity = xpc_array_get_count(xpcObject);
	NSMutableArray *newSelf = [[NSMutableArray alloc] initWithCapacity:capacity];
	
	if (newSelf) {
		xpc_array_apply(xpcObject, ^_Bool(size_t index, xpc_object_t value) {
			xpc_type_t valueType = xpc_get_type(value);
			
			if (valueType == XPC_TYPE_ARRAY) {
				NSArray *array = [[NSArray alloc] initWithXPCObject:value];
				[newSelf addObject:array];
			}
			else if (valueType == XPC_TYPE_BOOL ||
					 valueType == XPC_TYPE_DOUBLE ||
					 valueType == XPC_TYPE_INT64 ||
					 valueType == XPC_TYPE_UINT64) {
				NSNumber *boolNumber = [[NSNumber alloc] initWithXPCObject:value];
				[newSelf addObject:boolNumber];
			}
			else if (valueType == XPC_TYPE_DATA) {
				NSData *data = [[NSData alloc] initWithXPCObject:value];
				[newSelf addObject:data];
			}
			else if (valueType == XPC_TYPE_DATE) {
				NSDate *date = [[NSDate alloc] initWithXPCObject:value];
				[newSelf addObject:date];
			}
			else if (valueType == XPC_TYPE_DICTIONARY) {
				NSDictionary *dictionary = [[NSDictionary alloc] initWithXPCObject:value];
				[newSelf addObject:dictionary];
			}
			else if (valueType == XPC_TYPE_NULL) {
				[newSelf addObject:[NSNull null]];
			}
			else if (valueType == XPC_TYPE_STRING) {
				NSString *string = [[NSString alloc] initWithXPCObject:value];
				[newSelf addObject:string];
			}
			else {
				char *valueDescription = xpc_copy_description(value);
				NSString *assertionString = [[NSString alloc] initWithFormat:@"Unsupported XPC object '%s'.", valueDescription];
				free(valueDescription);
#if DEBUG
				NSAssert(NO, assertionString);
#else
				NSLog(@"%@", assertionString);
#endif
			}
			
			return true;
		});
	}
	
	self = newSelf;
	return self;
}

- (xpc_object_t)XPCObject
{
	xpc_object_t resXpcArray = xpc_array_create(NULL, 0);
	
	for (id obj in self) {
		if ([obj respondsToSelector:@selector(XPCObject)]) {
			xpc_object_t xpcObj = [obj XPCObject];
			xpc_array_append_value(resXpcArray, xpcObj);
			xpc_release(xpcObj);
		}
		else if ([obj isKindOfClass:[NSNull class]]) {
			xpc_object_t nullObject = xpc_null_create();
			xpc_array_set_value(resXpcArray, XPC_ARRAY_APPEND, nullObject);
			xpc_release(nullObject);
		}
		else {
			NSString *assertionString = [[NSString alloc] initWithFormat:@"Could not create XPC version of object '%@' of type %@.", obj, [obj class]];
#if DEBUG
			NSAssert(NO, assertionString);
#else
			NSLog(@"%@", assertionString);
#endif
		}
	}
	
	return resXpcArray;
}

@end

CD_FIX_CATEGORY_BUG(NSData_CDXPC)
@implementation NSData (CDXPC)

+ (id)dataWithXPCObject:(xpc_object_t)xpcObject
{
	return [[[self class] alloc] initWithXPCObject:xpcObject];
}

- (id)initWithXPCObject:(xpc_object_t)xpcObject
{
	NSAssert(xpc_get_type(xpcObject) == XPC_TYPE_DATA, @"xpcObject must be of type XPC_TYPE_DATA");
	
	NSUInteger length = xpc_data_get_length(xpcObject);
	const void *dataPtr = xpc_data_get_bytes_ptr(xpcObject);
	return [self initWithBytes:dataPtr length:length];
}

- (xpc_object_t)XPCObject
{
	const void *dataPtr = [self bytes];
	NSUInteger length = [self length];
	xpc_object_t resXpcData = xpc_data_create(dataPtr, length);
	
	return resXpcData;
}

@end

CD_FIX_CATEGORY_BUG(NSDate_CDXPC)
@implementation NSDate (CDXPC)

+ (id)dateWithXPCObject:(xpc_object_t)xpcObject
{
	return [[[self class] alloc] initWithXPCObject:xpcObject];
}

- (id)initWithXPCObject:(xpc_object_t)xpcObject
{
	NSAssert(xpc_get_type(xpcObject) == XPC_TYPE_DATE, @"xpcObject must be of type XPC_TYPE_DATE");
	
	int64_t unixTimestamp = xpc_date_get_value(xpcObject);
	return [self initWithTimeIntervalSince1970:unixTimestamp];
}

- (xpc_object_t)XPCObject
{
	xpc_object_t resXpcDate = xpc_date_create([self timeIntervalSince1970]);
	return resXpcDate;
}

@end

CD_FIX_CATEGORY_BUG(NSDictionary_CDXPC)
@implementation NSDictionary (CDXPC)

+ (id)dictionaryWithXPCObject:(xpc_object_t)xpcObject
{
	return [[[self class] alloc] initWithXPCObject:xpcObject];
}

- (id)initWithXPCObject:(xpc_object_t)xpcObject
{
	NSAssert(xpc_get_type(xpcObject) == XPC_TYPE_DICTIONARY, @"xpcObject must be of type XPC_TYPE_DICTIONARY");
	
	NSUInteger capacity = xpc_dictionary_get_count(xpcObject);
	NSMutableDictionary *newSelf = [[NSMutableDictionary alloc] initWithCapacity:capacity];
	
	if (newSelf) {
		xpc_dictionary_apply(xpcObject, ^_Bool(const char *keyStr, xpc_object_t value) {
			NSString *key = [[NSString alloc] initWithUTF8String:keyStr];
			xpc_type_t valueType = xpc_get_type(value);
			id object = nil;
			
			if (valueType == XPC_TYPE_ARRAY) {
				object = [[NSArray alloc] initWithXPCObject:value];
				
			}
			else if (valueType == XPC_TYPE_BOOL ||
					 valueType == XPC_TYPE_DOUBLE ||
					 valueType == XPC_TYPE_INT64 ||
					 valueType == XPC_TYPE_UINT64) {
				object = [[NSNumber alloc] initWithXPCObject:value];
			}
			else if (valueType == XPC_TYPE_DATA) {
				object = [[NSData alloc] initWithXPCObject:value];
			}
			else if (valueType == XPC_TYPE_DATE) {
				object = [[NSDate alloc] initWithXPCObject:value];
			}
			else if (valueType == XPC_TYPE_DICTIONARY) {
				object = [[NSDictionary alloc] initWithXPCObject:value];
			}
			else if (valueType == XPC_TYPE_NULL) {
				object = [NSNull null];
			}
			else if (valueType == XPC_TYPE_STRING) {
				object = [[NSString alloc] initWithXPCObject:value];
			}
			else {
				char *valueDescription = xpc_copy_description(value);
				NSString *assertionString = [[NSString alloc] initWithFormat:@"Unsupported XPC object '%s'.", valueDescription];
				free(valueDescription);
#if DEBUG
				NSAssert(NO, assertionString);
#else
				NSLog(@"%@", assertionString);
#endif
			}
			
			if (object == nil) {
				object = [NSNull null];
			}
			[newSelf setValue:object forKey:key];
			
			return true;
		});
	}
	
	self = newSelf;
	return self;
}

- (xpc_object_t)XPCObject
{
	xpc_object_t resXpcDictionary = xpc_dictionary_create(NULL, NULL, 0);
	
	[self enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
		xpc_object_t xpcObj = NULL;
		
		if ([obj respondsToSelector:@selector(XPCObject)]) {
			xpcObj = [obj XPCObject];
		}
		else if ([obj isKindOfClass:[NSNull class]]) {
			xpcObj = xpc_null_create();
		}
		else {
			NSString *assertionString = [[NSString alloc] initWithFormat:@"Could not create XPC version of object '%@' of type %@.", obj, [obj class]];
#if DEBUG
			NSAssert(NO, assertionString);
#else
			NSLog(@"%@", assertionString);
#endif
		}
		
		if (xpcObj != NULL) {
			// Make sure the key is a string!
			if (![key isKindOfClass:[NSString class]]) {
				key = [key description];
			}
			const char *xpcKey = [key UTF8String];
			
			xpc_dictionary_set_value(resXpcDictionary, xpcKey, xpcObj);
			
			xpc_release(xpcObj);
		}
	}];
	
	return resXpcDictionary;
}

- (xpc_object_t)replyXPCObject:(xpc_object_t)object
{
	xpc_object_t resXpcDictionary = xpc_dictionary_create_reply(object);
	
	[self enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
		xpc_object_t xpcObj = NULL;
		
		if ([obj respondsToSelector:@selector(XPCObject)]) {
			xpcObj = [obj XPCObject];
		}
		else if ([obj isKindOfClass:[NSNull class]]) {
			xpcObj = xpc_null_create();
		}
		else {
			NSString *assertionString = [[NSString alloc] initWithFormat:@"Could not create XPC version of object '%@' of type %@.", obj, [obj class]];
#if DEBUG
			NSAssert(NO, assertionString);
#else
			NSLog(@"%@", assertionString);
#endif
		}
		
		if (xpcObj != NULL) {
			// Make sure the key is a string!
			if (![key isKindOfClass:[NSString class]]) {
				key = [key description];
			}
			const char *xpcKey = [key UTF8String];
			
			xpc_dictionary_set_value(resXpcDictionary, xpcKey, xpcObj);
			
			xpc_release(xpcObj);
		}
	}];
	
	return resXpcDictionary;
}

@end

CD_FIX_CATEGORY_BUG(NSNull_CDXPC)
@implementation NSNull (CDXPC)

+ (id)nullWithXPCObject:(xpc_object_t)xpcObject
{
	return [self null];
}

- (id)initWithXPCObject:(xpc_object_t)xpcObject
{
	return [[self class] null];
}

- (xpc_object_t)XPCObject
{
	xpc_object_t resXpcNull = xpc_null_create();
	return resXpcNull;
}

@end

CD_FIX_CATEGORY_BUG(NSNumber_CDXPC)
@implementation NSNumber (CDXPC)

+ (id)numberWithXPCObject:(xpc_object_t)xpcObject
{
	return [[[self class] alloc] initWithXPCObject:xpcObject];
}

- (id)initWithXPCObject:(xpc_object_t)xpcObject
{
	xpc_type_t objectType = xpc_get_type(xpcObject);
	NSAssert((objectType == XPC_TYPE_BOOL ||
			  objectType == XPC_TYPE_DOUBLE ||
			  objectType == XPC_TYPE_INT64 ||
			  objectType == XPC_TYPE_UINT64),
			 @"xpcObject must be one of; bool, double, int64 or uint64.");
	
	
	NSNumber *newSelf = nil;
	if (objectType == XPC_TYPE_BOOL) {
		_Bool boolValue = xpc_bool_get_value(xpcObject);
		newSelf = [[NSNumber alloc] initWithBool:boolValue];
	}
	else if (objectType == XPC_TYPE_DOUBLE) {
		double doubleValue = xpc_double_get_value(xpcObject);
		newSelf = [[NSNumber alloc] initWithDouble:doubleValue];
	}
	else if (objectType == XPC_TYPE_INT64) {
		int64_t int64Value = xpc_int64_get_value(xpcObject);
		newSelf = [[NSNumber alloc] initWithLongLong:int64Value];
	}
	else if (objectType == XPC_TYPE_UINT64) {
		uint64_t uint64Value = xpc_uint64_get_value(xpcObject);
		newSelf = [[NSNumber alloc] initWithUnsignedLongLong:uint64Value];
	}
	
	self = newSelf;
	return self;
}


- (xpc_object_t)XPCObject
{
	xpc_object_t resXpcNumber = NULL;
	
	// Bools
	if (strcmp([self objCType], "B") == 0) {
		resXpcNumber = xpc_bool_create(([self boolValue] == YES));
	}
	// Integers (all stored as an int64_t)
	else if (strcmp([self objCType], "c") == 0 ||
			 strcmp([self objCType], "i") == 0 ||
			 strcmp([self objCType], "s") == 0 ||
			 strcmp([self objCType], "l") == 0 ||
			 strcmp([self objCType], "q") == 0) {
		
		resXpcNumber = xpc_int64_create([self longLongValue]);
	}
	// Unsigned integers (all stored as an uint64_t)
	else if (strcmp([self objCType], "C") == 0 ||
			 strcmp([self objCType], "I") == 0 ||
			 strcmp([self objCType], "S") == 0 ||
			 strcmp([self objCType], "L") == 0 ||
			 strcmp([self objCType], "Q") == 0) {
		
		resXpcNumber = xpc_uint64_create([self unsignedLongLongValue]);
	}
	// Floats and doubles (all stored as an double)
	else if (strcmp([self objCType], "f")  == 0 ||
			 strcmp([self objCType], "d")  == 0) {
		
		resXpcNumber = xpc_double_create([self doubleValue]);
	}
	
	return resXpcNumber;
}

@end

CD_FIX_CATEGORY_BUG(NSString_CDXPC)
@implementation NSString (CDXPC)

+ (id)stringWithXPCObject:(xpc_object_t)xpcObject
{
	return [[[self class] alloc] initWithXPCObject:xpcObject];
}

- (id)initWithXPCObject:(xpc_object_t)xpcObject
{
	NSAssert(xpc_get_type(xpcObject) == XPC_TYPE_STRING, @"xpcObject must be of type XPC_TYPE_STRING");
	
	const char *xpcString = xpc_string_get_string_ptr(xpcObject);
	return [self initWithUTF8String:xpcString];
}

- (xpc_object_t)XPCObject
{
	xpc_object_t resXpcString = xpc_string_create([self UTF8String]);
	return resXpcString;
}

@end

CD_FIX_CATEGORY_BUG(NSError_CDXPC)
@implementation NSError (CDXPC)
+ (NSError *)errorFromXPCObject:(xpc_object_t)xpcObject {
    
    char *description = xpc_copy_description( xpcObject );
    NSError *xpcError = [NSError errorWithDomain:NSPOSIXErrorDomain code:EINVAL userInfo:@{
                                                                                           NSLocalizedDescriptionKey:
                                                                                               [NSString stringWithCString:description encoding:[NSString defaultCStringEncoding]] }];
    free( description );
    return xpcError;
}
@end