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
#include "qmp-commands.h"
#include "sysemu/blockdev.h"
#include "qemu-version.h"
#include <Carbon/Carbon.h>
#include "qom/cpu.h"

#ifndef MAC_OS_X_VERSION_10_5
#define MAC_OS_X_VERSION_10_5 1050
#endif
#ifndef MAC_OS_X_VERSION_10_6
#define MAC_OS_X_VERSION_10_6 1060
#endif
#ifndef MAC_OS_X_VERSION_10_10
#define MAC_OS_X_VERSION_10_10 101000
#endif

/* These are defined to quiet deprecation warnings */
#ifdef __MAC_10_12
#define NSAnyEventMask NSEventMaskAny

#define NSAlternateKeyMask NSEventModifierFlagOption
#define NSCommandKeyMask NSEventModifierFlagCommand
#define NSControlKeyMask NSEventModifierFlagControl

#define NSCenterTextAlignment NSTextAlignmentCenter

//NSWindowStyle flags
#define NSMiniaturizableWindowMask NSWindowStyleMaskMiniaturizable
#define NSClosableWindowMask NSWindowStyleMaskClosable
#define NSTitledWindowMask NSWindowStyleMaskTitled
#define NSBorderlessWindowMask NSWindowStyleMaskBorderless

// NSEvent flags
#define NSScrollWheel NSEventTypeScrollWheel
#define NSFlagsChanged NSEventTypeFlagsChanged
#define NSKeyDown NSEventTypeKeyDown
#define NSKeyUp NSEventTypeKeyUp
#define NSMouseMoved NSEventTypeMouseMoved
#define NSLeftMouseDown NSEventTypeLeftMouseDown
#define NSRightMouseDown NSEventTypeRightMouseDown
#define NSOtherMouseDown NSEventTypeOtherMouseDown
#define NSLeftMouseDragged NSEventTypeLeftMouseDragged
#define NSRightMouseDragged NSEventTypeRightMouseDragged
#define NSOtherMouseDragged NSEventTypeOtherMouseDragged
#define NSLeftMouseUp NSEventTypeLeftMouseUp
#define NSRightMouseUp NSEventTypeRightMouseUp
#define NSOtherMouseUp NSEventTypeOtherMouseUp
#endif


//#define DEBUG

#ifdef DEBUG
#define COCOA_DEBUG(...)  { (void) fprintf (stdout, __VA_ARGS__); }
#else
#define COCOA_DEBUG(...)  ((void) 0)
#endif

#define cgrect(nsrect) (*(CGRect *)&(nsrect))
#define USB_DISK_ID "USB_DISK"
#define EJECT_IMAGE_FILE_TAG 2099
#define MAX_DEVICE_NAME_SIZE 10

typedef struct {
    int width;
    int height;
    int bitsPerComponent;
    int bitsPerPixel;
} QEMUScreen;

static NSWindow *normalWindow, *about_window, *stop_window;
static DisplayChangeListener *dcl;
static int last_buttons;

int gArgc;
char **gArgv;
bool stretch_video;
static NSTextField *pauseLabel;
static NSArray * supportedImageFileTypes;

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
    [0x7f7f] = Q_KEY_CODE_POWER,
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
}

