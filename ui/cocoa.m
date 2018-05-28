/*
 * QEMU Cocoa CG display driver
 *
 * Copyright (c) 2008 Mike Kronenberg
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#include "qemu/osdep.h"

#import <Cocoa/Cocoa.h>
#include <crt_externs.h>

#include "qemu-common.h"
#include "ui/console.h"
#include "ui/input.h"
#include "sysemu/sysemu.h"
#include "qapi/error.h"
#include "qapi/qapi-commands.h"
#include "sysemu/blockdev.h"
#include "qemu-version.h"
#include <Carbon/Carbon.h>
#include "qom/cpu.h"

#ifndef MAC_OS_X_VERSION_10_10
#define MAC_OS_X_VERSION_10_10 101000
#endif
#ifndef MAC_OS_X_VERSION_10_12
#define MAC_OS_X_VERSION_10_12 101200
#endif

/* macOS 10.12 deprecated many constants, #define the new names for older SDKs */
#if MAC_OS_X_VERSION_MAX_ALLOWED < MAC_OS_X_VERSION_10_12
#define NSEventMaskAny                  NSAnyEventMask
#define NSEventModifierFlagCapsLock     NSAlphaShiftKeyMask
#define NSEventModifierFlagShift        NSShiftKeyMask
#define NSEventModifierFlagCommand      NSCommandKeyMask
#define NSEventModifierFlagControl      NSControlKeyMask
#define NSEventModifierFlagOption       NSAlternateKeyMask
#define NSEventTypeFlagsChanged         NSFlagsChanged
#define NSEventTypeKeyUp                NSKeyUp
#define NSEventTypeKeyDown              NSKeyDown
#define NSEventTypeMouseMoved           NSMouseMoved
#define NSEventTypeLeftMouseDown        NSLeftMouseDown
#define NSEventTypeRightMouseDown       NSRightMouseDown
#define NSEventTypeOtherMouseDown       NSOtherMouseDown
#define NSEventTypeLeftMouseDragged     NSLeftMouseDragged
#define NSEventTypeRightMouseDragged    NSRightMouseDragged
#define NSEventTypeOtherMouseDragged    NSOtherMouseDragged
#define NSEventTypeLeftMouseUp          NSLeftMouseUp
#define NSEventTypeRightMouseUp         NSRightMouseUp
#define NSEventTypeOtherMouseUp         NSOtherMouseUp
#define NSEventTypeScrollWheel          NSScrollWheel
#define NSTextAlignmentCenter           NSCenterTextAlignment
#define NSWindowStyleMaskBorderless     NSBorderlessWindowMask
#define NSWindowStyleMaskClosable       NSClosableWindowMask
#define NSWindowStyleMaskMiniaturizable NSMiniaturizableWindowMask
#define NSWindowStyleMaskTitled         NSTitledWindowMask
#endif

//#define DEBUG

#ifdef DEBUG
#define COCOA_DEBUG(...)  { (void) fprintf (stdout, __VA_ARGS__); }
#else
#define COCOA_DEBUG(...)  ((void) 0)
#endif

#if NSGEOMETRY_TYPES_SAME_AS_CGGEOMETRY_TYPES
#define cgrect(nsrect) nsrect
#else
#define cgrect(nsrect) (*(CGRect *)&(nsrect))
#endif

typedef struct {
    int width;
    int height;
    int bitsPerComponent;
    int bitsPerPixel;
} QEMUScreen;

NSWindow *normalWindow, *about_window;
static DisplayChangeListener *dcl;
static int last_buttons;

int gArgc;
char **gArgv;
bool stretch_video;
NSTextField *pauseLabel;
NSArray * supportedImageFileTypes;

// Mac to QKeyCode conversion
const int mac_to_qkeycode_map[] = {
    [kVK_ANSI_A] = Q_KEY_CODE_A,
    [kVK_ANSI_B] = Q_KEY_CODE_B,
    [kVK_ANSI_C] = Q_KEY_CODE_C,
    [kVK_ANSI_D] = Q_KEY_CODE_D,
    [kVK_ANSI_E] = Q_KEY_CODE_E,
    [kVK_ANSI_F] = Q_KEY_CODE_F,
    [kVK_ANSI_G] = Q_KEY_CODE_G,
    [kVK_ANSI_H] = Q_KEY_CODE_H,
    [kVK_ANSI_I] = Q_KEY_CODE_I,
    [kVK_ANSI_J] = Q_KEY_CODE_J,
    [kVK_ANSI_K] = Q_KEY_CODE_K,
    [kVK_ANSI_L] = Q_KEY_CODE_L,
    [kVK_ANSI_M] = Q_KEY_CODE_M,
    [kVK_ANSI_N] = Q_KEY_CODE_N,
    [kVK_ANSI_O] = Q_KEY_CODE_O,
    [kVK_ANSI_P] = Q_KEY_CODE_P,
    [kVK_ANSI_Q] = Q_KEY_CODE_Q,
    [kVK_ANSI_R] = Q_KEY_CODE_R,
    [kVK_ANSI_S] = Q_KEY_CODE_S,
    [kVK_ANSI_T] = Q_KEY_CODE_T,
    [kVK_ANSI_U] = Q_KEY_CODE_U,
    [kVK_ANSI_V] = Q_KEY_CODE_V,
    [kVK_ANSI_W] = Q_KEY_CODE_W,
    [kVK_ANSI_X] = Q_KEY_CODE_X,
    [kVK_ANSI_Y] = Q_KEY_CODE_Y,
    [kVK_ANSI_Z] = Q_KEY_CODE_Z,

    [kVK_ANSI_0] = Q_KEY_CODE_0,
    [kVK_ANSI_1] = Q_KEY_CODE_1,
    [kVK_ANSI_2] = Q_KEY_CODE_2,
    [kVK_ANSI_3] = Q_KEY_CODE_3,
    [kVK_ANSI_4] = Q_KEY_CODE_4,
    [kVK_ANSI_5] = Q_KEY_CODE_5,
    [kVK_ANSI_6] = Q_KEY_CODE_6,
    [kVK_ANSI_7] = Q_KEY_CODE_7,
    [kVK_ANSI_8] = Q_KEY_CODE_8,
    [kVK_ANSI_9] = Q_KEY_CODE_9,

    [kVK_ANSI_Grave] = Q_KEY_CODE_GRAVE_ACCENT,
    [kVK_ANSI_Minus] = Q_KEY_CODE_MINUS,
    [kVK_ANSI_Equal] = Q_KEY_CODE_EQUAL,
    [kVK_Delete] = Q_KEY_CODE_BACKSPACE,
    [kVK_CapsLock] = Q_KEY_CODE_CAPS_LOCK,
    [kVK_Tab] = Q_KEY_CODE_TAB,
    [kVK_Return] = Q_KEY_CODE_RET,
    [kVK_ANSI_LeftBracket] = Q_KEY_CODE_BRACKET_LEFT,
    [kVK_ANSI_RightBracket] = Q_KEY_CODE_BRACKET_RIGHT,
    [kVK_ANSI_Backslash] = Q_KEY_CODE_BACKSLASH,
    [kVK_ANSI_Semicolon] = Q_KEY_CODE_SEMICOLON,
    [kVK_ANSI_Quote] = Q_KEY_CODE_APOSTROPHE,
    [kVK_ANSI_Comma] = Q_KEY_CODE_COMMA,
    [kVK_ANSI_Period] = Q_KEY_CODE_DOT,
    [kVK_ANSI_Slash] = Q_KEY_CODE_SLASH,
    [kVK_Shift] = Q_KEY_CODE_SHIFT,
    [kVK_RightShift] = Q_KEY_CODE_SHIFT_R,
    [kVK_Control] = Q_KEY_CODE_CTRL,
    [kVK_RightControl] = Q_KEY_CODE_CTRL_R,
    [kVK_Option] = Q_KEY_CODE_ALT,
    [kVK_RightOption] = Q_KEY_CODE_ALT_R,
    [kVK_Command] = Q_KEY_CODE_META_L,
    [0x36] = Q_KEY_CODE_META_R, /* There is no kVK_RightCommand */
    [kVK_Space] = Q_KEY_CODE_SPC,

    [kVK_ANSI_Keypad0] = Q_KEY_CODE_KP_0,
    [kVK_ANSI_Keypad1] = Q_KEY_CODE_KP_1,
    [kVK_ANSI_Keypad2] = Q_KEY_CODE_KP_2,
    [kVK_ANSI_Keypad3] = Q_KEY_CODE_KP_3,
    [kVK_ANSI_Keypad4] = Q_KEY_CODE_KP_4,
    [kVK_ANSI_Keypad5] = Q_KEY_CODE_KP_5,
    [kVK_ANSI_Keypad6] = Q_KEY_CODE_KP_6,
    [kVK_ANSI_Keypad7] = Q_KEY_CODE_KP_7,
    [kVK_ANSI_Keypad8] = Q_KEY_CODE_KP_8,
    [kVK_ANSI_Keypad9] = Q_KEY_CODE_KP_9,
    [kVK_ANSI_KeypadDecimal] = Q_KEY_CODE_KP_DECIMAL,
    [kVK_ANSI_KeypadEnter] = Q_KEY_CODE_KP_ENTER,
    [kVK_ANSI_KeypadPlus] = Q_KEY_CODE_KP_ADD,
    [kVK_ANSI_KeypadMinus] = Q_KEY_CODE_KP_SUBTRACT,
    [kVK_ANSI_KeypadMultiply] = Q_KEY_CODE_KP_MULTIPLY,
    [kVK_ANSI_KeypadDivide] = Q_KEY_CODE_KP_DIVIDE,
    [kVK_ANSI_KeypadEquals] = Q_KEY_CODE_KP_EQUALS,
    [kVK_ANSI_KeypadClear] = Q_KEY_CODE_NUM_LOCK,

    [kVK_UpArrow] = Q_KEY_CODE_UP,
    [kVK_DownArrow] = Q_KEY_CODE_DOWN,
    [kVK_LeftArrow] = Q_KEY_CODE_LEFT,
    [kVK_RightArrow] = Q_KEY_CODE_RIGHT,

    [kVK_Help] = Q_KEY_CODE_INSERT,
    [kVK_Home] = Q_KEY_CODE_HOME,
    [kVK_PageUp] = Q_KEY_CODE_PGUP,
    [kVK_PageDown] = Q_KEY_CODE_PGDN,
    [kVK_End] = Q_KEY_CODE_END,
    [kVK_ForwardDelete] = Q_KEY_CODE_DELETE,

    [kVK_Escape] = Q_KEY_CODE_ESC,

    /* The Power key can't be used directly because the operating system uses
     * it. This key can be emulated by using it in place of another key such as
     * F1. Don't forget to disable the real key binding.
     */
    /* [kVK_F1] = Q_KEY_CODE_POWER, */

    [kVK_F1] = Q_KEY_CODE_F1,
    [kVK_F2] = Q_KEY_CODE_F2,
    [kVK_F3] = Q_KEY_CODE_F3,
    [kVK_F4] = Q_KEY_CODE_F4,
    [kVK_F5] = Q_KEY_CODE_F5,
    [kVK_F6] = Q_KEY_CODE_F6,
    [kVK_F7] = Q_KEY_CODE_F7,
    [kVK_F8] = Q_KEY_CODE_F8,
    [kVK_F9] = Q_KEY_CODE_F9,
    [kVK_F10] = Q_KEY_CODE_F10,
    [kVK_F11] = Q_KEY_CODE_F11,
    [kVK_F12] = Q_KEY_CODE_F12,
    [kVK_F13] = Q_KEY_CODE_PRINT,
    [kVK_F14] = Q_KEY_CODE_SCROLL_LOCK,
    [kVK_F15] = Q_KEY_CODE_PAUSE,

    /*
     * The eject and volume keys can't be used here because they are handled at
     * a lower level than what an Application can see.
     */
};

