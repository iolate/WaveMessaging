#import <substrate.h>
#import <xpc/xpc.h>
#import "ObjectToXPC.h"

#define CUCKOO_XPC_NAME "com.apple.backboard.applicationstateconnection"

@interface BKApplicationStateServer
+ (id)sharedInstance;
- (void)_removeClientConnection:(id)arg1;
@end

#if 0 //iOS 7.0.4
@interface BKApplicationStateServer
- (id)_clientForConnection:(id)arg1;
- (NSMutableSet *)_clients;
@end
@implementation BKApplicationStateServer
-(void)_addClientConnection:(id)arg1 {
    BKApplicationStateServerClient* client = [BKApplicationStateServerClient clientWithConnection:arg1];
    NSMutableSet* _clients = [self _clients];
    [_clients addObject:client];
    
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    xpc_connection_set_target_queue(arg1, queue);
    xpc_connection_set_event_handler(arg1, ^(xpc_object_t object) {
        xpc_retain(object);
        
        dispatch_async(self->_queue, ^{
            NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
            xpc_type_t type = xpc_get_type( object );
            
            if ( type == XPC_TYPE_ERROR ) {
                [self _removeClientConnection:arg1];
            }else if ( type == XPC_TYPE_DICTIONARY ) {

            }
            
            [self _handleMessage:object];
            
            [pool release];
            xpc_release(object);
        });
    });
    
    if (self->_connectionResumed) {
        xpc_connection_resume(arg1);
    }
}
-(void)_removeClientConnection:(id)arg1 {
    BKApplicationStateServerClient* client = [self _clientForConnection:arg1];
    
    if (client == nil) return;
        
    [client invalidate];
    NSMutableSet* _clients = [self _clients];
    [_clients removeObject:client];
}
@end

@interface BKApplicationStateServerClient
@property(retain, nonatomic) BKSBasicServerClient *connectionWrapper;
- (void)invalidate;
@end
@implementation BKApplicationStateServerClient
-(void)invalidate {
    [[self connectionWrapper] invalidate];
}
@end

@interface BKSBasicServerClient
- (void)invalidate;
- (id)connection;
@end
@implementation BKSBasicServerClient
-(void)invalidate {
    id connection = [self connection];
    if (connection) xpc_connection_cancel(connection);
}
@end
#endif

@interface WMXPCConnection : NSObject
@property (nonatomic) __attribute__((NSObject)) xpc_connection_t connection;
@property (nonatomic, strong) NSString* serviceName;
@end

@implementation WMXPCConnection
@synthesize connection = _connection;

-(id)initWithConnection:(xpc_connection_t)connection {
    if ((self = [super init])) {
        _connection = (xpc_connection_t)xpc_retain(connection);
    }
    return self;
}

-(oneway void)release {
    /*
     https://developer.apple.com/library/mac/documentation/darwin/reference/manpages/man3/xpc_connection_cancel.3.html
     Note that, if a connection receives XPC_ERROR_CONNECTION_INVALID in its event handler due to other cir-cumstances, circumstances,
     cumstances, it is already in a canceled state, and therefore a call to xpc_connection_cancel() is
     unnecessary (but harmless) in this case.
     */
    //_xpc_connection_cancel(_connection);
    //_connection = nil;
    
    [super release];
}
@end

static NSMutableDictionary* wmservices = nil;
MSHook(void, xpc_connection_cancel, xpc_connection_t connection) {
    if (wmservices != nil) {
        for (WMXPCConnection* wmc in [wmservices allValues]) {
            if ([wmc connection] == connection) {
                //NSLog(@"#### WM: This is For WM. Block cancel message.");
                return;
            }
        }
    }
    
    _xpc_connection_cancel(connection);
}

#if 0
void original_handler(xpc_object_t object) {
    xpc_retain(object);
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    
    xpc_type_t type = xpc_get_type(object);
    if (type == XPC_TYPE_ERROR) {
        if (object == XPC_ERROR_CONNECTION_INTERRUPTED) {
            
        }else if (object == XPC_ERROR_CONNECTION_INVALID) {
            [self _removeClientConnection:object];
        }
    }else if (type == XPC_TYPE_CONNECTION) {
        [self _addClientConnection:object];
    }
    [pool release];
    xpc_release(object);
}
#endif

#define REMOVE_FROM_CLIENTS_LIST(c) dispatch_async(MSHookIvar<dispatch_queue_t>([NSClassFromString(@"BKApplicationStateServer") sharedInstance], "_queue"), ^{[[NSClassFromString(@"BKApplicationStateServer") sharedInstance] _removeClientConnection:(id)c]; });