/* Sends a command to the monitor console */
static void sendMonitorCommand(const char *commandString)
{
    int index;
    char * consoleName;
    static QemuConsole *monitor;

    /* If the monitor console hasn't been found yet */
    if(!monitor) {
        index = 0;
        /* Find the monitor console */
        while (qemu_console_lookup_by_index(index) != NULL) {
            consoleName = qemu_console_get_label(qemu_console_lookup_by_index(index));
            if(strstr(consoleName, "monitor")) {
                monitor = qemu_console_lookup_by_index(index);
                break;
            }
            index++;
        }
    }

    /* If the monitor console was not found */
    if(!monitor) {
        NSBeep();
        QEMU_Alert(@"Failed to find the monitor console!");
        return;
    }

    /* send each letter in the commandString to the monitor */
    for (index = 0; index < strlen(commandString); index++) {
        kbd_put_keysym_console(monitor, commandString[index]);
    }

    /* simulate the user pushing the return key */
    kbd_put_keysym_console(monitor, '\n');
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
 Determine if the current emulator has the specified device.
 device_name: the name of the device you want: floppy, cd
 official_name: QEMU's name for the device: floppy0, ide-cd0
*/
static bool emulatorHasDevice(const char * device_name, char * official_name)
{
    BlockInfoList * block_device_data;
    block_device_data = qmp_query_block(false);
    if(block_device_data == NULL) {
        return false;
    }
    while(block_device_data->next != NULL) {
        /* If we found the device */
        if (strstr(block_device_data->value->device, device_name)) {
            strncpy(official_name, block_device_data->value->device, MAX_DEVICE_NAME_SIZE);
            qapi_free_BlockInfoList(block_device_data);
            return true;
        }
        block_device_data = block_device_data->next;
    }
    return false;
}

/* Translate an ascii character to sendkey compatible input */
static char *ascii_to_sendkey(int c)
{
    /* For lowercase letters and numbers */
    if (isalnum(c) && !isupper(c)) {
        return g_strdup_printf("%c", c);
    }

    /* For uppercase letters */
    if (isupper(c)) {
        return g_strdup_printf("shift-%c", tolower(c));
    }

    const char *translation_matrix[] = {
    [' '] = "spc",
    [','] = "comma",
    ['<'] = "shift-comma",
    ['.'] = "dot",
    ['>'] = "shift-dot",
    ['/'] = "slash",
    ['?'] = "shift-slash",
    [';'] = "semicolon",
    [':'] = "shift-semicolon",
    ['\''] = "apostrophe",
    ['\"'] = "shift-apostrophe",
    ['\n'] = "ret",
    ['['] = "bracket_left",
    ['{'] = "shift-bracket_left",
    [']'] = "bracket_right",
    ['}'] = "shift-bracket_right",
    ['\\'] = "backslash",
    ['|'] = "shift-backslash",
    ['\t'] = "tab",
    ['`'] = "grave_accent",
    ['~'] = "shift-grave_accent",
    ['!'] = "shift-1",
    ['@'] = "shift-2",
    ['#'] = "shift-3",
    ['$'] = "shift-4",
    ['%'] = "shift-5",
    ['^'] = "shift-6",
    ['&'] = "shift-7",
    ['*'] = "shift-8",
    ['('] = "shift-9",
    [')'] = "shift-0",
    ['-'] = "minus",
    ['_'] = "shift-minus",
    ['='] = "equal",
    ['+'] = "shift-equal"
    };

    /* If an unicode character is encounted display a question mark */
    if (c >= ARRAY_SIZE(translation_matrix) || c < 0) {
        return g_strdup_printf("shift-slash");
    }

    return g_strdup_printf("%s", translation_matrix[c]);
}

/* 
 * Determines if the current event is caused by a key being pushed.
 * The modifier keys (i.e. Command) don't sent a keydown or keyup event.
 */
static bool isKeyDownEvent(NSEvent *event)
{
    /* Translate a key to a key mask */
    const int key_translation[] = {
    [kVK_Command] = NSCommandKeyMask,
    [54] = NSCommandKeyMask,    /* There is no kVK_RightCommand */
    [kVK_Option] = NSAlternateKeyMask,
    [kVK_RightOption] = NSAlternateKeyMask,
    [kVK_Control] = NSControlKeyMask,
    [kVK_RightControl] = NSControlKeyMask,
    [kVK_Shift] = NSShiftKeyMask,
    [kVK_RightShift] = NSShiftKeyMask
    };
    
    /* See if the key that caused the event is currently down */
    return [event modifierFlags] & key_translation[[event keyCode]];
}

/*
 ------------------------------------------------------
    QemuCocoaView
 ------------------------------------------------------
*/
@interface QemuCocoaView : NSView
{
    QEMUScreen screen;
    NSWindow *fullScreenWindow;
    CGFloat cx,cy,cw,ch,cdx,cdy;
    CGDataProviderRef dataProviderRef;
    int modifiers_state[256];
    BOOL isMouseGrabbed;
    BOOL isFullscreen;
    BOOL isAbsoluteEnabled;
    BOOL isMouseDeassociated;
}
- (void) switchSurface:(DisplaySurface *)surface;
- (void) grabMouse;
- (void) ungrabMouse;
- (void) toggleFullScreen:(id)sender;
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
@property (readonly, getter=isMouseGrabbed) BOOL mouseGrabbed;
@property (getter=isAbsoluteEnabled) BOOL absoluteEnabled;
@property (readonly, getter=isMouseDeassociated) BOOL mouseDeassociated;
@property (readonly) CGFloat cdx;
@property (readonly) CGFloat cdy;
@property (readonly) QEMUScreen gscreen;
- (void) raiseAllKeys;
@end

QemuCocoaView *cocoaView;

@implementation QemuCocoaView
@synthesize mouseGrabbed = isMouseGrabbed;
@synthesize absoluteEnabled = isAbsoluteEnabled;
@synthesize mouseDeassociated = isMouseDeassociated;
@synthesize cdx;
@synthesize cdy;
@synthesize gscreen = screen;

- (id)initWithFrame:(NSRect)frameRect
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
        CGColorSpaceRef col =
        #ifdef __LITTLE_ENDIAN__
            CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB); //colorspace for OS X >= 10.4
        #else
            CGColorSpaceCreateDeviceRGB(); //colorspace for OS X < 10.4 (actually ppc)
        #endif
        
        CGImageRef imageRef = CGImageCreate(
            screen.width, //width
            screen.height, //height
            screen.bitsPerComponent, //bitsPerComponent
            screen.bitsPerPixel, //bitsPerPixel
            (screen.width * (screen.bitsPerComponent/2)), //bytesPerRow
            col,
            kCGBitmapByteOrder32Host | kCGImageAlphaNoneSkipFirst,
            dataProviderRef, //provider
            NULL, //decode
            0, //interpolate
            kCGRenderingIntentDefault //intent
        );
        CGColorSpaceRelease(col);
        // selective drawing code (draws only dirty rectangles) (OS X >= 10.4)
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
        [[fullScreenWindow contentView] setFrame:[[NSScreen mainScreen] frame]];
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
        isFullscreen = FALSE;
        [self ungrabMouse];
        [self setContentDimensions];
        if ([NSView respondsToSelector:@selector(exitFullScreenModeWithOptions:)]) { // test if "exitFullScreenModeWithOptions" is supported on host at runtime
            [self exitFullScreenModeWithOptions:nil];
        } else {
            [fullScreenWindow close];
            [normalWindow setContentView: self];
            [normalWindow makeKeyAndOrderFront: self];
            [NSMenu setMenuBarVisible:YES];
        }
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
                styleMask:NSBorderlessWindowMask
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