static int cocoa_keycode_to_qemu(int keycode)
{
    if (ARRAY_SIZE(mac_to_qkeycode_map) <= keycode) {
        fprintf(stderr, "(cocoa) warning unknown keycode 0x%x\n", keycode);
        return 0;
    }
    return mac_to_qkeycode_map[keycode];
}

/* Displays an alert dialog box with the specified message */
static void QEMU_Alert(NSString *message)
{
    NSAlert *alert;
    alert = [NSAlert new];
    [alert setMessageText: message];
    [alert runModal];
    [alert release];
}

/* Handles any errors that happen with a device transaction */
static void handleAnyDeviceErrors(Error * err)
{
    if (err) {
        QEMU_Alert([NSString stringWithCString: error_get_pretty(err)
                                      encoding: NSASCIIStringEncoding]);
        error_free(err);
    }
}

/*
 ------------------------------------------------------
    QemuCocoaView
 ------------------------------------------------------
*/
@interface QemuCocoaView : NSView
{
    NSWindow *fullScreenWindow;
    CGFloat cx,cy,cw,ch;
    CGDataProviderRef dataProviderRef;
    BOOL modifiers_state[256];
    BOOL isFullscreen;
}
- (void) switchSurface:(DisplaySurface *)surface;
- (void) grabMouse;
- (void) ungrabMouse;
- (void) toggleFullScreen:(id)sender;
- (void) handleMonitorInput:(NSEvent *)event;
- (void) handleEvent:(NSEvent *)event;
/* The state surrounding mouse grabbing is potentially confusing.
 * isAbsoluteEnabled tracks qemu_input_is_absolute() [ie "is the emulated
 *   pointing device an absolute-position one?"], but is only updated on
 *   next refresh.
 * isMouseGrabbed tracks whether GUI events are directed to the guest;
 *   it controls whether special keys like Cmd get sent to the guest,
 *   and whether we capture the mouse when in non-absolute mode.
 * isMouseDeassociated tracks whether we've told MacOSX to disassociate
 *   the mouse and mouse cursor position by calling
 *   CGAssociateMouseAndMouseCursorPosition(FALSE)
 *   (which basically happens if we grab in non-absolute mode).
 */
@property (getter = isAbsoluteEnabled) BOOL absoluteEnabled;
@property (readonly, getter=isMouseGrabbed) BOOL mouseGrabbed;
@property (readonly, getter=isMouseDeassociated) BOOL mouseDeassociated;
@property (readonly) CGFloat cdx;
@property (readonly) CGFloat cdy;
@property (readonly) QEMUScreen gscreen;
- (void) raiseAllKeys;
@end

QemuCocoaView *cocoaView;

@implementation QemuCocoaView
@synthesize cdx;
@synthesize cdy;
@synthesize absoluteEnabled = isAbsoluteEnabled;
@synthesize mouseGrabbed = isMouseGrabbed;
@synthesize mouseDeassociated = isMouseDeassociated;
@synthesize gscreen = screen;

- (instancetype)initWithFrame:(NSRect)frameRect
{
    COCOA_DEBUG("QemuCocoaView: initWithFrame\n");

    self = [super initWithFrame:frameRect];
    if (self) {

        screen.bitsPerComponent = 8;
        screen.bitsPerPixel = 32;
        screen.width = frameRect.size.width;
        screen.height = frameRect.size.height;

    }
    return self;
}

- (void) dealloc
{
    COCOA_DEBUG("QemuCocoaView: dealloc\n");

    if (dataProviderRef)
        CGDataProviderRelease(dataProviderRef);

    [super dealloc];
}

- (BOOL) isOpaque
{
    return YES;
}

- (BOOL) screenContainsPoint:(NSPoint) p
{
    return (p.x > -1 && p.x < screen.width && p.y > -1 && p.y < screen.height);
}

- (void) hideCursor
{
    if (!cursor_hide) {
        return;
    }
    [NSCursor hide];
}

- (void) unhideCursor
{
    if (!cursor_hide) {
        return;
    }
    [NSCursor unhide];
}

