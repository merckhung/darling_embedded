// SPDX-License-Identifier: GPL-3.0-or-later
#ifndef DARLING_EMBEDDED_FOUNDATION_FOUNDATION_H_
#define DARLING_EMBEDDED_FOUNDATION_FOUNDATION_H_

#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <objc/message.h>
#include <objc/objc.h>
#include <objc/runtime.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>

typedef long NSInteger;
typedef unsigned long NSUInteger;
typedef double NSTimeInterval;

enum {
  NSASCIIStringEncoding = 1,
  NSUTF8StringEncoding = 4,
  NSISOLatin1StringEncoding = 5,
  NSMacOSRomanStringEncoding = 30,
};

typedef struct _NSRange {
  NSUInteger location;
  NSUInteger length;
} NSRange;

static inline NSRange NSMakeRange(NSUInteger loc, NSUInteger len) {
  NSRange r = {loc, len};
  return r;
}

#define NSNotFound ((NSInteger)0x7fffffffffffffffL)

#ifdef __cplusplus
extern "C" {
#endif

Class NSClassFromString(id aClassName);
SEL NSSelectorFromString(id aSelectorName);
void NSLog(id format, ...);

#ifdef __cplusplus
}
#endif

#ifdef __OBJC__

__attribute__((objc_root_class))
@interface NSObject {
 @public
  Class isa;
}
+ (Class)class;
+ (Class)superclass;
+ (instancetype)alloc;
+ (instancetype)new;
- (instancetype)init;
- (void)dealloc;
- (id)retain;
- (oneway void)release;
- (id)autorelease;
- (NSUInteger)retainCount;
- (Class)class;
- (Class)superclass;
- (BOOL)isEqual:(id)object;
- (BOOL)isKindOfClass:(Class)aClass;
- (BOOL)respondsToSelector:(SEL)aSelector;
- (id)performSelector:(SEL)aSelector;
- (id)performSelector:(SEL)aSelector withObject:(id)object;
- (id)performSelector:(SEL)aSelector withObject:(id)object1 withObject:(id)object2;
- (id)copy;
- (id)description;
@end

@interface NSObject (NSDelayedPerforming)
- (void)performSelector:(SEL)aSelector withObject:(id)anArgument afterDelay:(NSTimeInterval)delay;
@end

@interface NSAutoreleasePool : NSObject {
  void* _token;
}
+ (void)addObject:(id)anObject;
- (void)addObject:(id)anObject;
- (void)drain;
@end

@interface NSString : NSObject {
 @public
  uint32_t _flags;
  const char* _cstr;
  long _length;
}
+ (instancetype)string;
+ (instancetype)stringWithUTF8String:(const char*)nullTerminatedCString;
+ (instancetype)stringWithCString:(const char*)cString
                         encoding:(NSUInteger)enc;
+ (instancetype)stringWithFormat:(NSString*)format, ...;
- (instancetype)copy;
- (instancetype)initWithUTF8String:(const char*)nullTerminatedCString;
- (instancetype)initWithData:(id)data encoding:(NSUInteger)encoding;
- (instancetype)initWithFormat:(NSString*)format, ...;
- (const char*)UTF8String;
- (NSUInteger)length;
- (BOOL)isEqualToString:(NSString*)aString;
- (BOOL)hasPrefix:(NSString*)aString;
- (NSString*)lastPathComponent;
- (id)dataUsingEncoding:(NSUInteger)encoding;
- (int)intValue;
- (double)doubleValue;
@end

@class NSArray;
@class NSCharacterSet;