- (void) handleEvent:(NSEvent *)event
{
    COCOA_DEBUG("QemuCocoaView: handleEvent\n");

    int buttons = 0;
    int keycode;
    bool mouse_event = false;
    NSPoint p = [event locationInWindow];

    switch ([event type]) {
        case NSFlagsChanged:
            keycode = cocoa_keycode_to_qemu([event keyCode]);

            if ((keycode == Q_KEY_CODE_META_L || keycode == Q_KEY_CODE_META_R)
               && !isMouseGrabbed) {
              /* Don't pass command key changes to guest unless mouse is grabbed */
              keycode = 0;
            }

            if (keycode) {
                // emulate caps lock and num lock keydown and keyup
                if (keycode == Q_KEY_CODE_CAPS_LOCK ||
                    keycode == Q_KEY_CODE_NUM_LOCK) {
                    qemu_input_event_send_key_qcode(dcl->con, keycode, true);
                    qemu_input_event_send_key_qcode(dcl->con, keycode, false);
                } else if (qemu_console_is_graphic(NULL)) {
                    if (isKeyDownEvent(event)) { //keydown
                        qemu_input_event_send_key_qcode(dcl->con, keycode, true);
                        modifiers_state[keycode] = 1;
                    } else { // keyup
                        qemu_input_event_send_key_qcode(dcl->con, keycode, false);
                        modifiers_state[keycode] = 0;
                    }
                }
            }

            // release Mouse grab when pressing ctrl+alt
            if (([event modifierFlags] & NSControlKeyMask) && ([event modifierFlags] & NSAlternateKeyMask)) {
                [self ungrabMouse];
            }
            break;
        case NSKeyDown:
            keycode = cocoa_keycode_to_qemu([event keyCode]);

            // forward command key combos to the host UI unless the mouse is grabbed
            if (!isMouseGrabbed && ([event modifierFlags] & NSCommandKeyMask)) {
                [NSApp sendEvent:event];
                return;
            }

            // default

            // handle control + alt Key Combos (ctrl+alt is reserved for QEMU)
            if (([event modifierFlags] & NSControlKeyMask) && ([event modifierFlags] & NSAlternateKeyMask)) {
                switch (keycode) {

                    // enable graphic console
                    case Q_KEY_CODE_1 ... Q_KEY_CODE_9: // '1' to '9' keys
                        console_select(keycode - 11);
                        break;
                }

            // handle keys for graphic console
            } else if (qemu_console_is_graphic(NULL)) {
                qemu_input_event_send_key_qcode(dcl->con, keycode, true);

            // handlekeys for Monitor
            } else {
                int keysym = 0;
                switch([event keyCode]) {
                case 115:
                    keysym = QEMU_KEY_HOME;
                    break;
                case 117:
                    keysym = QEMU_KEY_DELETE;
                    break;
                case 119:
                    keysym = QEMU_KEY_END;
                    break;
                case 123:
                    keysym = QEMU_KEY_LEFT;
                    break;
                case 124:
                    keysym = QEMU_KEY_RIGHT;
                    break;
                case 125:
                    keysym = QEMU_KEY_DOWN;
                    break;
                case 126:
                    keysym = QEMU_KEY_UP;
                    break;
                default:
                    {
                        NSString *ks = [event characters];
                        if ([ks length] > 0)
                            keysym = [ks characterAtIndex:0];
                    }
                }
                if (keysym)
                    kbd_put_keysym(keysym);
            }
            break;
        case NSKeyUp:
            keycode = cocoa_keycode_to_qemu([event keyCode]);

            // don't pass the guest a spurious key-up if we treated this
            // command-key combo as a host UI action
            if (!isMouseGrabbed && ([event modifierFlags] & NSCommandKeyMask)) {
                return;
            }

            if (qemu_console_is_graphic(NULL)) {
                qemu_input_event_send_key_qcode(dcl->con, keycode, false);
            }
            break;
        case NSMouseMoved:
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
        case NSLeftMouseDown:
            if ([event modifierFlags] & NSCommandKeyMask) {
                buttons |= MOUSE_EVENT_RBUTTON;
            } else {
                buttons |= MOUSE_EVENT_LBUTTON;
            }
            mouse_event = true;
            break;
        case NSRightMouseDown:
            buttons |= MOUSE_EVENT_RBUTTON;
            mouse_event = true;
            break;
        case NSOtherMouseDown:
            buttons |= MOUSE_EVENT_MBUTTON;
            mouse_event = true;
            break;
        case NSLeftMouseDragged:
            if ([event modifierFlags] & NSCommandKeyMask) {
                buttons |= MOUSE_EVENT_RBUTTON;
            } else {
                buttons |= MOUSE_EVENT_LBUTTON;
            }
            mouse_event = true;
            break;
        case NSRightMouseDragged:
            buttons |= MOUSE_EVENT_RBUTTON;
            mouse_event = true;
            break;
        case NSOtherMouseDragged:
            buttons |= MOUSE_EVENT_MBUTTON;
            mouse_event = true;
            break;
        case NSLeftMouseUp:
            mouse_event = true;
            if (!isMouseGrabbed && [self screenContainsPoint:p]) {
                if([[self window] isKeyWindow]) {
                    [self grabMouse];
                }
            }
            break;
        case NSRightMouseUp:
            mouse_event = true;
            break;
        case NSOtherMouseUp:
            mouse_event = true;
            break;
        case NSScrollWheel:
            if (isMouseGrabbed) {
                buttons |= ([event deltaY] < 0) ?
                    MOUSE_EVENT_WHEELUP : MOUSE_EVENT_WHEELDN;
            }
            mouse_event = true;
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
        if (isMouseGrabbed && ([[self window] isKeyWindow] || isFullscreen) &&
            (last_buttons != buttons)) {
            static uint32_t bmap[INPUT_BUTTON__MAX] = {
                [INPUT_BUTTON_LEFT]       = MOUSE_EVENT_LBUTTON,
                [INPUT_BUTTON_MIDDLE]     = MOUSE_EVENT_MBUTTON,
                [INPUT_BUTTON_RIGHT]      = MOUSE_EVENT_RBUTTON,
                [INPUT_BUTTON_WHEEL_UP]   = MOUSE_EVENT_WHEELUP,
                [INPUT_BUTTON_WHEEL_DOWN] = MOUSE_EVENT_WHEELDN,
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
                    qemu_input_queue_abs(dcl->con, INPUT_AXIS_X, p.x, screen.width);
                    qemu_input_queue_abs(dcl->con, INPUT_AXIS_Y, screen.height - p.y, screen.height);
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
            [normalWindow setTitle:[NSString stringWithFormat:@"QEMU %s - (Press ctrl + alt to release Mouse)", qemu_name]];
        else
            [normalWindow setTitle:@"QEMU - (Press ctrl + alt to release Mouse)"];
    }
    [self hideCursor];
    if (!isAbsoluteEnabled) {
        isMouseDeassociated = TRUE;
        CGAssociateMouseAndMouseCursorPosition(FALSE);
    }
    isMouseGrabbed = TRUE; // while isMouseGrabbed = TRUE, QemuCocoaApp sends all events to [cocoaView handleEvent:]
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
        isMouseDeassociated = FALSE;
    }
    isMouseGrabbed = FALSE;
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
@interface QemuCocoaAppController : NSObject
#if (MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_6)
                      <NSMenuDelegate, NSWindowDelegate, NSApplicationDelegate>
#else
                      <NSMenuDelegate>
#endif
{
    NSTimer *paste_timer;
}
- (void)startEmulationWithArgc:(int)argc argv:(char**)argv;
- (void)doToggleFullScreen:(id)sender;
- (IBAction)toggleFullScreen:(id)sender;
- (IBAction)showQEMUDoc:(id)sender;
- (IBAction)zoomToFit:(id) sender;
- (IBAction)displayConsole:(id)sender;
- (IBAction)pauseQEMU:(id)sender;
- (IBAction)resumeQEMU:(id)sender;
- (void)displayPause;
- (void)removePause;
- (IBAction)restartQEMU:(id)sender;
- (IBAction)powerDownQEMU:(id)sender;
- (IBAction)ejectDeviceMedia:(id)sender;
- (IBAction)changeDeviceMedia:(id)sender;
- (BOOL)verifyQuit;
- (void)openDocumentation:(NSString *)filename;
- (IBAction) do_about_menu_item: (id) sender;
- (void)make_about_window;
- (IBAction)mountImageFile:(id)sender;
- (IBAction)ejectImageFile:(id)sender;
- (void)updateEjectImageMenuItems;
- (IBAction)do_send_key_menu_item:(id)sender;
- (IBAction)adjustSpeed:(id)sender;
- (IBAction)useRealCdrom:(id)sender;
- (IBAction)doPaste:(id)sender;
- (void)make_stop_window;
- (void)do_stop_button:(id)sender;
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
            styleMask:NSTitledWindowMask|NSMiniaturizableWindowMask|NSClosableWindowMask
            backing:NSBackingStoreBuffered defer:NO];
        if(!normalWindow) {
            fprintf(stderr, "(cocoa) can't create window\n");
            exit(1);
        }
        [normalWindow setAcceptsMouseMovedEvents:YES];
        [normalWindow setTitle:@"QEMU"];
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
        if (!supportedImageFileTypes) {
        supportedImageFileTypes = [[NSArray arrayWithObjects: @"img", @"iso", @"dmg",
                                 @"qcow", @"qcow2", @"cloop", @"vmdk", @"cdr",
                                 @"toast", nil] copy];
        }
        [self make_about_window];
        [self make_stop_window];
    }
    return self;
}