- (void) drawRect:(NSRect) rect
{
    COCOA_DEBUG("QemuCocoaView: drawRect\n");

    // get CoreGraphic context
    CGContextRef viewContextRef = [[NSGraphicsContext currentContext] graphicsPort];
    CGContextSetInterpolationQuality (viewContextRef, kCGInterpolationNone);
    CGContextSetShouldAntialias (viewContextRef, NO);

    // draw screen bitmap directly to Core Graphics context
    if (!dataProviderRef) {
        // Draw request before any guest device has set up a framebuffer:
        // just draw an opaque black rectangle
        CGContextSetRGBFillColor(viewContextRef, 0, 0, 0, 1.0);
        CGContextFillRect(viewContextRef, NSRectToCGRect(rect));
    } else {
        CGColorSpaceRef tmpSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
        CGImageRef imageRef = CGImageCreate(
            screen.width, //width
            screen.height, //height
            screen.bitsPerComponent, //bitsPerComponent
            screen.bitsPerPixel, //bitsPerPixel
            (screen.width * (screen.bitsPerComponent/2)), //bytesPerRow
            tmpSpace,
            kCGBitmapByteOrder32Host | kCGImageAlphaNoneSkipFirst,
            dataProviderRef, //provider
            NULL, //decode
            0, //interpolate
            kCGRenderingIntentDefault //intent
        );
        CFRelease(tmpSpace);
        // selective drawing code (draws only dirty rectangles)
        const NSRect *rectList;
        NSInteger rectCount;
        int i;
        CGImageRef clipImageRef;
        CGRect clipRect;

        [self getRectsBeingDrawn:&rectList count:&rectCount];
        for (i = 0; i < rectCount; i++) {
            clipRect.origin.x = rectList[i].origin.x / cdx;
            clipRect.origin.y = (CGFloat)screen.height - (rectList[i].origin.y + rectList[i].size.height) / cdy;
            clipRect.size.width = rectList[i].size.width / cdx;
            clipRect.size.height = rectList[i].size.height / cdy;
            clipImageRef = CGImageCreateWithImageInRect(
                                                        imageRef,
                                                        clipRect
                                                        );
            CGContextDrawImage (viewContextRef, cgrect(rectList[i]), clipImageRef);
            CGImageRelease (clipImageRef);
        }
        CGImageRelease (imageRef);
    }
}

- (void) setContentDimensions
{
    COCOA_DEBUG("QemuCocoaView: setContentDimensions\n");

    if (isFullscreen) {
        cdx = [[NSScreen mainScreen] frame].size.width / (CGFloat)screen.width;
        cdy = [[NSScreen mainScreen] frame].size.height / (CGFloat)screen.height;

        /* stretches video, but keeps same aspect ratio */
        if (stretch_video == true) {
            /* use smallest stretch value - prevents clipping on sides */
            if (MIN(cdx, cdy) == cdx) {
                cdy = cdx;
            } else {
                cdx = cdy;
            }
        } else {  /* No stretching */
            cdx = cdy = 1;
        }
        cw = screen.width * cdx;
        ch = screen.height * cdy;
        cx = ([[NSScreen mainScreen] frame].size.width - cw) / 2.0;
        cy = ([[NSScreen mainScreen] frame].size.height - ch) / 2.0;
    } else {
        cx = 0;
        cy = 0;
        cw = screen.width;
        ch = screen.height;
        cdx = 1.0;
        cdy = 1.0;
    }
}

- (void) switchSurface:(DisplaySurface *)surface
{
    COCOA_DEBUG("QemuCocoaView: switchSurface\n");

    int w = surface_width(surface);
    int h = surface_height(surface);
    /* cdx == 0 means this is our very first surface, in which case we need
     * to recalculate the content dimensions even if it happens to be the size
     * of the initial empty window.
     */
    bool isResize = (w != screen.width || h != screen.height || cdx == 0.0);

    int oldh = screen.height;
    if (isResize) {
        // Resize before we trigger the redraw, or we'll redraw at the wrong size
        COCOA_DEBUG("switchSurface: new size %d x %d\n", w, h);
        screen.width = w;
        screen.height = h;
        [self setContentDimensions];
        [self setFrame:NSMakeRect(cx, cy, cw, ch)];
    }

    // update screenBuffer
    if (dataProviderRef)
        CGDataProviderRelease(dataProviderRef);

    //sync host window color space with guests
    screen.bitsPerPixel = surface_bits_per_pixel(surface);
    screen.bitsPerComponent = surface_bytes_per_pixel(surface) * 2;

    dataProviderRef = CGDataProviderCreateWithData(NULL, surface_data(surface), w * 4 * h, NULL);

    // update windows
    if (isFullscreen) {
        [normalWindow setFrame:NSMakeRect([normalWindow frame].origin.x, [normalWindow frame].origin.y - h + oldh, w, h + [normalWindow frame].size.height - oldh) display:NO animate:NO];
    } else {
        if (qemu_name)
            [normalWindow setTitle:[NSString stringWithFormat:@"QEMU %s", qemu_name]];
        [normalWindow setFrame:NSMakeRect([normalWindow frame].origin.x, [normalWindow frame].origin.y - h + oldh, w, h + [normalWindow frame].size.height - oldh) display:YES animate:NO];
    }

    if (isResize) {
        [normalWindow center];
    }
}

- (void) toggleFullScreen:(id)sender
{
    COCOA_DEBUG("QemuCocoaView: toggleFullScreen\n");

    if (isFullscreen) { // switch from fullscreen to desktop
        isFullscreen = NO;
        [self ungrabMouse];
        [self setContentDimensions];
        [self exitFullScreenModeWithOptions:nil];
    } else { // switch from desktop to fullscreen
        isFullscreen = TRUE;
        [normalWindow orderOut: nil]; /* Hide the window */
        [self grabMouse];
        [self setContentDimensions];
        if ([NSView respondsToSelector:@selector(enterFullScreenMode:withOptions:)]) { // test if "enterFullScreenMode:withOptions" is supported on host at runtime
            [self enterFullScreenMode:[NSScreen mainScreen] withOptions:[NSDictionary dictionaryWithObjectsAndKeys:
                [NSNumber numberWithBool:NO], NSFullScreenModeAllScreens,
                [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:NO], kCGDisplayModeIsStretched, nil], NSFullScreenModeSetting,
                 nil]];
        } else {
            [NSMenu setMenuBarVisible:NO];
            fullScreenWindow = [[NSWindow alloc] initWithContentRect:[[NSScreen mainScreen] frame]
                styleMask:NSWindowStyleMaskBorderless
                backing:NSBackingStoreBuffered
                defer:NO];
            [fullScreenWindow setAcceptsMouseMovedEvents: YES];
            [fullScreenWindow setHasShadow:NO];
            [fullScreenWindow setBackgroundColor: [NSColor blackColor]];
            [self setFrame:NSMakeRect(cx, cy, cw, ch)];
            [[fullScreenWindow contentView] addSubview: self];
            [fullScreenWindow makeKeyAndOrderFront:self];
        }
    }
}

- (void) toggleModifier: (int)keycode {
    // Toggle the stored state.
    modifiers_state[keycode] = !modifiers_state[keycode];
    // Send a keyup or keydown depending on the state.
    qemu_input_event_send_key_qcode(dcl->con, keycode, modifiers_state[keycode]);
}

- (void) toggleStatefulModifier: (int)keycode {
    // Toggle the stored state.
    modifiers_state[keycode] = !modifiers_state[keycode];
    // Generate keydown and keyup.
    qemu_input_event_send_key_qcode(dcl->con, keycode, true);
    qemu_input_event_send_key_qcode(dcl->con, keycode, false);
}

