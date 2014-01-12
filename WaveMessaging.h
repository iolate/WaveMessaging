/*
 *  WaveMessaging ( kr.iolate.wavemessaging )
 *
 *  iolate ( iolate@me.com )
 *  Twitter: @iolate_e
 *
 *  2014. Jan. 2.
 *
 */

#if 0
#define WM_SERVICE_NAME @"kr.iolate.wavemessaging.example"

//############ Server Example ############
static NSDictionary* wmCallBack(NSString* serviceName, NSDictionary* contents, BOOL reply) {
    
    if (reply) {
        ...
        //Client waits for receiving reply data.
        //You can return nil; too.
    }
    return nil;
}

+(void)load {
    WaveMessagingStartService(WM_SERVICE_NAME, wmCallBack);
}
//########################################


//############ Client Example ############
-(void)sendMessage {
    if (!WaveMessagingIsValidService(WM_SERVICE_NAME)) return;
    
    NSDictionary* message;
    //one way
    WaveMessagingSendMessage(WM_SERVICE_NAME, message);
    //reply
    NSDictionary* replyDate = WaveMessagingSendMessageWithReply(WM_SERVICE_NAME, message);
}
//########################################
#endif

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif
    
typedef NSDictionary* (*WaveMessagingCallBack) (NSString* serviceName, NSDictionary* contents, BOOL reply);
BOOL WaveMessagingStartService(NSString* serviceName, WaveMessagingCallBack callback);
BOOL WaveMessagingStopService(NSString* serviceName);

BOOL WaveMessagingIsValidService(NSString* serviceName);
BOOL WaveMessagingSendMessage(NSString* serviceName, NSDictionary* contents);
NSDictionary* WaveMessagingSendMessageWithReply(NSString* serviceName, NSDictionary* contents);

#ifdef __cplusplus
} // extern "C"
#endif