@interface NSString (DarlingAdditions)
+ (instancetype)stringWithString:(NSString*)aString;
+ (instancetype)stringWithContentsOfFile:(NSString*)path encoding:(NSUInteger)enc error:(id*)error;
- (instancetype)initWithString:(NSString*)aString;
- (instancetype)initWithBytes:(const void*)bytes length:(NSUInteger)len encoding:(NSUInteger)enc;
- (NSString*)substringFromIndex:(NSUInteger)from;
- (NSString*)substringToIndex:(NSUInteger)to;
- (NSString*)substringWithRange:(NSRange)range;
- (NSRange)rangeOfString:(NSString*)searchString;
- (BOOL)hasSuffix:(NSString*)aString;
- (NSArray*)componentsSeparatedByString:(NSString*)separator;
- (NSArray*)componentsSeparatedByCharactersInSet:(NSCharacterSet*)set;
- (NSString*)stringByAppendingString:(NSString*)aString;
- (NSString*)stringByAppendingPathComponent:(NSString*)component;
- (NSString*)stringByDeletingLastPathComponent;
- (NSString*)pathExtension;
- (NSString*)stringByReplacingOccurrencesOfString:(NSString*)target withString:(NSString*)replacement;
- (NSString*)stringByTrimmingCharactersInSet:(NSCharacterSet*)set;
- (const char*)cStringUsingEncoding:(NSUInteger)encoding;
- (const char*)fileSystemRepresentation;
- (float)floatValue;
- (BOOL)boolValue;
- (NSInteger)integerValue;
- (long long)longLongValue;
- (unsigned short)characterAtIndex:(NSUInteger)index;
- (NSString*)lowercaseString;
- (NSString*)uppercaseString;
- (id)mutableCopy;
@end

@interface NSMutableString : NSString
+ (instancetype)stringWithCapacity:(NSUInteger)capacity;
- (void)appendString:(NSString*)aString;
- (void)appendFormat:(NSString*)format, ...;
- (void)insertString:(NSString*)aString atIndex:(NSUInteger)loc;
- (void)setString:(NSString*)aString;
- (void)replaceCharactersInRange:(NSRange)range withString:(NSString*)aString;
- (void)deleteCharactersInRange:(NSRange)range;
@end

@interface NSCharacterSet : NSObject {
 @public
  unsigned char _bits[32];
}
+ (NSCharacterSet*)characterSetWithCharactersInString:(NSString*)aString;
+ (NSCharacterSet*)whitespaceCharacterSet;
+ (NSCharacterSet*)whitespaceAndNewlineCharacterSet;
+ (NSCharacterSet*)newlineCharacterSet;
- (BOOL)characterIsMember:(unsigned short)aCharacter;
@end

@interface NSConstantString : NSString
@end

@interface NSNumber : NSObject {
  double _doubleVal;
  long long _intVal;
  BOOL _isFloat;
}
+ (NSNumber*)numberWithInt:(int)value;
+ (NSNumber*)numberWithLongLong:(long long)value;
+ (NSNumber*)numberWithDouble:(double)value;
+ (NSNumber*)numberWithBool:(BOOL)value;
- (int)intValue;
- (long long)longLongValue;
- (double)doubleValue;
- (BOOL)boolValue;
- (NSString*)stringValue;
@end

typedef struct {
  unsigned long state;
  id* itemsPtr;
  unsigned long* mutationsPtr;
  unsigned long extra[5];
} NSFastEnumerationState;

@interface NSArray : NSObject {
  void* _items;
}
+ (instancetype)array;
+ (instancetype)arrayWithObjects:(const id*)objects count:(NSUInteger)cnt;
- (NSUInteger)count;
- (id)objectAtIndex:(NSUInteger)index;
- (id)lastObject;
- (id)objectAtIndexedSubscript:(NSUInteger)idx;
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState*)state
                                 objects:(id*)buffer
                                   count:(NSUInteger)len;
@end

@interface NSArray (DarlingAdditions)
+ (instancetype)arrayWithObject:(id)anObject;
+ (instancetype)arrayWithArray:(NSArray*)array;
- (id)firstObject;
- (NSUInteger)indexOfObject:(id)anObject;
- (BOOL)containsObject:(id)anObject;
- (id)mutableCopy;
- (NSString*)componentsJoinedByString:(NSString*)separator;
@end

@interface NSMutableArray : NSArray
+ (instancetype)arrayWithCapacity:(NSUInteger)numItems;
- (void)addObject:(id)anObject;
- (void)removeAllObjects;
- (void)addObjectsFromArray:(NSArray*)otherArray;
- (void)insertObject:(id)anObject atIndex:(NSUInteger)index;
- (void)removeObjectAtIndex:(NSUInteger)index;
- (void)removeLastObject;
- (void)removeObject:(id)anObject;
@end

@interface NSDictionary : NSObject {
 @public
  void* _map;
}
+ (instancetype)dictionary;
+ (instancetype)dictionaryWithContentsOfFile:(NSString*)path;
+ (instancetype)dictionaryWithObjects:(const id*)objects forKeys:(const id*)keys count:(NSUInteger)cnt;
- (NSUInteger)count;
- (id)objectForKey:(id)aKey;
- (id)objectForKeyedSubscript:(id)aKey;
@end

