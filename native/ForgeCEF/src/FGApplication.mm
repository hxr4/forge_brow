#import <Cocoa/Cocoa.h>

#include "include/cef_application_mac.h"

@interface FGApplication : NSApplication <CefAppProtocol>
@end

@implementation FGApplication {
  BOOL _handlingSendEvent;
}

- (BOOL)isHandlingSendEvent {
  return _handlingSendEvent;
}

- (void)setHandlingSendEvent:(BOOL)handlingSendEvent {
  _handlingSendEvent = handlingSendEvent;
}

- (void)sendEvent:(NSEvent *)event {
  CefScopedSendingEvent sendingEventScoper;
  [super sendEvent:event];
}

@end