// Does the work of sending input to the monitor
- (void) handleMonitorInput:(NSEvent *)event
{
    int keysym = 0;
    int control_key = 0;

    // if the control key is down
    if ([event modifierFlags] & NSEventModifierFlagControl) {
        control_key = 1;
    }

    /* translates Macintosh keycodes to QEMU's keysym */

    int without_control_translation[] = {
        [0 ... 0xff] = 0,   // invalid key

        [kVK_UpArrow]       = QEMU_KEY_UP,
        [kVK_DownArrow]     = QEMU_KEY_DOWN,
        [kVK_RightArrow]    = QEMU_KEY_RIGHT,
        [kVK_LeftArrow]     = QEMU_KEY_LEFT,
        [kVK_Home]          = QEMU_KEY_HOME,
        [kVK_End]           = QEMU_KEY_END,
        [kVK_PageUp]        = QEMU_KEY_PAGEUP,
        [kVK_PageDown]      = QEMU_KEY_PAGEDOWN,
        [kVK_ForwardDelete] = QEMU_KEY_DELETE,
        [kVK_Delete]        = QEMU_KEY_BACKSPACE,
    };

    int with_control_translation[] = {
        [0 ... 0xff] = 0,   // invalid key

        [kVK_UpArrow]       = QEMU_KEY_CTRL_UP,
        [kVK_DownArrow]     = QEMU_KEY_CTRL_DOWN,
        [kVK_RightArrow]    = QEMU_KEY_CTRL_RIGHT,
        [kVK_LeftArrow]     = QEMU_KEY_CTRL_LEFT,
        [kVK_Home]          = QEMU_KEY_CTRL_HOME,
        [kVK_End]           = QEMU_KEY_CTRL_END,
        [kVK_PageUp]        = QEMU_KEY_CTRL_PAGEUP,
        [kVK_PageDown]      = QEMU_KEY_CTRL_PAGEDOWN,
    };

    if (control_key != 0) { /* If the control key is being used */
        if ([event keyCode] < ARRAY_SIZE(with_control_translation)) {
            keysym = with_control_translation[[event keyCode]];
        }
    } else {
        if ([event keyCode] < ARRAY_SIZE(without_control_translation)) {
            keysym = without_control_translation[[event keyCode]];
        }
    }

    // if not a key that needs translating
    if (keysym == 0) {
        NSString *ks = [event characters];
        if ([ks length] > 0) {
            keysym = [ks characterAtIndex:0];
        }
    }

    if (keysym) {
        kbd_put_keysym(keysym);
    }
}

- (void) handleEvent:(NSEvent *)event
{
    COCOA_DEBUG("QemuCocoaView: handleEvent\n");

    int buttons = 0;
    int keycode = 0;
    bool mouse_event = false;
    NSPoint p = [event locationInWindow];

    switch ([event type]) {
        case NSEventTypeFlagsChanged:
            if ([event keyCode] == 0) {
                // When the Cocoa keyCode is zero that means keys should be
                // synthesized based on the values in in the eventModifiers
                // bitmask.

                if (qemu_console_is_graphic(NULL)) {
                    NSUInteger modifiers = [event modifierFlags];

                    if (!!(modifiers & NSEventModifierFlagCapsLock) != !!modifiers_state[Q_KEY_CODE_CAPS_LOCK]) {
                        [self toggleStatefulModifier:Q_KEY_CODE_CAPS_LOCK];
                    }
                    if (!!(modifiers & NSEventModifierFlagShift) != !!modifiers_state[Q_KEY_CODE_SHIFT]) {
                        [self toggleModifier:Q_KEY_CODE_SHIFT];
                    }
                    if (!!(modifiers & NSEventModifierFlagControl) != !!modifiers_state[Q_KEY_CODE_CTRL]) {
                        [self toggleModifier:Q_KEY_CODE_CTRL];
                    }
                    if (!!(modifiers & NSEventModifierFlagOption) != !!modifiers_state[Q_KEY_CODE_ALT]) {
                        [self toggleModifier:Q_KEY_CODE_ALT];
                    }
                    if (!!(modifiers & NSEventModifierFlagCommand) != !!modifiers_state[Q_KEY_CODE_META_L]) {
                        [self toggleModifier:Q_KEY_CODE_META_L];
                    }
                }
            } else {
                keycode = cocoa_keycode_to_qemu([event keyCode]);
            }

            if ((keycode == Q_KEY_CODE_META_L || keycode == Q_KEY_CODE_META_R)
               && !isMouseGrabbed) {
              /* Don't pass command key changes to guest unless mouse is grabbed */
              keycode = 0;
            }

            if (keycode) {
                // emulate caps lock and num lock keydown and keyup
                if (keycode == Q_KEY_CODE_CAPS_LOCK ||
                    keycode == Q_KEY_CODE_NUM_LOCK) {
                    [self toggleStatefulModifier:keycode];
                } else if (qemu_console_is_graphic(NULL)) {
                  [self toggleModifier:keycode];
                }
            }

            break;
        case NSEventTypeKeyDown:
            keycode = cocoa_keycode_to_qemu([event keyCode]);

            // forward command key combos to the host UI unless the mouse is grabbed
            if (!isMouseGrabbed && ([event modifierFlags] & NSEventModifierFlagCommand)) {
                [NSApp sendEvent:event];
                return;
            }

            // default

            // handle control + alt Key Combos (ctrl+alt+[1..9,g] is reserved for QEMU)
            if (([event modifierFlags] & NSEventModifierFlagControl) && ([event modifierFlags] & NSEventModifierFlagOption)) {
                NSString *keychar = [event charactersIgnoringModifiers];
                if ([keychar length] == 1) {
                    char key = [keychar characterAtIndex:0];
                    switch (key) {

                        // enable graphic console
                        case '1' ... '9':
                            console_select(key - '0' - 1); /* ascii math */
                            return;

                        // release the mouse grab
                        case 'g':
                            [self ungrabMouse];
                            return;
                    }
                }
            }

            if (qemu_console_is_graphic(NULL)) {
                qemu_input_event_send_key_qcode(dcl->con, keycode, true);
            } else {
                [self handleMonitorInput: event];
            }
            break;
        case NSEventTypeKeyUp:
            keycode = cocoa_keycode_to_qemu([event keyCode]);

            // don't pass the guest a spurious key-up if we treated this
            // command-key combo as a host UI action
            if (!isMouseGrabbed && ([event modifierFlags] & NSEventModifierFlagCommand)) {
                return;
            }

            if (qemu_console_is_graphic(NULL)) {
                qemu_input_event_send_key_qcode(dcl->con, keycode, false);
            }
            break;
        case NSEventTypeMouseMoved:
            if (isAbsoluteEnabled) {
                if (![self screenContainsPoint:p] || ![[self window] isKeyWindow]) {
                    if (isMouseGrabbed) {
                        [self ungrabMouse];
                    }
                } else {
                    if (!isMouseGrabbed) {
                        [self grabMouse];
                    }
                }
            }
            mouse_event = true;
            break;
        case NSEventTypeLeftMouseDown:
            if ([event modifierFlags] & NSEventModifierFlagCommand) {
                buttons |= MOUSE_EVENT_RBUTTON;
            } else {
                buttons |= MOUSE_EVENT_LBUTTON;
            }
            mouse_event = true;
            break;
        case NSEventTypeRightMouseDown:
            buttons |= MOUSE_EVENT_RBUTTON;
            mouse_event = true;
            break;
        case NSEventTypeOtherMouseDown:
            buttons |= MOUSE_EVENT_MBUTTON;
            mouse_event = true;
            break;
        case NSEventTypeLeftMouseDragged:
            if ([event modifierFlags] & NSEventModifierFlagCommand) {
                buttons |= MOUSE_EVENT_RBUTTON;
            } else {
                buttons |= MOUSE_EVENT_LBUTTON;
            }
            mouse_event = true;
            break;
        case NSEventTypeRightMouseDragged:
            buttons |= MOUSE_EVENT_RBUTTON;
            mouse_event = true;
            break;
        case NSEventTypeOtherMouseDragged:
            buttons |= MOUSE_EVENT_MBUTTON;
            mouse_event = true;
            break;
        case NSEventTypeLeftMouseUp:
            mouse_event = true;
            if (!isMouseGrabbed && [self screenContainsPoint:p]) {
                if([[self window] isKeyWindow]) {
                    [self grabMouse];
                }
            }
            break;
        case NSEventTypeRightMouseUp:
            mouse_event = true;
            break;
        case NSEventTypeOtherMouseUp:
            mouse_event = true;
            break;
        case NSEventTypeScrollWheel:
            /*
             * Send wheel events to the guest regardless of window focus.
             * This is in-line with standard Mac OS X UI behaviour.
             */

            /* Determine if this is a scroll up or scroll down event */
            buttons = ([event scrollingDeltaY] > 0) ?
                INPUT_BUTTON_WHEEL_UP : INPUT_BUTTON_WHEEL_DOWN;
            qemu_input_queue_btn(dcl->con, buttons, true);
            qemu_input_event_sync();
            qemu_input_queue_btn(dcl->con, buttons, false);
            qemu_input_event_sync();

            /*
             * Since deltaY also reports scroll wheel events we prevent mouse
             * movement code from executing.
             */
            mouse_event = false;
            break;
        default:
            [NSApp sendEvent:event];
    }

    if (mouse_event) {
        /* Don't send button events to the guest unless we've got a
         * mouse grab or window focus. If we have neither then this event
         * is the user clicking on the background window to activate and
         * bring us to the front, which will be done by the sendEvent
         * call below. We definitely don't want to pass that click through
         * to the guest.
         */
        if ((isMouseGrabbed || [[self window] isKeyWindow]) &&
            (last_buttons != buttons)) {
            static uint32_t bmap[INPUT_BUTTON__MAX] = {
                [INPUT_BUTTON_LEFT]       = MOUSE_EVENT_LBUTTON,
                [INPUT_BUTTON_MIDDLE]     = MOUSE_EVENT_MBUTTON,
                [INPUT_BUTTON_RIGHT]      = MOUSE_EVENT_RBUTTON
            };
            qemu_input_update_buttons(dcl->con, bmap, last_buttons, buttons);
            last_buttons = buttons;
        }
        if (isMouseGrabbed) {
            if (isAbsoluteEnabled) {
                /* Note that the origin for Cocoa mouse coords is bottom left, not top left.
                 * The check on screenContainsPoint is to avoid sending out of range values for
                 * clicks in the titlebar.
                 */
                if ([self screenContainsPoint:p]) {
                    qemu_input_queue_abs(dcl->con, INPUT_AXIS_X, p.x, 0, screen.width);
                    qemu_input_queue_abs(dcl->con, INPUT_AXIS_Y, screen.height - p.y, 0, screen.height);
                }
            } else {
                qemu_input_queue_rel(dcl->con, INPUT_AXIS_X, (int)[event deltaX]);
                qemu_input_queue_rel(dcl->con, INPUT_AXIS_Y, (int)[event deltaY]);
            }
        } else {
            [NSApp sendEvent:event];
        }
        qemu_input_event_sync();
    }
}

