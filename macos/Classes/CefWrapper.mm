//
//  CefWrapper.m
//  Pods-Runner
//
//  Created by Hao Linwei on 2022/8/18.
//

#import "CefWrapper.h"
#import <Foundation/Foundation.h>
#import "include/wrapper/cef_library_loader.h"
#import "include/cef_app.h"
#import "../../common/webview_app.h"
#import "../../common/webview_handler.h"
#import "../../common/webview_cookieVisitor.h"
#import "../../common/webview_js_handler.h"

#include <thread>

CefRefPtr<WebviewHandler> handler(new WebviewHandler());
CefRefPtr<WebviewApp> app(new WebviewApp(handler));
CefMainArgs mainArgs;

NSObject<FlutterTextureRegistry>* tr;
CGFloat scaleFactor = 0.0;

EventsStreamHandler *evHandler;

static NSTimer* _timer;
static CVPixelBufferRef buf_cache;
static CVPixelBufferRef buf_temp;
dispatch_semaphore_t lock = dispatch_semaphore_create(1);

int64_t textureId;

FlutterMethodChannel* f_channel;

@implementation CefWrapper

+ (void)init {
    CefScopedLibraryLoader loader;
    
    if(!loader.LoadInMain()) {
        printf("load cef err");
    }
    
    CefMainArgs main_args;
    CefExecuteProcess(main_args, nullptr, nullptr);
}

+ (void)doMessageLoopWork {
    CefDoMessageLoopWork();
}

+ (void)startCef {
    textureId = [tr registerTexture:[CefWrapper alloc]];
    handler.get()->imePositionCallback = [](int x, int y, int w, int h){
        NSMutableDictionary *dic = [NSMutableDictionary dictionary];
        [dic setObject:[NSNumber numberWithInt:x] forKey:@"x"];
        [dic setObject:[NSNumber numberWithInt:y] forKey:@"y"];
        [dic setObject:[NSNumber numberWithInt:w] forKey:@"w"];
        [dic setObject:[NSNumber numberWithInt:h] forKey:@"h"];
        [evHandler sendEvents:dic];
    };
    handler.get()->onPaintCallback = [](const void* buffer, int32_t width, int32_t height) {
        NSDictionary* dic = @{
            (__bridge NSString*)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
            (__bridge NSString*)kCVPixelBufferIOSurfacePropertiesKey : @{},
            (__bridge NSString*)kCVPixelBufferOpenGLCompatibilityKey : @YES,
            (__bridge NSString*)kCVPixelBufferMetalCompatibilityKey : @YES,
        };
        
        static CVPixelBufferRef buf = NULL;
        CVPixelBufferCreate(kCFAllocatorDefault,  width,
                            height, kCVPixelFormatType_32BGRA,
                            (__bridge CFDictionaryRef)dic, &buf);
        
        //copy data
        CVPixelBufferLockBaseAddress(buf, 0);
        char *copyBaseAddress = (char *) CVPixelBufferGetBaseAddress(buf);
        
        //MUST align pixel to pixelBuffer. Otherwise cause render issue. see https://www.codeprintr.com/thread/6563066.html about 16 bytes align
        size_t bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(buf, 0);
        char* src = (char*) buffer;
        int actureRowSize = width * 4;
        for(int line = 0; line < height; line++) {
            memcpy(copyBaseAddress, src, actureRowSize);
            src += actureRowSize;
            copyBaseAddress += bytesPerRow;
        }
        CVPixelBufferUnlockBaseAddress(buf, 0);
        
        dispatch_semaphore_wait(lock, DISPATCH_TIME_FOREVER);
        if(buf_cache) {
            CVPixelBufferRelease(buf_cache);
        }
        buf_cache = buf;
        dispatch_semaphore_signal(lock);
        [tr textureFrameAvailable:textureId];
    };
    
    //url change cb
    handler.get()->onUrlChangedCb = [](std::string url) {
        [f_channel invokeMethod:@"urlChanged" arguments:[NSString stringWithCString:url.c_str() encoding:NSUTF8StringEncoding]];
    };
    //title change cb
    handler.get()->onTitleChangedCb = [](std::string title) {
        [f_channel invokeMethod:@"titleChanged" arguments:[NSString stringWithCString:title.c_str() encoding:NSUTF8StringEncoding]];
    };
    //allcookie visited cb
    handler.get()->onAllCookieVisitedCb = [](std::map<std::string, std::map<std::string, std::string>> cookies) {
        NSMutableDictionary * dict = [NSMutableDictionary dictionary];
        for(auto &cookie : cookies)
        {
            NSString * domain = [NSString stringWithCString:cookie.first.c_str() encoding:NSUTF8StringEncoding];
            NSMutableDictionary * tempdict = [NSMutableDictionary dictionary];
            for(auto &c : cookie.second)
            {
                NSString * key = [NSString stringWithCString:c.first.c_str() encoding:NSUTF8StringEncoding];
                NSString * val = [NSString stringWithCString:c.second.c_str() encoding:NSUTF8StringEncoding];
                tempdict[key] = val;
            }
            dict[domain] = tempdict;
        }
        [f_channel invokeMethod:@"allCookiesVisited" arguments:dict];
    };
    
    //urlcookie visited cb
    handler.get()->onUrlCookieVisitedCb = [](std::map<std::string, std::map<std::string, std::string>> cookies) {
        NSMutableDictionary * dict = [NSMutableDictionary dictionary];
        for(auto &cookie : cookies)
        {
            NSString * domain = [NSString stringWithCString:cookie.first.c_str() encoding:NSUTF8StringEncoding];
            NSMutableDictionary * tempdict = [NSMutableDictionary dictionary];
            for(auto &c : cookie.second)
            {
                NSString * key = [NSString stringWithCString:c.first.c_str() encoding:NSUTF8StringEncoding];
                NSString * val = [NSString stringWithCString:c.second.c_str() encoding:NSUTF8StringEncoding];
                tempdict[key] = val;
            }
            dict[domain] = tempdict;
        }
        [f_channel invokeMethod:@"urlCookiesVisited" arguments:dict];
    };

    //JavaScriptChannel called
 	handler.get()->onJavaScriptChannelMessage = [](std::string channelName, std::string message, std::string callbackId, std::string frameId) {
        NSMutableDictionary * dict = [NSMutableDictionary dictionary];
        dict[@"channel"] = [NSString stringWithCString:channelName.c_str() encoding:NSUTF8StringEncoding];
        dict[@"message"]  = [NSString stringWithCString:message.c_str() encoding:NSUTF8StringEncoding];
        dict[@"callbackId"]  = [NSString stringWithCString:callbackId.c_str() encoding:NSUTF8StringEncoding];
        dict[@"frameId"]  = [NSString stringWithCString:frameId.c_str() encoding:NSUTF8StringEncoding];
        [f_channel invokeMethod:@"javascriptChannelMessage" arguments:dict];
	};   

    CefSettings settings;
    settings.windowless_rendering_enabled = true;
    settings.external_message_pump = true;
    CefString(&settings.browser_subprocess_path) = "/Library/Chaches";
    
    CefInitialize(mainArgs, settings, app.get(), nullptr);
    _timer = [NSTimer timerWithTimeInterval:0.016f target:self selector:@selector(doMessageLoopWork) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer: _timer forMode:NSRunLoopCommonModes];
    
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent * _Nullable(NSEvent * _Nonnull event) {
        [self processKeyboardEvent:event];
        return event;
    }];
    
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyUp handler:^NSEvent * _Nullable(NSEvent * _Nonnull event) {
        [self processKeyboardEvent:event];
        return event;
    }];
}