- (void) dealloc
{
    COCOA_DEBUG("QemuCocoaAppController: dealloc\n");

    if (cocoaView)
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

    qemu_system_shutdown_request();
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
        NSURL * file = [[openPanel URLs] objectAtIndex: 0];
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
                    styleMask:NSTitledWindowMask | NSClosableWindowMask |
                    NSMiniaturizableWindowMask
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
    [name_label setAlignment: NSCenterTextAlignment];
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
    [version_label setAlignment: NSCenterTextAlignment];
    [version_label setDrawsBackground: NO];

    /* Create the version string*/
    NSString *version_string;
    version_string = [[NSString alloc] initWithFormat:
    @"QEMU emulator version %s%s", QEMU_VERSION, QEMU_PKGVERSION];
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
    [copyright_label setAlignment: NSCenterTextAlignment];
    [copyright_label setStringValue: [NSString stringWithFormat: @"%s",
                                     QEMU_COPYRIGHT]];
    [superView addSubview: copyright_label];
}

/* Displays a dialog box asking the user for an image file to mount */
- (void)mountImageFile:(id)sender
{
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

        static int usbDiskCount;  // used for the ID
        char *commandBuffer, *fileName, *idString, *fileNameHint;
        NSString *buffer;
        const int fileNameHintSize = 10;

        fileName = g_strdup_printf("%s",
                            [file fileSystemRepresentation]);
        buffer = [file lastPathComponent];
        buffer = [buffer stringByDeletingPathExtension];
        if([buffer length] > fileNameHintSize) {
            buffer = [buffer substringToIndex: fileNameHintSize];
        }
        fileNameHint = g_strdup_printf("%s",
                        [buffer UTF8String]);
        idString = g_strdup_printf("%s_%s_%d", USB_DISK_ID, fileNameHint, usbDiskCount);
        commandBuffer = g_strdup_printf("drive_add 0 if=none,id=%s,file=%s",
                                                            idString, fileName);
        sendMonitorCommand(commandBuffer);
        commandBuffer = g_strdup_printf("device_add usb-storage,"
                                         "id=%s,drive=%s", idString, idString);
        sendMonitorCommand(commandBuffer);
        [self updateEjectImageMenuItems];
        usbDiskCount++;
        g_free(fileName);
        g_free(fileNameHint);
        g_free(idString);
        g_free(commandBuffer);
    }
}

