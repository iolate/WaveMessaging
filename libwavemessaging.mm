#import <xpc/xpc.h>
#import "ObjectToXPC.h"

#define CUCKOO_XPC_NAME "com.apple.backboard.applicationstateconnection"

@class WaveMessaging;

typedef NSDictionary* (*WaveMessagingCallBack) (NSString* serviceName, NSDictionary* contents, BOOL reply);

@interface WaveMessaging : NSObject
@property (readonly, nonatomic) __attribute__((NSObject)) xpc_connection_t connection;
//@property (readwrite, strong, nonatomic) __attribute__((NSObject)) dispatch_queue_t dispatchQueue;
@property (readonly, strong, nonatomic) NSString* serviceName;
@property (nonatomic) WaveMessagingCallBack callback;
@end


@implementation WaveMessaging
@synthesize connection = _connection;
//@synthesize dispatchQueue = _dispatchQueue;
@synthesize serviceName = _serviceName;
@synthesize callback;

-(id)initWithConnection:(xpc_connection_t)connection andServiceName:(NSString *)serviceName{
    if ((self = [super init])) {
        _connection = (xpc_connection_t)xpc_retain(connection);
        _serviceName = [[NSString alloc] initWithString:serviceName];
        
        [self setupConnectionHandler];
    }
    return self;
}

-(void)setupConnectionHandler {
    xpc_connection_set_event_handler(self.connection, ^(xpc_object_t object) {
        xpc_type_t type = xpc_get_type(object);
        if ( type == XPC_TYPE_ERROR ) {
            NSError *xpcError = [NSError errorFromXPCObject:object];
            NSLog(@"## WM Error: %@", xpcError);
            xpcError = nil;
            
            return;
        }else if ( type == XPC_TYPE_DICTIONARY ) {
            xpc_object_t xWMType = xpc_dictionary_get_value(object, "WaveMessaging");
            if (xWMType == NULL || xWMType == XPC_BOOL_FALSE) return;
            
            NSDictionary* message = [[NSDictionary alloc] initWithXPCObject:object];
            NSString* messageServiceName = [message objectForKey:@"service-name"];
            if (![messageServiceName isEqualToString:self.serviceName]) {
                NSLog(@"####### WaveMessaging: incorrect message name %@ vs %@", messageServiceName, self.serviceName);
                [message release];
                return;
            }
            
            NSDictionary* contents = [message objectForKey:@"wm-contents"];
            BOOL needReply = [message objectForKey:@"wm-reply"] ? [[message objectForKey:@"wm-reply"] boolValue] : NO;
            
            NSDictionary* reply = self.callback(self.serviceName, contents, needReply);
            
            if (needReply) {
                xpc_object_t reply_message;
                if (reply) {
                    reply_message = [reply replyXPCObject:object];
                }else {
                    reply_message = xpc_dictionary_create_reply(object);
                    xpc_dictionary_set_bool(reply_message, "wm-nil", YES);
                }
                xpc_connection_t connection = xpc_dictionary_get_remote_connection(object);
                xpc_connection_send_message( connection, reply_message);
                xpc_release(reply_message);
            }
            
            [message release];
        }
        
    });
    
    //dispatch_queue_t queue = dispatch_queue_create( [self.serviceName UTF8String], 0 );
    //self.dispatchQueue = queue;
    //xpc_connection_set_target_queue( self.connection, self.dispatchQueue );
}

-(oneway void)release {
    [_serviceName release];
    _serviceName = nil;

    //dispatch_release(_dispatchQueue);
    //_dispatchQueue = nil;
    [super release];
    
    //Do not release _connection.
}
@end

static NSMutableDictionary* wavemessages = nil;
BOOL WaveMessagingStartService(NSString* serviceName, WaveMessagingCallBack callback) {
    
    if (serviceName == nil || [serviceName isEqualToString:@""]) return NO;
    
    if (wavemessages != nil && [[wavemessages allKeys] containsObject:serviceName]) {
        return NO;
    }
    
    xpc_connection_t xpcConnection = xpc_connection_create_mach_service(CUCKOO_XPC_NAME, nil, 0);
    WaveMessaging* wm = [[WaveMessaging alloc] initWithConnection:xpcConnection andServiceName:serviceName];
    xpc_release( xpcConnection );
    
    if (wavemessages == nil) {
        wavemessages = [[NSMutableDictionary alloc] init];
    }
    wm.callback = callback;
    
    [wavemessages setObject:wm forKey:serviceName];
    
    xpc_connection_resume(wm.connection);
    //dispatch_sync(wm.dispatchQueue, ^{  });
    
    xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_bool(message, "WaveMessaging", NO);
    xpc_dictionary_set_string(message, "service-name", [serviceName UTF8String]);
    xpc_connection_send_message(wm.connection, message);
    
    xpc_release( message );
    
    return YES;
}

