//
//  CefWrapper.h
//  Pods
//
//  Created by Hao Linwei on 2022/8/18.
//

#ifndef CefWrapper_h
#define CefWrapper_h
#import <FlutterMacOS/FlutterMacOS.h>

extern NSObject<FlutterTextureRegistry>* tr;
extern CGFloat scaleFactor;

@interface EventsStreamHandler : NSObject<FlutterStreamHandler>
@property (nonatomic, strong) FlutterEventSink events;
- (void)sendEvents:(NSDictionary *)dic;
@end

extern EventsStreamHandler *evHandler;

@interface CefWrapper : NSObject<FlutterTexture>

+ (void)setMethodChannel: (FlutterMethodChannel*)channel;
+ (void) handleMethodCallWrapper: (FlutterMethodCall*)call result:(FlutterResult)result;

@end

#endif /* CefWrapper_h */