- (void) grabMouse
{
    COCOA_DEBUG("QemuCocoaView: grabMouse\n");

    if (!isFullscreen) {
        if (qemu_name)
            [normalWindow setTitle:[NSString stringWithFormat:@"QEMU %s - (Press ctrl + alt + g to release Mouse)", qemu_name]];
        else
            [normalWindow setTitle:@"QEMU - (Press ctrl + alt + g to release Mouse)"];
    }
    [self hideCursor];
    if (!isAbsoluteEnabled) {
        isMouseDeassociated = YES;
        CGAssociateMouseAndMouseCursorPosition(FALSE);
    }
    isMouseGrabbed = YES; // while isMouseGrabbed = YES, QemuCocoaApp sends all events to [cocoaView handleEvent:]
}

- (void) ungrabMouse
{
    COCOA_DEBUG("QemuCocoaView: ungrabMouse\n");

    if (!isFullscreen) {
        if (qemu_name)
            [normalWindow setTitle:[NSString stringWithFormat:@"QEMU %s", qemu_name]];
        else
            [normalWindow setTitle:@"QEMU"];
    }
    [self unhideCursor];
    if (isMouseDeassociated) {
        CGAssociateMouseAndMouseCursorPosition(TRUE);
        isMouseDeassociated = NO;
    }
    isMouseGrabbed = NO;
}

/*
 * Makes the target think all down keys are being released.
 * This prevents a stuck key problem, since we will not see
 * key up events for those keys after we have lost focus.
 */
- (void) raiseAllKeys
{
    int index;
    const int max_index = ARRAY_SIZE(modifiers_state);

   for (index = 0; index < max_index; index++) {
       if (modifiers_state[index]) {
           modifiers_state[index] = 0;
           qemu_input_event_send_key_qcode(dcl->con, index, false);
       }
   }
}
@end



/*
 ------------------------------------------------------
    QemuCocoaAppController
 ------------------------------------------------------
*/
@interface QemuCocoaAppController : NSObject <NSApplicationDelegate, NSFileManagerDelegate, NSWindowDelegate>
- (void)startEmulationWithArgc:(int)argc argv:(char**)argv;
- (void)doToggleFullScreen:(id)sender;
- (void)toggleFullScreen:(id)sender;
- (void)showQEMUDoc:(id)sender;
- (void)zoomToFit:(id) sender;
- (void)displayConsole:(id)sender;
- (void)pauseQEMU:(id)sender;
- (void)resumeQEMU:(id)sender;
- (void)displayPause;
- (void)removePause;
- (void)restartQEMU:(id)sender;
- (void)powerDownQEMU:(id)sender;
- (void)ejectDeviceMedia:(id)sender;
- (void)changeDeviceMedia:(id)sender;
- (BOOL)verifyQuit;
- (void)openDocumentation:(NSString *)filename;
- (IBAction) do_about_menu_item: (id) sender;
- (void)make_about_window;
- (void)adjustSpeed:(id)sender;
@end

@implementation QemuCocoaAppController
- (id) init
{
    COCOA_DEBUG("QemuCocoaAppController: init\n");

    self = [super init];
    if (self) {

        // create a view and add it to the window
        cocoaView = [[QemuCocoaView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 640.0, 480.0)];
        if(!cocoaView) {
            fprintf(stderr, "(cocoa) can't create a view\n");
            exit(1);
        }

        // create a window
        normalWindow = [[NSWindow alloc] initWithContentRect:[cocoaView frame]
            styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskClosable
            backing:NSBackingStoreBuffered defer:NO];
        if(!normalWindow) {
            fprintf(stderr, "(cocoa) can't create window\n");
            exit(1);
        }
        [normalWindow setAcceptsMouseMovedEvents:YES];
        normalWindow.title = @"QEMU";
        [normalWindow setContentView:cocoaView];
#if (MAC_OS_X_VERSION_MAX_ALLOWED < MAC_OS_X_VERSION_10_10)
        [normalWindow useOptimizedDrawing:YES];
#endif
        [normalWindow makeKeyAndOrderFront:self];
        [normalWindow center];
        [normalWindow setDelegate: self];
        stretch_video = false;

        /* Used for displaying pause on the screen */
        pauseLabel = [NSTextField new];
        [pauseLabel setBezeled:YES];
        [pauseLabel setDrawsBackground:YES];
        [pauseLabel setBackgroundColor: [NSColor whiteColor]];
        [pauseLabel setEditable:NO];
        [pauseLabel setSelectable:NO];
        [pauseLabel setStringValue: @"Paused"];
        [pauseLabel setFont: [NSFont fontWithName: @"Helvetica" size: 90]];
        [pauseLabel setTextColor: [NSColor blackColor]];
        [pauseLabel sizeToFit];

        // set the supported image file types that can be opened
        supportedImageFileTypes = [@[@"img", @"iso", @"dmg",
                                 @"qcow", @"qcow2", @"cloop", @"vmdk", @"cdr",
                                 @"toast"] retain];
        [self make_about_window];
    }
    return self;
}

- (void) dealloc
{
    COCOA_DEBUG("QemuCocoaAppController: dealloc\n");

    [cocoaView release];
    [super dealloc];
}