+ (void)processKeyboardEvent: (NSEvent*) event {
    CefKeyEvent keyEvent;
    
    keyEvent.native_key_code = [event keyCode];
    keyEvent.modifiers = [self getModifiersForEvent:event];
    
    //handle backspace
    if(keyEvent.native_key_code == 51) {
        keyEvent.character = 0;
        keyEvent.unmodified_character = 0;
    } else {
        NSString* s = [event characters];
        if([s length] == 0) {
            keyEvent.type = KEYEVENT_KEYDOWN;
        } else {
            keyEvent.type = KEYEVENT_CHAR;
        }
        if ([s length] > 0)
            keyEvent.character = [s characterAtIndex:0];
        
        s = [event charactersIgnoringModifiers];
        if ([s length] > 0)
            keyEvent.unmodified_character = [s characterAtIndex:0];
        
        if([event type] == NSKeyUp) {
            keyEvent.type = KEYEVENT_KEYUP;
        }
    }
    
    handler.get()->sendKeyEvent(keyEvent);
}

+ (int)getModifiersForEvent:(NSEvent*)event {
    int modifiers = 0;
    
    if ([event modifierFlags] & NSControlKeyMask)
        modifiers |= EVENTFLAG_CONTROL_DOWN;
    if ([event modifierFlags] & NSShiftKeyMask)
        modifiers |= EVENTFLAG_SHIFT_DOWN;
    if ([event modifierFlags] & NSAlternateKeyMask)
        modifiers |= EVENTFLAG_ALT_DOWN;
    if ([event modifierFlags] & NSCommandKeyMask)
        modifiers |= EVENTFLAG_COMMAND_DOWN;
    if ([event modifierFlags] & NSAlphaShiftKeyMask)
        modifiers |= EVENTFLAG_CAPS_LOCK_ON;
    
    if ([event type] == NSKeyUp || [event type] == NSKeyDown ||
        [event type] == NSFlagsChanged) {
        // Only perform this check for key events
        //    if ([self isKeyPadEvent:event])
        //      modifiers |= EVENTFLAG_IS_KEY_PAD;
    }
    
    // OS X does not have a modifier for NumLock, so I'm not entirely sure how to
    // set EVENTFLAG_NUM_LOCK_ON;
    //
    // There is no EVENTFLAG for the function key either.
    
    // Mouse buttons
    switch ([event type]) {
        case NSLeftMouseDragged:
        case NSLeftMouseDown:
        case NSLeftMouseUp:
            modifiers |= EVENTFLAG_LEFT_MOUSE_BUTTON;
            break;
        case NSRightMouseDragged:
        case NSRightMouseDown:
        case NSRightMouseUp:
            modifiers |= EVENTFLAG_RIGHT_MOUSE_BUTTON;
            break;
        case NSOtherMouseDragged:
        case NSOtherMouseDown:
        case NSOtherMouseUp:
            modifiers |= EVENTFLAG_MIDDLE_MOUSE_BUTTON;
            break;
        default:
            break;
    }
    
    return modifiers;
}