@interface NSDictionary (DarlingAdditions)
- (NSArray*)allKeys;
- (NSArray*)allValues;
@end

@interface NSMutableDictionary : NSDictionary
- (void)setObject:(id)anObject forKey:(id)aKey;
- (void)setObject:(id)anObject forKeyedSubscript:(id)aKey;
- (void)removeObjectForKey:(id)aKey;
@end

@interface NSBundle : NSObject {
  NSString* _bundlePath;
  NSDictionary* _infoDict;
}
+ (NSBundle*)mainBundle;
+ (NSBundle*)bundleWithPath:(NSString*)path;
- (instancetype)initWithPath:(NSString*)path;
- (NSString*)bundlePath;
- (NSString*)executablePath;
- (NSString*)bundleIdentifier;
- (NSString*)pathForResource:(NSString*)name ofType:(NSString*)ext;
- (NSDictionary*)infoDictionary;
- (id)objectForInfoDictionaryKey:(NSString*)key;
@end

@interface NSBundle (DarlingAdditions)
- (NSString*)resourcePath;
@end

@interface NSProcessInfo : NSObject {
  NSString* _processName;
}
+ (NSProcessInfo*)processInfo;
- (NSString*)processName;
- (NSString*)hostName;
- (NSString*)operatingSystemVersionString;
- (NSUInteger)processorCount;
- (unsigned long long)physicalMemory;
- (NSTimeInterval)systemUptime;
- (int)processIdentifier;
@end

@interface NSTimer : NSObject {
 @public
  NSTimeInterval _interval;
  NSTimeInterval _nextFire;
  id _target;
  SEL _selector;
  id _userInfo;
  BOOL _repeats;
  BOOL _valid;
}
+ (NSTimer*)scheduledTimerWithTimeInterval:(NSTimeInterval)ti
                                    target:(id)aTarget
                                  selector:(SEL)aSelector
                                  userInfo:(id)userInfo
                                   repeats:(BOOL)yesOrNo;
- (void)fire;
- (void)invalidate;
- (BOOL)isValid;
- (id)userInfo;
@end

@interface NSData : NSObject {
 @public
  const void* _bytes;
  NSUInteger _length;
}
+ (instancetype)data;
+ (instancetype)dataWithBytes:(const void*)bytes length:(NSUInteger)length;
- (const void*)bytes;
- (NSUInteger)length;
@end

@interface NSMutableData : NSData
@end

@interface NSFileManager : NSObject
+ (NSFileManager*)defaultManager;
- (BOOL)fileExistsAtPath:(NSString*)path;
@end

@interface NSFileManager (DarlingAdditions)
- (BOOL)fileExistsAtPath:(NSString*)path isDirectory:(BOOL*)isDirectory;
- (BOOL)isReadableFileAtPath:(NSString*)path;
- (BOOL)isWritableFileAtPath:(NSString*)path;
- (BOOL)isExecutableFileAtPath:(NSString*)path;
- (NSString*)currentDirectoryPath;
@end

@interface NSUserDefaults : NSObject
+ (NSUserDefaults*)standardUserDefaults;
- (void)registerDefaults:(NSDictionary*)registrationDictionary;
- (id)objectForKey:(NSString*)defaultName;
- (void)setObject:(id)value forKey:(NSString*)defaultName;
- (BOOL)boolForKey:(NSString*)defaultName;
- (void)setBool:(BOOL)value forKey:(NSString*)defaultName;
- (float)floatForKey:(NSString*)defaultName;
- (NSInteger)integerForKey:(NSString*)defaultName;
@end

@interface NSNotification : NSObject {
 @public
  NSString* _name;
  id _object;
  NSDictionary* _userInfo;
}
+ (instancetype)notificationWithName:(NSString*)aName object:(id)anObject;
+ (instancetype)notificationWithName:(NSString*)aName object:(id)anObject userInfo:(NSDictionary*)aUserInfo;
- (NSString*)name;
- (id)object;
- (NSDictionary*)userInfo;
@end