/* Removes an image file from QEMU */
- (void)ejectImageFile:(id) sender
{
    char *commandBuffer;
    NSString *imageFileID;

    imageFileID = [sender representedObject];
    if (imageFileID == nil) {
        NSBeep();
        QEMU_Alert(@"Could not find image file's ID!");
        return;
    }

    commandBuffer = g_strdup_printf("drive_del %s",
                    [imageFileID cStringUsingEncoding: NSASCIIStringEncoding]);
    sendMonitorCommand(commandBuffer);
    g_free(commandBuffer);

    commandBuffer = g_strdup_printf("device_del %s",
                        [imageFileID cStringUsingEncoding: NSASCIIStringEncoding]);
    sendMonitorCommand(commandBuffer);
    g_free(commandBuffer);

    [self updateEjectImageMenuItems];
}

/* Gives each mounted image file an eject menu item */
- (void) updateEjectImageMenuItems
{
    NSMenu *machineMenu;
    machineMenu = [[[NSApp mainMenu] itemWithTitle:@"Machine"] submenu];

    /* Remove old menu items*/
    NSMenu * ejectSubmenu;
    ejectSubmenu = [[machineMenu itemWithTag: EJECT_IMAGE_FILE_TAG] submenu];
    if(!ejectSubmenu) {
        NSBeep();
        QEMU_Alert(@"Failed to find eject submenu!");
        return;
    }
    int index;
    for (index = 0; index < [ejectSubmenu numberOfItems]; index++) {
        [ejectSubmenu removeItemAtIndex: 0];
    }
     /* Needed probably because of a bug with cocoa */
    if ([ejectSubmenu numberOfItems] > 0) {
        [ejectSubmenu removeItemAtIndex: 0];
    }

    BlockInfoList *currentDevice;
    currentDevice = qmp_query_block(NULL);

    NSString *fileName, *deviceName;
    NSMenuItem *ejectFileMenuItem;  /* Used with each mounted image file */

    /* Look for mounted image files */
    while(currentDevice) {
        if (!currentDevice->value || !currentDevice->value->inserted
                                  || !currentDevice->value->inserted->file) {
            currentDevice = currentDevice->next;
            continue;
        }

        /* if the device's name is the generated ID */
        if (!strstr(currentDevice->value->device, USB_DISK_ID)) {
            currentDevice = currentDevice->next;
            continue;
        }

        fileName = [NSString stringWithFormat: @"%s", currentDevice->value->inserted->file];
        fileName = [fileName lastPathComponent]; /* To obtain only the file name */

        ejectFileMenuItem = [[NSMenuItem alloc] initWithTitle: [NSString stringWithFormat: @"Eject %@", fileName]
                                                  action: @selector(ejectImageFile:)
                                           keyEquivalent: @""];
        [ejectSubmenu addItem: ejectFileMenuItem];
        deviceName = [NSString stringWithFormat: @"%s", currentDevice->value->device];
        [ejectFileMenuItem setRepresentedObject: deviceName];
        [ejectFileMenuItem autorelease];
        currentDevice = currentDevice->next;
    }

    /* Add default menu item if submenu is empty */
    if ([ejectSubmenu numberOfItems] == 0) {

        /* Create the default menu item */
        NSMenuItem *emptyMenuItem;
        emptyMenuItem = [NSMenuItem new];
        [emptyMenuItem setTitle: @"No items available"];
        [emptyMenuItem setEnabled: NO];

        /* Add the default menu item to the submenu */
        [ejectSubmenu addItem: emptyMenuItem];
        [emptyMenuItem release];
    }
}

/* The action method to the items in the Send Keys menu */
- (IBAction)do_send_key_menu_item:(id)sender {
    NSString *keys = [sender representedObject];
    NSArray *key_array = [keys componentsSeparatedByString: @","];
    #define array_size 0xff
    int keydown_array[array_size] = {0};
    int index, keycode;
    NSString *hex_string;

    for (index = 0; index < [key_array count]; index++) {
        hex_string = [key_array objectAtIndex: index];
        sscanf([hex_string cStringUsingEncoding: NSASCIIStringEncoding], "%x",
               &keycode);
        keycode = cocoa_keycode_to_qemu(keycode);
        qemu_input_event_send_key_qcode(dcl->con, keycode, true);
        keydown_array[keycode] = 1;
    }

    /* Send keyup event for all keys that were sent */
    for (index = 0; index < array_size; index++) {
        if (keydown_array[index] != 0) {
            qemu_input_event_send_key_qcode(dcl->con, index, false);
        }
    }
}