static BOOL handler_my_turn = NO;
MSHook(void, xpc_connection_set_event_handler, xpc_connection_t connection, xpc_handler_t handler) {
    
    char* name = (char*)xpc_connection_get_name( connection );
    
    if (name != NULL) {
        if (!strcmp(CUCKOO_XPC_NAME, name)) {

            xpc_handler_t original_handler = Block_copy(handler);
            handler = ^(xpc_object_t object) {
                xpc_type_t type = xpc_get_type( object );
                if ( type == XPC_TYPE_CONNECTION ) {
                    handler_my_turn = YES;
                }
                original_handler(object); //-> [ _addClientConnection: ] -> xpc_connection_set_event_handler
            };
            
            _xpc_connection_set_event_handler(connection, handler);
            return;
        }
    }else if (name == NULL && handler_my_turn) {
        handler_my_turn = NO;
        __block BOOL isServer = NO;
        __block NSString* serviceName = nil;
        xpc_handler_t originalHandler = Block_copy(handler);
        
        handler = ^(xpc_object_t object) {
            xpc_type_t type = xpc_get_type( object );
            if ( type == XPC_TYPE_ERROR ) {
                //if ( object == XPC_ERROR_CONNECTION_INVALID ) {
                //} else if ( object == XPC_ERROR_CONNECTION_INTERRUPTED ) {
                //} else if ( object == XPC_ERROR_TERMINATION_IMMINENT ) { }
                if (isServer) {
                    if ([[wmservices allKeys] containsObject:serviceName]) {
                        WMXPCConnection* wmc = [wmservices objectForKey:serviceName];
                        [wmservices removeObjectForKey:serviceName];
                        [wmc release];
                    }
                }
            }else if ( type == XPC_TYPE_DICTIONARY ) {
                xpc_object_t xWMType = xpc_dictionary_get_value(object, "WaveMessaging");
                if (xWMType != NULL) {
                    
                    xpc_object_t service_name_object = xpc_dictionary_get_value(object, "service-name");
                    if (xpc_get_type(service_name_object) == XPC_TYPE_STRING) {
                        const char *service_name_char = xpc_string_get_string_ptr(service_name_object);
                        if (!serviceName) {
                            serviceName = [[NSString alloc] initWithUTF8String:service_name_char];
                        }
                        
                        if (xWMType == XPC_BOOL_FALSE) {
                            // ############## Server
                            
                            if ([[wmservices allKeys] containsObject:serviceName]) {
                                //error
                                NSLog(@"#### WaveMessaging: Service was already assigned.");
                            }else{
                                isServer = YES;
                                WMXPCConnection* wmc = [[WMXPCConnection alloc] initWithConnection:connection];
                                [wmservices setObject:wmc forKey:serviceName];
                            }
                            
                            REMOVE_FROM_CLIENTS_LIST(connection);
                            return;
                        }else if (xWMType == XPC_BOOL_TRUE) {
                            // ############## Client
                            xpc_object_t is_valid = xpc_dictionary_get_value(object, "wm-isvalid-query");
                            if (is_valid != NULL && is_valid == XPC_BOOL_TRUE) {
                                // ############## WaveMessagingIsValidService
                                BOOL isValid = [[wmservices allKeys] containsObject:serviceName];
                                xpc_object_t reply_message = xpc_dictionary_create_reply(object);
                                xpc_dictionary_set_bool(reply_message, "wm-isvalid", isValid);
                                xpc_connection_send_message( connection, reply_message);
                                xpc_release(reply_message);
                                REMOVE_FROM_CLIENTS_LIST(connection);
                                return;
                            }
                            
                            if (![[wmservices allKeys] containsObject:serviceName]) {
                                
                                xpc_object_t is_reply = xpc_dictionary_get_value(object, "wm-reply");
                                if (is_reply != NULL && is_reply == XPC_BOOL_TRUE) {
                                    xpc_object_t reply_message = xpc_dictionary_create_reply(object);
                                    xpc_dictionary_set_bool(reply_message, "wm-error", YES);
                                    xpc_connection_send_message( connection, reply_message);
                                    xpc_release(reply_message);
                                }
                            }else{
                                xpc_object_t is_reply = xpc_dictionary_get_value(object, "wm-reply");
                                WMXPCConnection* server = [wmservices objectForKey:serviceName];
                                
                                if (is_reply != NULL && is_reply == XPC_BOOL_TRUE) {
                                    xpc_object_t message = xpc_copy(object);
                                    xpc_object_t reply_object = xpc_connection_send_message_with_reply_sync( server.connection, message);
                                    
                                    xpc_type_t type2 = xpc_get_type( reply_object );
                                    if ( type2 == XPC_TYPE_DICTIONARY ) {
                                        xpc_object_t reply_message = xpc_dictionary_create_reply(object);
                                        xpc_dictionary_set_value(reply_message,"reply", reply_object);
                                        xpc_connection_send_message( connection, reply_message);
                                        xpc_release(reply_message);
                                    }else{
                                        xpc_object_t reply_message = xpc_dictionary_create_reply(object);
                                        xpc_dictionary_set_bool(reply_message, "wm-error", YES);
                                        xpc_connection_send_message( connection, reply_message);
                                        xpc_release(reply_message);
                                    }
                                    xpc_release( message );
                                }else {
                                    xpc_connection_send_message(server.connection, object);
                                }
                            }
                            REMOVE_FROM_CLIENTS_LIST(connection);
                            return;
                        }else {
                            NSLog(@"#### WaveMessaging: WaveMessaging is not BOOL");
                        }
                    }
                    // ############## Error...?
                    return;
                }
                //orig
            }
            
            originalHandler(object);
        };
    }
    
    _xpc_connection_set_event_handler(connection, handler);
}

MSInitialize {
    wmservices = [[NSMutableDictionary alloc] init];
    MSHookFunction(xpc_connection_set_event_handler, MSHake(xpc_connection_set_event_handler));
    MSHookFunction(xpc_connection_cancel, MSHake(xpc_connection_cancel));
}