BOOL WaveMessagingStopService(NSString* serviceName) {
    if (wavemessages != nil && [[wavemessages allKeys] containsObject:serviceName]) {
        WaveMessaging* wm = [wavemessages objectForKey:serviceName];
        xpc_connection_cancel(wm.connection);
        //dispatch_sync(wm.dispatchQueue, ^{  });
        [wavemessages removeObjectForKey:serviceName];
        [wm release];
        return YES;
    }else{
        return NO;
    }
}

BOOL WaveMessagingIsValidService(NSString* serviceName) {
    if (serviceName == nil || [serviceName isEqualToString:@""]) return NO;
    
    __block BOOL isValid = NO;
    
    dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
        xpc_dictionary_set_bool(message, "WaveMessaging", YES);
        xpc_dictionary_set_string(message, "service-name", [serviceName UTF8String]);
        xpc_dictionary_set_bool(message, "wm-isvalid-query", YES);
        
        xpc_connection_t xpcConnection = xpc_connection_create_mach_service(CUCKOO_XPC_NAME, nil, 0);
        xpc_connection_set_event_handler(xpcConnection, ^(xpc_object_t object) { });
        
        xpc_connection_resume(xpcConnection);
        
        xpc_object_t reply_object = xpc_connection_send_message_with_reply_sync( xpcConnection, message);
        
        xpc_object_t is_valid = xpc_dictionary_get_value(reply_object, "wm-isvalid");
        if (is_valid != NULL && is_valid == XPC_BOOL_TRUE) {
            isValid = YES;
        }else {
            isValid = NO;
        }
        
        xpc_release( message );
        xpc_release( xpcConnection );
    });
    
    return isValid;
}

BOOL WaveMessagingSendMessage(NSString* serviceName, NSDictionary* contents) {
    if (serviceName == nil || [serviceName isEqualToString:@""]) return NO;
    
    if (![contents respondsToSelector:@selector(XPCObject)]) {
        return NO;
    }
    xpc_object_t contents_object = [contents XPCObject];
    if (contents_object == NULL) {
        return NO;
    }
    
    dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
        xpc_dictionary_set_bool(message, "WaveMessaging", YES);
        xpc_dictionary_set_string(message, "service-name", [serviceName UTF8String]);
        xpc_dictionary_set_bool(message, "wm-reply", NO);
        xpc_dictionary_set_value(message, "wm-contents", contents_object);
        
        xpc_connection_t xpcConnection = xpc_connection_create_mach_service(CUCKOO_XPC_NAME, nil, 0);
        xpc_connection_set_event_handler(xpcConnection, ^(xpc_object_t object) { });
        
        xpc_connection_resume(xpcConnection);
        xpc_connection_send_message( xpcConnection, message);
        
        xpc_release( contents_object );
        xpc_release( message );
        xpc_release( xpcConnection );
        
    });
        
    return YES;
}

NSDictionary* WaveMessagingSendMessageWithReply(NSString* serviceName, NSDictionary* contents) {
    if (serviceName == nil || [serviceName isEqualToString:@""]) return nil;
    
    if (![contents respondsToSelector:@selector(XPCObject)]) {
        return nil;
    }
    xpc_object_t contents_object = [contents XPCObject];
    if (contents_object == NULL) {
        return nil;
    }

    __block NSDictionary* replyDictionary = nil;

    dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
        xpc_dictionary_set_bool(message, "WaveMessaging", YES);
        xpc_dictionary_set_string(message, "service-name", [serviceName UTF8String]);
        xpc_dictionary_set_bool(message, "wm-reply", YES);
        xpc_dictionary_set_value(message, "wm-contents", contents_object);
        
        xpc_connection_t xpcConnection = xpc_connection_create_mach_service(CUCKOO_XPC_NAME, nil, 0);
        xpc_connection_set_event_handler(xpcConnection, ^(xpc_object_t object) { });
        
        xpc_connection_resume(xpcConnection);
        
        xpc_object_t reply_object = xpc_connection_send_message_with_reply_sync( xpcConnection, message);
        
        xpc_object_t reply_contents = xpc_dictionary_get_value(reply_object, "reply");
        
        if (reply_contents != NULL) {
            xpc_object_t isNil = xpc_dictionary_get_value(reply_contents, "wm-nil");
            if (isNil != NULL && isNil == XPC_BOOL_TRUE) {
                //Already....
                //replyDictionary = nil;
            }else{
                replyDictionary = [[NSDictionary alloc] initWithXPCObject:reply_contents];
            }
        }
        
        xpc_release( contents_object );
        xpc_release( message );
        xpc_release( xpcConnection );
    });
        
    return [replyDictionary autorelease];
}