/* Used by the Speed menu items */
- (void)adjustSpeed:(id)sender
{
    int speed, menu_number, count, item;
    NSMenu *menu;
    NSArray *itemArray;

    // uncheck all the menu items in the Speed menu
    menu = [sender menu];
    if (menu != nil)
    {
        count = [[menu itemArray] count];
        itemArray = [menu itemArray];
        for (item = 0; item < count; item++)  // unselect each item
            [[itemArray objectAtIndex: item] setState: NSOffState];
    }

    // check the menu item
    [sender setState: NSOnState];

    // get the menu number
    menu_number = [sender tag];

    /* Calculate the speed */
    speed = -1 * menu_number + 100;
    cpu_throttle_set(speed);
    COCOA_DEBUG("cpu throttling at %d%c\n", cpu_throttle_get_percentage(), '%');
}

/* Have QEMU use a real CD/DVD disc */
- (void)useRealCdrom:(id)sender
{
    char cdrom_drive_name[MAX_DEVICE_NAME_SIZE];
    if (emulatorHasDevice("cd", cdrom_drive_name)) {
        Error *err = NULL;
        qmp_blockdev_change_medium(true,
                           [[sender representedObject] cStringUsingEncoding:
                           NSASCIIStringEncoding],
                           false, NULL,
                           "/dev/cdrom",
                           true, "raw",
                           false, 0,
                           &err);
        handleAnyDeviceErrors(err);
    } else {
        NSBeep();
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Alert";
        alert.informativeText = @"No real optical media found.";
        [alert runModal];
        [alert release];
    }
}

/* The action method to the Edit->Paste menu item */
- (void)doPaste:(id)sender
{
    const float speed = 1.0/7.0; // The smaller the number the faster the speed
    NSMutableString *counter_string = [[NSMutableString alloc] initWithCapacity: 10];
    [counter_string setString: @"0"];
    paste_timer = [NSTimer scheduledTimerWithTimeInterval: speed target: self selector:@selector(doPasteWorker:) userInfo:counter_string repeats:YES];
    [stop_window makeKeyAndOrderFront: nil];
    [counter_string autorelease];
}

/* Does the pasting work - called by a timer */
- (void)doPasteWorker:(NSTimer*) timer
{
    NSPasteboard *pboard = [NSPasteboard generalPasteboard];
    NSString *text = [pboard stringForType: NSStringPboardType];
    NSMutableString *counter_string;
    char *command_buffer, *buffer;
    int index;
    const int delay = 0;
    
    counter_string = [timer userInfo];
    index = [counter_string intValue];
    buffer = ascii_to_sendkey([text characterAtIndex: index]);
    command_buffer = g_strdup_printf("sendkey %s %d", buffer, delay);
    sendMonitorCommand(command_buffer);
    g_free(buffer);
    g_free(command_buffer);
    index++;
    
    /* If all the text has been pasted */
    if (index >= [text length]) {
        [timer invalidate];
        [stop_window orderOut: self];
    }
    [counter_string setString: [[NSNumber numberWithInt: index] stringValue]];
}

/*
 * If the user holds down a button and clicks on one of QEMU's menus, then
 * releases the button, a stuck key situation will take place after the menu is
 * closed.
 */
- (void)menuDidClose:(NSMenu *)menu
{
    [cocoaView raiseAllKeys];
}

/* Display a window with a stop button on it. For the pasting feature. */
- (void)make_stop_window
{
    /* Make the window */
    int window_width, window_height;
    window_width = 250;
    window_height = 90;
    NSRect contentRect = NSMakeRect(0, 0, window_width, window_height);
    stop_window = [[NSWindow alloc] initWithContentRect:contentRect
            styleMask:NSTitledWindowMask|NSMiniaturizableWindowMask
            backing:NSBackingStoreBuffered defer:NO];
    [stop_window setTitle: @"Pasting from clipboard..."];
    [stop_window center];

    /* Make the stop button */
    int button_width = 96;
    int button_height = 32;
    int button_x = window_width/2 - button_width/2;
    int button_y = 35;
    contentRect = NSMakeRect(button_x, button_y, button_width, button_height);
    NSButton *stop_button = [[[NSButton alloc] initWithFrame:contentRect] autorelease];
    [[stop_window contentView] addSubview: stop_button];
    [stop_button setTitle: @"Stop"];
    [stop_button setButtonType:NSMomentaryLightButton];
    [stop_button setBezelStyle:NSRoundedBezelStyle];
    [stop_button setTarget:self];
    [stop_button setAction:@selector(do_stop_button:)];
}

/* The stop button for the stop_window - stops pasting text into guest */
- (void)do_stop_button:(id)sender
{
    [stop_window orderOut: self];
    [paste_timer invalidate];
}

@end

/* Determines if '-sendkeymenu' is in the arguments sent to QEMU */
static int send_key_support(void) {
    int index;
    for (index = 0; index < gArgc; index++) {
        if (strcmp("-sendkeymenu", gArgv[index]) == 0) {
            return true;
        }
    }
    return false;
}

/* Remove one of the options from the global variable gArgv */
static void remove_option(int index)
{
    if (index < 0) {
        printf("Error: remove_option(): index less than zero: %d\n", index);
        return;
    } else if (index >= gArgc) {
        printf("Error: remove_option(): index too big: %d\n", index);
        return;
    }
    gArgc--;
    /* copy everything from index + 1 to the end */
    for (; index < gArgc; index++) {
        gArgv[index] = gArgv[index+1];
    }
}