+(void)sendScrollEvent:(int)x y:(int)y deltaX:(int)deltaX deltaY:(int)deltaY {
    handler.get()->sendScrollEvent(x, y, deltaX, deltaY);
}

+ (void)cursorClickUp:(int)x y:(int)y {
    handler.get()->cursorClick(x, y, true);
}

+ (void)cursorClickDown:(int)x y:(int)y {
    handler.get()->cursorClick(x, y, false);
}

+ (void)cursorMove:(int)x y:(int)y dragging:(bool)dragging {
    handler.get()->cursorMove(x, y, dragging);
}

+ (void)sizeChanged:(float)dpi width:(int)width height:(int)height {
    handler.get()->changeSize(dpi, width, height);
}

+ (void)loadUrl:(NSString*)url {
    handler.get()->loadUrl(std::string([url cStringUsingEncoding:NSUTF8StringEncoding]));
}

+ (void)goForward {
    handler.get()->goForward();
}

+ (void)goBack {
    handler.get()->goBack();
}

+ (void)reload {
    handler.get()->reload();
}

+ (void)openDevTools {
    handler.get()->openDevTools();
}

- (CVPixelBufferRef _Nullable)copyPixelBuffer {
    dispatch_semaphore_wait(lock, DISPATCH_TIME_FOREVER);
    buf_temp = buf_cache;
    CVPixelBufferRetain(buf_temp);
    dispatch_semaphore_signal(lock);
    return buf_temp;
}

+ (void)setMethodChannel: (FlutterMethodChannel*)channel {
    f_channel = channel;
}

+ (void)setCookie: (NSString *)domain key:(NSString *) key value:(NSString *)value {
    handler.get()->setCookie(std::string([domain cStringUsingEncoding:NSUTF8StringEncoding]), std::string([key cStringUsingEncoding:NSUTF8StringEncoding]), std::string([value cStringUsingEncoding:NSUTF8StringEncoding]));
}

+ (void)deleteCookie: (NSString *)domain key:(NSString *) key {
    handler.get()->deleteCookie(std::string([domain cStringUsingEncoding:NSUTF8StringEncoding]), std::string([key cStringUsingEncoding:NSUTF8StringEncoding]));
}

+ (void)visitAllCookies {
    handler.get()->visitAllCookies();
}

+ (void)visitUrlCookies: (NSString *)domain isHttpOnly:(bool)isHttpOnly {
    handler.get()->visitUrlCookies(std::string([domain cStringUsingEncoding:NSUTF8StringEncoding]), isHttpOnly);
}

+ (void) setJavaScriptChannels: (NSArray *)channels {
    std::vector<std::string> stdChannels;
    NSEnumerator * enumerator = [channels objectEnumerator];
    NSString * value;
    while (value = [enumerator nextObject]) {
        stdChannels.push_back(std::string([value cStringUsingEncoding:NSUTF8StringEncoding]));
    }
    handler.get()->setJavaScriptChannels(stdChannels);
}

+ (void) sendJavaScriptChannelCallBack: (bool)error  result:(NSString *)result callbackId:(NSString *)callbackId frameId:(NSString *)frameId {
    handler.get()->sendJavaScriptChannelCallBack(error, std::string([result cStringUsingEncoding:NSUTF8StringEncoding]), 
        std::string([callbackId cStringUsingEncoding:NSUTF8StringEncoding]), std::string([frameId cStringUsingEncoding:NSUTF8StringEncoding]));
}

+ (void) executeJavaScript: (NSString *)code {
    handler.get()->executeJavaScript(std::string([code cStringUsingEncoding:NSUTF8StringEncoding]));
}
@end


@implementation EventsStreamHandler

- (void)sendEvents:(NSDictionary *)dic {
    if(self.events != NULL) {
        self.events(dic);
    }
}

- (FlutterError * _Nullable)onCancelWithArguments:(id _Nullable)arguments {
    if (_events != NULL) {
        _events = NULL;
    }
    return nil;
}

- (FlutterError * _Nullable)onListenWithArguments:(id _Nullable)arguments eventSink:(nonnull FlutterEventSink)events {
    _events = events;
    return  nil;
}

@end