- (void)applicationDidFinishLaunching: (NSNotification *) note
{
    COCOA_DEBUG("QemuCocoaAppController: applicationDidFinishLaunching\n");
    // launch QEMU, with the global args
    [self startEmulationWithArgc:gArgc argv:(char **)gArgv];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
    COCOA_DEBUG("QemuCocoaAppController: applicationWillTerminate\n");

    qemu_system_shutdown_request(SHUTDOWN_CAUSE_HOST_UI);
    exit(0);
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)theApplication
{
    return YES;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:
                                                         (NSApplication *)sender
{
    COCOA_DEBUG("QemuCocoaAppController: applicationShouldTerminate\n");
    return [self verifyQuit];
}

/* Called when the user clicks on a window's close button */
- (BOOL)windowShouldClose:(id)sender
{
    COCOA_DEBUG("QemuCocoaAppController: windowShouldClose\n");
    [NSApp terminate: sender];
    /* If the user allows the application to quit then the call to
     * NSApp terminate will never return. If we get here then the user
     * cancelled the quit, so we should return NO to not permit the
     * closing of this window.
     */
    return NO;
}

/* Called when QEMU goes into the background */
- (void) applicationWillResignActive: (NSNotification *)aNotification
{
    COCOA_DEBUG("QemuCocoaAppController: applicationWillResignActive\n");
    [cocoaView raiseAllKeys];
}

- (void)startEmulationWithArgc:(int)argc argv:(char**)argv
{
    COCOA_DEBUG("QemuCocoaAppController: startEmulationWithArgc\n");

    int status;
    status = qemu_main(argc, argv, *_NSGetEnviron());
    exit(status);
}

/* We abstract the method called by the Enter Fullscreen menu item
 * because Mac OS 10.7 and higher disables it. This is because of the
 * menu item's old selector's name toggleFullScreen:
 */
- (void) doToggleFullScreen:(id)sender
{
    [self toggleFullScreen:(id)sender];
}

- (void)toggleFullScreen:(id)sender
{
    COCOA_DEBUG("QemuCocoaAppController: toggleFullScreen\n");

    [cocoaView toggleFullScreen:sender];
}

/* Tries to find then open the specified filename */
- (void) openDocumentation: (NSString *) filename
{
    /* Where to look for local files */
    NSString *path_array[] = {@"../share/doc/qemu/", @"../doc/qemu/", @"../"};
    NSString *full_file_path;

    /* iterate thru the possible paths until the file is found */
    int index;
    for (index = 0; index < ARRAY_SIZE(path_array); index++) {
        full_file_path = [[NSBundle mainBundle] executablePath];
        full_file_path = [full_file_path stringByDeletingLastPathComponent];
        full_file_path = [NSString stringWithFormat: @"%@/%@%@", full_file_path,
                          path_array[index], filename];
        if ([[NSWorkspace sharedWorkspace] openFile: full_file_path] == YES) {
            return;
        }
    }

    /* If none of the paths opened a file */
    NSBeep();
    QEMU_Alert(@"Failed to open file");
}

- (void)showQEMUDoc:(id)sender
{
    COCOA_DEBUG("QemuCocoaAppController: showQEMUDoc\n");

    [self openDocumentation: @"qemu-doc.html"];
}

/* Stretches video to fit host monitor size */
- (void)zoomToFit:(id) sender
{
    stretch_video = !stretch_video;
    if (stretch_video == true) {
        [sender setState: NSOnState];
    } else {
        [sender setState: NSOffState];
    }
}

/* Displays the console on the screen */
- (void)displayConsole:(id)sender
{
    console_select([sender tag]);
}

/* Pause the guest */
- (void)pauseQEMU:(id)sender
{
    qmp_stop(NULL);
    [sender setEnabled: NO];
    [[[sender menu] itemWithTitle: @"Resume"] setEnabled: YES];
    [self displayPause];
}

/* Resume running the guest operating system */
- (void)resumeQEMU:(id) sender
{
    qmp_cont(NULL);
    [sender setEnabled: NO];
    [[[sender menu] itemWithTitle: @"Pause"] setEnabled: YES];
    [self removePause];
}

/* Displays the word pause on the screen */
- (void)displayPause
{
    /* Coordinates have to be calculated each time because the window can change its size */
    int xCoord, yCoord, width, height;
    xCoord = ([normalWindow frame].size.width - [pauseLabel frame].size.width)/2;
    yCoord = [normalWindow frame].size.height - [pauseLabel frame].size.height - ([pauseLabel frame].size.height * .5);
    width = [pauseLabel frame].size.width;
    height = [pauseLabel frame].size.height;
    [pauseLabel setFrame: NSMakeRect(xCoord, yCoord, width, height)];
    [cocoaView addSubview: pauseLabel];
}

/* Removes the word pause from the screen */
- (void)removePause
{
    [pauseLabel removeFromSuperview];
}

/* Restarts QEMU */
- (void)restartQEMU:(id)sender
{
    qmp_system_reset(NULL);
}

/* Powers down QEMU */
- (void)powerDownQEMU:(id)sender
{
    qmp_system_powerdown(NULL);
}

/* Ejects the media.
 * Uses sender's tag to figure out the device to eject.
 */
- (void)ejectDeviceMedia:(id)sender
{
    NSString * drive;
    drive = [sender representedObject];
    if(drive == nil) {
        NSBeep();
        QEMU_Alert(@"Failed to find drive to eject!");
        return;
    }

    Error *err = NULL;
    qmp_eject(true, [drive cStringUsingEncoding: NSASCIIStringEncoding],
              false, NULL, false, false, &err);
    handleAnyDeviceErrors(err);
}

/* Displays a dialog box asking the user to select an image file to load.
 * Uses sender's represented object value to figure out which drive to use.
 */
- (void)changeDeviceMedia:(id)sender
{
    /* Find the drive name */
    NSString * drive;
    drive = [sender representedObject];
    if(drive == nil) {
        NSBeep();
        QEMU_Alert(@"Could not find drive!");
        return;
    }

    /* Display the file open dialog */
    NSOpenPanel * openPanel;
    openPanel = [NSOpenPanel openPanel];
    [openPanel setCanChooseFiles: YES];
    [openPanel setAllowsMultipleSelection: NO];
    [openPanel setAllowedFileTypes: supportedImageFileTypes];
    if([openPanel runModal] == NSFileHandlingPanelOKButton) {
        NSString * file = [[[openPanel URLs] objectAtIndex: 0] path];
        if(file == nil) {
            NSBeep();
            QEMU_Alert(@"Failed to convert URL to file path!");
            return;
        }

        Error *err = NULL;
        qmp_blockdev_change_medium(true,
                                   [drive cStringUsingEncoding:
                                          NSASCIIStringEncoding],
                                   false, NULL,
                                   [file fileSystemRepresentation],
                                   true, "raw",
                                   false, 0,
                                   &err);
        handleAnyDeviceErrors(err);
    }
}

/* Verifies if the user really wants to quit */
- (BOOL)verifyQuit
{
    NSAlert *alert = [NSAlert new];
    [alert autorelease];
    [alert setMessageText: @"Are you sure you want to quit QEMU?"];
    [alert addButtonWithTitle: @"Cancel"];
    [alert addButtonWithTitle: @"Quit"];
    if([alert runModal] == NSAlertSecondButtonReturn) {
        return YES;
    } else {
        return NO;
    }
}

/* The action method for the About menu item */
- (IBAction) do_about_menu_item: (id) sender
{
    [about_window makeKeyAndOrderFront: nil];
}

/* Create and display the about dialog */
- (void)make_about_window
{
    /* Make the window */
    int x = 0, y = 0, about_width = 400, about_height = 200;
    NSRect window_rect = NSMakeRect(x, y, about_width, about_height);
    about_window = [[NSWindow alloc] initWithContentRect:window_rect
                    styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                    NSWindowStyleMaskMiniaturizable
                    backing:NSBackingStoreBuffered
                    defer:NO];
    [about_window setTitle: @"About"];
    [about_window setReleasedWhenClosed: NO];
    [about_window center];
    NSView *superView = [about_window contentView];

    /* Create the dimensions of the picture */
    int picture_width = 80, picture_height = 80;
    x = (about_width - picture_width)/2;
    y = about_height - picture_height - 10;
    NSRect picture_rect = NSMakeRect(x, y, picture_width, picture_height);

    /* Get the path to the QEMU binary */
    NSString *binary_name = [NSString stringWithCString: gArgv[0]
                                      encoding: NSASCIIStringEncoding];
    binary_name = [binary_name lastPathComponent];
    NSString *program_path = [[NSString alloc] initWithFormat: @"%@/%@",
    [[NSBundle mainBundle] bundlePath], binary_name];

    /* Make the picture of QEMU */
    NSImageView *picture_view = [[NSImageView alloc] initWithFrame:
                                                     picture_rect];
    NSImage *qemu_image = [[NSWorkspace sharedWorkspace] iconForFile:
                                                         program_path];
    [picture_view setImage: qemu_image];
    [picture_view setImageScaling: NSImageScaleProportionallyUpOrDown];
    [superView addSubview: picture_view];

    /* Make the name label */
    x = 0;
    y = y - 25;
    int name_width = about_width, name_height = 20;
    NSRect name_rect = NSMakeRect(x, y, name_width, name_height);
    NSTextField *name_label = [[NSTextField alloc] initWithFrame: name_rect];
    [name_label setEditable: NO];
    [name_label setBezeled: NO];
    [name_label setDrawsBackground: NO];
    [name_label setAlignment: NSTextAlignmentCenter];
    NSString *qemu_name = [[NSString alloc] initWithCString: gArgv[0]
                                            encoding: NSASCIIStringEncoding];
    qemu_name = [qemu_name lastPathComponent];
    [name_label setStringValue: qemu_name];
    [superView addSubview: name_label];

    /* Set the version label's attributes */
    x = 0;
    y = 50;
    int version_width = about_width, version_height = 20;
    NSRect version_rect = NSMakeRect(x, y, version_width, version_height);
    NSTextField *version_label = [[NSTextField alloc] initWithFrame:
                                                      version_rect];
    [version_label setEditable: NO];
    [version_label setBezeled: NO];
    [version_label setAlignment: NSTextAlignmentCenter];
    [version_label setDrawsBackground: NO];

    /* Create the version string*/
    NSString *version_string;
    version_string = [[NSString alloc] initWithFormat:
    @"QEMU emulator version %s", QEMU_FULL_VERSION];
    [version_label setStringValue: version_string];
    [superView addSubview: version_label];

    /* Make copyright label */
    x = 0;
    y = 35;
    int copyright_width = about_width, copyright_height = 20;
    NSRect copyright_rect = NSMakeRect(x, y, copyright_width, copyright_height);
    NSTextField *copyright_label = [[NSTextField alloc] initWithFrame:
                                                        copyright_rect];
    [copyright_label setEditable: NO];
    [copyright_label setBezeled: NO];
    [copyright_label setDrawsBackground: NO];
    [copyright_label setAlignment: NSTextAlignmentCenter];
    [copyright_label setStringValue: [NSString stringWithFormat: @"%s",
                                     QEMU_COPYRIGHT]];
    [superView addSubview: copyright_label];
}

/* Used by the Speed menu items */
- (void)adjustSpeed:(id)sender
{
    int throttle_pct; /* throttle percentage */
    NSMenu *menu;

    menu = [sender menu];
    if (menu != nil)
    {
        /* Unselect the currently selected item */
        for (NSMenuItem *item in [menu itemArray]) {
            if (item.state == NSOnState) {
                [item setState: NSOffState];
                break;
            }
        }
    }

    // check the menu item
    [sender setState: NSOnState];

    // get the throttle percentage
    throttle_pct = [sender tag];

    cpu_throttle_set(throttle_pct);
    COCOA_DEBUG("cpu throttling at %d%c\n", cpu_throttle_get_percentage(), '%');
}

@end


int main (int argc, const char * argv[]) {

    gArgc = argc;
    gArgv = (char **)argv;
    int i;

    /* In case we don't need to display a window, let's not do that */
    for (i = 1; i < argc; i++) {
        const char *opt = argv[i];

        if (opt[0] == '-') {
            /* Treat --foo the same as -foo.  */
            if (opt[1] == '-') {
                opt++;
            }
            if (!strcmp(opt, "-h") || !strcmp(opt, "-help") ||
                !strcmp(opt, "-vnc") ||
                !strcmp(opt, "-nographic") ||
                !strcmp(opt, "-version") ||
                !strcmp(opt, "-curses") ||
                !strcmp(opt, "-display") ||
                !strcmp(opt, "-qtest")) {
                return qemu_main(gArgc, gArgv, *_NSGetEnviron());
            }
        }
    }

    @autoreleasepool {

    // Pull this console process up to being a fully-fledged graphical
    // app with a menubar and Dock icon
    ProcessSerialNumber psn = { 0, kCurrentProcess };
    TransformProcessType(&psn, kProcessTransformToForegroundApplication);

    [NSApplication sharedApplication];

    // Add menus
    NSMenu      *menu;
    NSMenuItem  *menuItem;

    [NSApp setMainMenu:[[NSMenu alloc] init]];

    // Application menu
    menu = [[NSMenu alloc] initWithTitle:@""];
    [menu addItemWithTitle:@"About QEMU" action:@selector(do_about_menu_item:) keyEquivalent:@""]; // About QEMU
    [menu addItem:[NSMenuItem separatorItem]]; //Separator
    [menu addItemWithTitle:@"Hide QEMU" action:@selector(hide:) keyEquivalent:@"h"]; //Hide QEMU
    menuItem = (NSMenuItem *)[menu addItemWithTitle:@"Hide Others" action:@selector(hideOtherApplications:) keyEquivalent:@"h"]; // Hide Others
    [menuItem setKeyEquivalentModifierMask:(NSEventModifierFlagOption|NSEventModifierFlagCommand)];
    [menu addItemWithTitle:@"Show All" action:@selector(unhideAllApplications:) keyEquivalent:@""]; // Show All
    [menu addItem:[NSMenuItem separatorItem]]; //Separator
    [menu addItemWithTitle:@"Quit QEMU" action:@selector(terminate:) keyEquivalent:@"q"];
    menuItem = [[NSMenuItem alloc] initWithTitle:@"Apple" action:nil keyEquivalent:@""];
    [menuItem setSubmenu:menu];
    [[NSApp mainMenu] addItem:menuItem];
    [NSApp performSelector:@selector(setAppleMenu:) withObject:menu]; // Workaround (this method is private since 10.4+)

    // Machine menu
    menu = [[NSMenu alloc] initWithTitle: @"Machine"];
    [menu setAutoenablesItems: NO];
    [menu addItem: [[[NSMenuItem alloc] initWithTitle: @"Pause" action: @selector(pauseQEMU:) keyEquivalent: @""] autorelease]];
    menuItem = [[[NSMenuItem alloc] initWithTitle: @"Resume" action: @selector(resumeQEMU:) keyEquivalent: @""] autorelease];
    [menu addItem: menuItem];
    [menuItem setEnabled: NO];
    [menu addItem: [NSMenuItem separatorItem]];
    [menu addItem: [[[NSMenuItem alloc] initWithTitle: @"Reset" action: @selector(restartQEMU:) keyEquivalent: @""] autorelease]];
    [menu addItem: [[[NSMenuItem alloc] initWithTitle: @"Power Down" action: @selector(powerDownQEMU:) keyEquivalent: @""] autorelease]];
    menuItem = [[[NSMenuItem alloc] initWithTitle: @"Machine" action:nil keyEquivalent:@""] autorelease];
    [menuItem setSubmenu:menu];
    [[NSApp mainMenu] addItem:menuItem];

    // View menu
    menu = [[NSMenu alloc] initWithTitle:@"View"];
    [menu addItem: [[[NSMenuItem alloc] initWithTitle:@"Enter Fullscreen" action:@selector(doToggleFullScreen:) keyEquivalent:@"f"] autorelease]]; // Fullscreen
    [menu addItem: [[[NSMenuItem alloc] initWithTitle:@"Zoom To Fit" action:@selector(zoomToFit:) keyEquivalent:@""] autorelease]];
    menuItem = [[[NSMenuItem alloc] initWithTitle:@"View" action:nil keyEquivalent:@""] autorelease];
    [menuItem setSubmenu:menu];
    [[NSApp mainMenu] addItem:menuItem];

    // Speed menu
    menu = [[NSMenu alloc] initWithTitle:@"Speed"];

    // Add the rest of the Speed menu items
    int p, percentage, throttle_pct;
    for (p = 10; p >= 0; p--)
    {
        percentage = p * 10 > 1 ? p * 10 : 1; // prevent a 0% menu item

        menuItem = [[[NSMenuItem alloc]
                   initWithTitle: [NSString stringWithFormat: @"%d%%", percentage] action:@selector(adjustSpeed:) keyEquivalent:@""] autorelease];

        if (percentage == 100) {
            [menuItem setState: NSOnState];
        }

        /* Calculate the throttle percentage */
        throttle_pct = -1 * percentage + 100;

        [menuItem setTag: throttle_pct];
        [menu addItem: menuItem];
    }
    menuItem = [[[NSMenuItem alloc] initWithTitle:@"Speed" action:nil keyEquivalent:@""] autorelease];
    [menuItem setSubmenu:menu];
    [[NSApp mainMenu] addItem:menuItem];

    // Window menu
    menu = [[NSMenu alloc] initWithTitle:@"Window"];
    [menu addItem: [[[NSMenuItem alloc] initWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"] autorelease]]; // Miniaturize
    menuItem = [[[NSMenuItem alloc] initWithTitle:@"Window" action:nil keyEquivalent:@""] autorelease];
    [menuItem setSubmenu:menu];
    [[NSApp mainMenu] addItem:menuItem];
    [NSApp setWindowsMenu:menu];

    // Help menu
    menu = [[NSMenu alloc] initWithTitle:@"Help"];
    [menu addItem: [[[NSMenuItem alloc] initWithTitle:@"QEMU Documentation" action:@selector(showQEMUDoc:) keyEquivalent:@"?"] autorelease]]; // QEMU Help
    menuItem = [[[NSMenuItem alloc] initWithTitle:@"Window" action:nil keyEquivalent:@""] autorelease];
    [menuItem setSubmenu:menu];
    [[NSApp mainMenu] addItem:menuItem];

    // Create an Application controller
    QemuCocoaAppController *appController = [[QemuCocoaAppController alloc] init];
    [NSApp setDelegate:appController];

    // Start the main event loop
    [NSApp run];

    [appController release];

    return 0;
    }
}



#pragma mark qemu
static void cocoa_update(DisplayChangeListener *dcl,
                         int x, int y, int w, int h)
{
    @autoreleasepool {

    COCOA_DEBUG("qemu_cocoa: cocoa_update\n");

    NSRect rect;
    if ([cocoaView cdx] == 1.0) {
        rect = NSMakeRect(x, [cocoaView gscreen].height - y - h, w, h);
    } else {
        rect = NSMakeRect(
            x * [cocoaView cdx],
            ([cocoaView gscreen].height - y - h) * [cocoaView cdy],
            w * [cocoaView cdx],
            h * [cocoaView cdy]);
    }
    [cocoaView setNeedsDisplayInRect:rect];

    }
}

static void cocoa_switch(DisplayChangeListener *dcl,
                         DisplaySurface *surface)
{
    @autoreleasepool {

    COCOA_DEBUG("qemu_cocoa: cocoa_switch\n");
    [cocoaView switchSurface:surface];
    }
}

static void cocoa_refresh(DisplayChangeListener *dcl)
{
    @autoreleasepool {

    COCOA_DEBUG("qemu_cocoa: cocoa_refresh\n");
    graphic_hw_update(NULL);

    if (qemu_input_is_absolute()) {
        if (!cocoaView.absoluteEnabled) {
            if ([cocoaView isMouseGrabbed]) {
                [cocoaView ungrabMouse];
            }
        }
        cocoaView.absoluteEnabled = YES;
    }

    NSDate *distantPast;
    NSEvent *event;
    distantPast = [NSDate distantPast];
    do {
        event = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:distantPast
                        inMode: NSDefaultRunLoopMode dequeue:YES];
        if (event != nil) {
            [cocoaView handleEvent:event];
        }
    } while(event != nil);
    }
}

static void cocoa_cleanup(void)
{
    COCOA_DEBUG("qemu_cocoa: cocoa_cleanup\n");
    g_free(dcl);
}

static const DisplayChangeListenerOps dcl_ops = {
    .dpy_name          = "cocoa",
    .dpy_gfx_update = cocoa_update,
    .dpy_gfx_switch = cocoa_switch,
    .dpy_refresh = cocoa_refresh,
};

/* Returns a name for a given console */
static NSString * getConsoleName(QemuConsole * console)
{
    return [NSString stringWithFormat: @"%s", qemu_console_get_label(console)];
}

/* Add an entry to the View menu for each console */
static void add_console_menu_entries(void)
{
    NSMenu *menu;
    NSMenuItem *menuItem;
    int index = 0;

    menu = [[[NSApp mainMenu] itemWithTitle:@"View"] submenu];

    [menu addItem:[NSMenuItem separatorItem]];

    while (qemu_console_lookup_by_index(index) != NULL) {
        menuItem = [[[NSMenuItem alloc] initWithTitle: getConsoleName(qemu_console_lookup_by_index(index))
                                               action: @selector(displayConsole:) keyEquivalent: @""] autorelease];
        [menuItem setTag: index];
        [menu addItem: menuItem];
        index++;
    }
}

/* Make menu items for all removable devices.
 * Each device is given an 'Eject' and 'Change' menu item.
 */
static void addRemovableDevicesMenuItems(void)
{
    NSMenu *menu;
    NSMenuItem *menuItem;
    BlockInfoList *currentDevice, *pointerToFree;
    NSString *deviceName;

    currentDevice = qmp_query_block(NULL);
    pointerToFree = currentDevice;
    if(currentDevice == NULL) {
        NSBeep();
        QEMU_Alert(@"Failed to query for block devices!");
        return;
    }

    menu = [[[NSApp mainMenu] itemWithTitle:@"Machine"] submenu];

    // Add a separator between related groups of menu items
    [menu addItem:[NSMenuItem separatorItem]];

    // Set the attributes to the "Removable Media" menu item
    NSString *titleString = @"Removable Media";
    NSMutableAttributedString *attString=[[NSMutableAttributedString alloc] initWithString:titleString];
    NSColor *newColor = [NSColor blackColor];
    NSFontManager *fontManager = [NSFontManager sharedFontManager];
    NSFont *font = [fontManager fontWithFamily:@"Helvetica"
                                          traits:NSBoldFontMask|NSItalicFontMask
                                          weight:0
                                            size:14];
    [attString addAttribute:NSFontAttributeName value:font range:NSMakeRange(0, [titleString length])];
    [attString addAttribute:NSForegroundColorAttributeName value:newColor range:NSMakeRange(0, [titleString length])];
    [attString addAttribute:NSUnderlineStyleAttributeName value:[NSNumber numberWithInt: 1] range:NSMakeRange(0, [titleString length])];

    // Add the "Removable Media" menu item
    menuItem = [NSMenuItem new];
    [menuItem setAttributedTitle: attString];
    [menuItem setEnabled: NO];
    [menu addItem: menuItem];

    /* Loop through all the block devices in the emulator */
    while (currentDevice) {
        deviceName = [[NSString stringWithFormat: @"%s", currentDevice->value->device] retain];

        if(currentDevice->value->removable) {
            menuItem = [[NSMenuItem alloc] initWithTitle: [NSString stringWithFormat: @"Change %s...", currentDevice->value->device]
                                                  action: @selector(changeDeviceMedia:)
                                           keyEquivalent: @""];
            [menu addItem: menuItem];
            [menuItem setRepresentedObject: deviceName];
            [menuItem autorelease];

            menuItem = [[NSMenuItem alloc] initWithTitle: [NSString stringWithFormat: @"Eject %s", currentDevice->value->device]
                                                  action: @selector(ejectDeviceMedia:)
                                           keyEquivalent: @""];
            [menu addItem: menuItem];
            [menuItem setRepresentedObject: deviceName];
            [menuItem autorelease];
        }
        currentDevice = currentDevice->next;
    }
    qapi_free_BlockInfoList(pointerToFree);
}

static void cocoa_display_init(DisplayState *ds, DisplayOptions *opts)
{
    COCOA_DEBUG("qemu_cocoa: cocoa_display_init\n");

    /* if fullscreen mode is to be used */
    if (opts->has_full_screen && opts->full_screen) {
        [NSApp activateIgnoringOtherApps: YES];
        [(QemuCocoaAppController *)[[NSApplication sharedApplication] delegate] toggleFullScreen: nil];
    }

    dcl = g_malloc0(sizeof(DisplayChangeListener));

    // register vga output callbacks
    dcl->ops = &dcl_ops;
    register_displaychangelistener(dcl);

    // register cleanup function
    atexit(cocoa_cleanup);

    /* At this point QEMU has created all the consoles, so we can add View
     * menu entries for them.
     */
    add_console_menu_entries();

    /* Give all removable devices a menu item.
     * Has to be called after QEMU has started to
     * find out what removable devices it has.
     */
    addRemovableDevicesMenuItems();
}

static QemuDisplay qemu_display_cocoa = {
    .type       = DISPLAY_TYPE_COCOA,
    .init       = cocoa_display_init,
};

static void register_cocoa(void)
{
    qemu_display_register(&qemu_display_cocoa);
}

type_init(register_cocoa);