/* Creates the Send Key menu and populates it */
static void create_send_key_menu(void) {
    NSMenu *menu;
    menu = [[NSMenu alloc] initWithTitle:@"Send Key"];
    [menu setDelegate: [NSApp delegate]];

    /* Find the index of the sendkeymenu and its items */
    int send_key_index = -1;
    int index;
    for (index = 0; index < gArgc; index++) {
        if (strcmp("-sendkeymenu", gArgv[index]) == 0) {
            send_key_index = index;
            break;
        }
    }

    /* if failed to find the -sendkeymenu argument */
    if (send_key_index == -1) {
        printf("Failed to find 'sendkeymenu' arguments\n");
        exit(EXIT_FAILURE);
    }

    NSMenuItem *menu_item;
    char *token;
    token = strtok(gArgv[send_key_index+1], ":");

    /* loop thru each set of keys */
    while (token) {
        menu_item = [[[NSMenuItem alloc] initWithTitle: [NSString stringWithCString: token encoding:NSASCIIStringEncoding]
                                                action: @selector(do_send_key_menu_item:)
                                         keyEquivalent: @""] autorelease];
        [menu addItem: menu_item];
        token = strtok(NULL, ":");

        [menu_item setRepresentedObject: [NSString stringWithCString: token encoding: NSASCIIStringEncoding]];
        token = strtok(NULL, ":");
    }

    /* Add the menu to QEMU's menubar */
    menu_item = [[[NSMenuItem alloc] initWithTitle: @"Send Key"
                                            action:nil
                                     keyEquivalent:@""] autorelease];
    [menu_item setSubmenu:menu];
    [[NSApp mainMenu] addItem:menu_item];

    /* Remove the -sendkeymenu and related options from the global variable */
    remove_option(send_key_index);
    remove_option(send_key_index);
}

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

    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];

    // Pull this console process up to being a fully-fledged graphical
    // app with a menubar and Dock icon
    ProcessSerialNumber psn = { 0, kCurrentProcess };
    TransformProcessType(&psn, kProcessTransformToForegroundApplication);

    [NSApplication sharedApplication];

    // Create an Application controller
    QemuCocoaAppController *appController = [[QemuCocoaAppController alloc] init];
    [NSApp setDelegate:appController];

    // Add menus
    NSMenu      *menu;
    NSMenuItem  *menuItem;

    [NSApp setMainMenu:[[NSMenu alloc] init]];

    // Application menu
    menu = [[NSMenu alloc] initWithTitle:@""];
    [menu setDelegate: appController];
    [menu addItemWithTitle:@"About QEMU" action:@selector(do_about_menu_item:) keyEquivalent:@""]; // About QEMU
    [menu addItem:[NSMenuItem separatorItem]]; //Separator
    [menu addItemWithTitle:@"Hide QEMU" action:@selector(hide:) keyEquivalent:@"h"]; //Hide QEMU
    menuItem = (NSMenuItem *)[menu addItemWithTitle:@"Hide Others" action:@selector(hideOtherApplications:) keyEquivalent:@"h"]; // Hide Others
    [menuItem setKeyEquivalentModifierMask:(NSAlternateKeyMask|NSCommandKeyMask)];
    [menu addItemWithTitle:@"Show All" action:@selector(unhideAllApplications:) keyEquivalent:@""]; // Show All
    [menu addItem:[NSMenuItem separatorItem]]; //Separator
    [menu addItemWithTitle:@"Quit QEMU" action:@selector(terminate:) keyEquivalent:@"q"];
    menuItem = [[NSMenuItem alloc] initWithTitle:@"Apple" action:nil keyEquivalent:@""];
    [menuItem setSubmenu:menu];
    [[NSApp mainMenu] addItem:menuItem];
    [NSApp performSelector:@selector(setAppleMenu:) withObject:menu]; // Workaround (this method is private since 10.4+)

    // Edit menu
    menu = [[NSMenu alloc] initWithTitle: @"Edit"];
    [menu setDelegate: appController];
    [menu addItem: [[[NSMenuItem alloc] initWithTitle:@"Paste" action:@selector(doPaste:) keyEquivalent:@""] autorelease]];
    menuItem = [[[NSMenuItem alloc] initWithTitle: @"Edit" action:nil keyEquivalent:@""] autorelease];
    [menuItem setSubmenu:menu];
    [[NSApp mainMenu] addItem:menuItem];

    // Machine menu
    menu = [[NSMenu alloc] initWithTitle: @"Machine"];
    [menu setDelegate: appController];
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

    // Send Key menu
    if (send_key_support()) {
        create_send_key_menu();
    }

    // View menu
    menu = [[NSMenu alloc] initWithTitle:@"View"];
    [menu setDelegate: appController];
    [menu addItem: [[[NSMenuItem alloc] initWithTitle:@"Enter Fullscreen" action:@selector(doToggleFullScreen:) keyEquivalent:@"f"] autorelease]]; // Fullscreen
    [menu addItem: [[[NSMenuItem alloc] initWithTitle:@"Zoom To Fit" action:@selector(zoomToFit:) keyEquivalent:@""] autorelease]];
    menuItem = [[[NSMenuItem alloc] initWithTitle:@"View" action:nil keyEquivalent:@""] autorelease];
    [menuItem setSubmenu:menu];
    [[NSApp mainMenu] addItem:menuItem];

    // Speed menu
    menu = [[NSMenu alloc] initWithTitle:@"Speed"];
    [menu setDelegate: appController];

    // The 100% menu item has to be checked at the start
    menuItem = [[[NSMenuItem alloc] initWithTitle:@"100%" action:@selector(adjustSpeed:) keyEquivalent:@""] autorelease];
    [menuItem setTag: 100];
    [menuItem setState: NSOnState];
    [menu addItem: menuItem];

    // Add the rest of the menu items
    int p, percentage;
    for (p = 9; p >= 0; p--)
    {
        percentage = p * 10 > 1 ? p * 10 : 1; // prevent a 0% menu item
        menuItem = [[[NSMenuItem alloc]
                   initWithTitle: [NSString stringWithFormat: @"%d%c", percentage, '%'] action:@selector(adjustSpeed:) keyEquivalent:@""] autorelease];
        [menuItem setTag: percentage];
        [menu addItem: menuItem];
    }
    menuItem = [[[NSMenuItem alloc] initWithTitle:@"Speed" action:nil keyEquivalent:@""] autorelease];
    [menuItem setSubmenu:menu];
    [[NSApp mainMenu] addItem:menuItem];

    // Window menu
    menu = [[NSMenu alloc] initWithTitle:@"Window"];
    [menu setDelegate: appController];
    [menu addItem: [[[NSMenuItem alloc] initWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"] autorelease]]; // Miniaturize
    menuItem = [[[NSMenuItem alloc] initWithTitle:@"Window" action:nil keyEquivalent:@""] autorelease];
    [menuItem setSubmenu:menu];
    [[NSApp mainMenu] addItem:menuItem];
    [NSApp setWindowsMenu:menu];

    // Help menu
    menu = [[NSMenu alloc] initWithTitle:@"Help"];
    [menu setDelegate: appController];
    [menu addItem: [[[NSMenuItem alloc] initWithTitle:@"QEMU Documentation" action:@selector(showQEMUDoc:) keyEquivalent:@"?"] autorelease]]; // QEMU Help
    menuItem = [[[NSMenuItem alloc] initWithTitle:@"Window" action:nil keyEquivalent:@""] autorelease];
    [menuItem setSubmenu:menu];
    [[NSApp mainMenu] addItem:menuItem];

    // Start the main event loop
    [NSApp run];

    [appController release];
    [pool release];

    return 0;
}



#pragma mark qemu
static void cocoa_update(DisplayChangeListener *dcl,
                         int x, int y, int w, int h)
{
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];

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

    [pool release];
}

static void cocoa_switch(DisplayChangeListener *dcl,
                         DisplaySurface *surface)
{
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];

    COCOA_DEBUG("qemu_cocoa: cocoa_switch\n");
    [cocoaView switchSurface:surface];
    [pool release];
}