@interface NSNotificationCenter : NSObject
+ (NSNotificationCenter*)defaultCenter;
- (void)addObserver:(id)observer selector:(SEL)aSelector name:(NSString*)aName object:(id)anObject;
- (void)postNotificationName:(NSString*)aName object:(id)anObject;
- (void)postNotificationName:(NSString*)aName object:(id)anObject userInfo:(NSDictionary*)aUserInfo;
- (void)postNotification:(NSNotification*)notification;
- (void)removeObserver:(id)observer;
- (void)removeObserver:(id)observer name:(NSString*)aName object:(id)anObject;
@end

#ifdef __cplusplus
extern "C" {
#endif
extern NSString* const NSFileHandleReadCompletionNotification;
extern NSString* const NSFileHandleNotificationDataItem;
extern NSString* const NSTaskDidTerminateNotification;
// Delivers pending NSFileHandle background reads and NSTask terminations;
// called from the application's run loop.
void _DarlingPollRunLoopSources(void);
#ifdef __cplusplus
}
#endif

@interface NSFileHandle : NSObject
+ (NSFileHandle*)fileHandleForReadingAtPath:(NSString*)path;
+ (NSFileHandle*)fileHandleWithNullDevice;
- (NSData*)readDataToEndOfFile;
- (NSData*)availableData;
- (void)readInBackgroundAndNotify;
- (int)fileDescriptor;
- (void)writeData:(NSData*)data;
- (void)closeFile;
@end

@interface NSPipe : NSObject
+ (NSPipe*)pipe;
- (NSFileHandle*)fileHandleForReading;
- (NSFileHandle*)fileHandleForWriting;
@end

@interface NSTask : NSObject
- (void)setLaunchPath:(NSString*)path;
- (void)setArguments:(NSArray*)arguments;
- (void)setStandardInput:(id)input;
- (void)setStandardOutput:(id)output;
- (void)setStandardError:(id)error;
- (void)setCurrentDirectoryPath:(NSString*)path;
- (void)setEnvironment:(NSDictionary*)environment;
- (id)standardInput;
- (id)standardOutput;
- (void)launch;
- (void)waitUntilExit;
- (void)terminate;
- (BOOL)isRunning;
- (int)processIdentifier;
- (int)terminationStatus;
@end

@interface NSPropertyListSerialization : NSObject
+ (id)propertyListWithData:(NSData*)data options:(NSUInteger)opt format:(void*)format error:(id*)error;
@end

@interface NSMutableDictionary (DarlingMoreMethods)
- (void)removeAllObjects;
@end

@interface NSAttributedString : NSObject {
 @public
  NSMutableString* _string;
  NSDictionary* _attributes;
}
- (instancetype)initWithString:(NSString*)str;
- (instancetype)initWithString:(NSString*)str attributes:(NSDictionary*)attrs;
- (NSString*)string;
- (NSUInteger)length;
@end

@interface NSIndexSet : NSObject {
 @public
  NSUInteger _first;
  NSUInteger _count;
}
+ (instancetype)indexSet;
+ (instancetype)indexSetWithIndex:(NSUInteger)value;
+ (instancetype)indexSetWithIndexesInRange:(NSRange)range;
- (NSUInteger)count;
- (NSUInteger)firstIndex;
- (NSUInteger)lastIndex;
- (BOOL)containsIndex:(NSUInteger)value;
@end

@interface NSDate : NSObject {
 @public
  NSTimeInterval _ti;
}
+ (instancetype)date;
+ (instancetype)dateWithTimeIntervalSinceNow:(NSTimeInterval)secs;
+ (instancetype)distantFuture;
+ (instancetype)distantPast;
+ (NSTimeInterval)timeIntervalSinceReferenceDate;
- (NSTimeInterval)timeIntervalSinceReferenceDate;
- (NSTimeInterval)timeIntervalSince1970;
- (NSTimeInterval)timeIntervalSinceNow;
@end

@interface NSError : NSObject {
 @public
  NSString* _domain;
  NSInteger _code;
  NSDictionary* _userInfo;
}
+ (instancetype)errorWithDomain:(NSString*)domain code:(NSInteger)code userInfo:(NSDictionary*)dict;
- (instancetype)initWithDomain:(NSString*)domain code:(NSInteger)code userInfo:(NSDictionary*)dict;
- (NSString*)domain;
- (NSInteger)code;
- (NSDictionary*)userInfo;
- (NSString*)localizedDescription;
- (NSString*)localizedFailureReason;
@end

#endif  // __OBJC__

#endif  // DARLING_EMBEDDED_FOUNDATION_FOUNDATION_H_