static void cocoa_refresh(DisplayChangeListener *dcl)
{
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];

    COCOA_DEBUG("qemu_cocoa: cocoa_refresh\n");
    graphic_hw_update(NULL);

    if (qemu_input_is_absolute()) {
        if (![cocoaView isAbsoluteEnabled]) {
            if ([cocoaView isMouseGrabbed]) {
                [cocoaView ungrabMouse];
            }
        }
        [cocoaView setAbsoluteEnabled:YES];
    }

    NSDate *distantPast;
    NSEvent *event;
    distantPast = [NSDate distantPast];
    do {
        event = [NSApp nextEventMatchingMask:NSAnyEventMask untilDate:distantPast
                        inMode: NSDefaultRunLoopMode dequeue:YES];
        if (event != nil) {
            [cocoaView handleEvent:event];
        }
    } while(event != nil);
    [pool release];
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
            /* If CD-ROM drive found, add menu item for using real drive */
            if (strstr(currentDevice->value->device, "cd") != NULL) {
                menuItem = [[NSMenuItem alloc] initWithTitle: @"Use Real Optical Media"
                                                      action: @selector(useRealCdrom:)
                                               keyEquivalent: @""];
                [menu addItem: menuItem];
                [menuItem setRepresentedObject: deviceName];
                [menuItem autorelease];
            }

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
    [menu addItem: [[[NSMenuItem alloc] initWithTitle: @"Mount Image File..." action: @selector(mountImageFile:) keyEquivalent: @""] autorelease]];

    /* Create the eject menu item */
    NSMenuItem *ejectMenuItem;
    ejectMenuItem = [NSMenuItem new];
    [ejectMenuItem setTitle: @"Eject Image File"];
    [ejectMenuItem setTag: EJECT_IMAGE_FILE_TAG];
    [menu addItem: ejectMenuItem];
    [ejectMenuItem autorelease];

    /* Create the default menu item for the eject menu item's submenu*/
    NSMenuItem *emptyMenuItem;
    emptyMenuItem = [NSMenuItem new];
    [emptyMenuItem setTitle: @"No items available"];
    [emptyMenuItem setEnabled: NO];
    [emptyMenuItem autorelease];

    /* Add the default menu item to the submenu */
    NSMenu *submenu;
    submenu = [NSMenu new];
    [ejectMenuItem setSubmenu: submenu];
    [submenu addItem: emptyMenuItem];
    [submenu autorelease];
}

void cocoa_display_init(DisplayState *ds, int full_screen)
{
    COCOA_DEBUG("qemu_cocoa: cocoa_display_init\n");

    /* if fullscreen mode is to be used */
    if (full_screen == true) {
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
