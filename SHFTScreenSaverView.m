#import <ScreenSaver/ScreenSaver.h>
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <sys/mman.h>

#define MAX_BLINKS 6

typedef struct {
    CGRect frame;
} CellInfo;

typedef struct {
    int cellIdx;
    float opacity;
    float prevOpacity;
    float phase;
    float timer;
    float fadeInTime;
    float fadeOutTime;
} BlinkState;

// ── Static (process-wide) shared resources ──
// legacyScreenSaver creates NEW view instances per activation cycle.
// By making heavy allocations static, all instances share the same buffers.
// This eliminates ~34MB allocation per start/stop cycle.
static BOOL s_didSetup = NO;
static void *s_bgPixels = NULL;         // mmap'd background pixel backup
static CGImageRef s_bgImage = NULL;     // pre-rendered background as CGImage (set once)
static CellInfo *s_cellInfos = NULL;
static int s_cellCount = 0;
static int s_imgW = 0;
static int s_imgH = 0;
static size_t s_bytesPerRow = 0;
static size_t s_bufferSize = 0;

@interface SHFTScreenSaverView : ScreenSaverView
{
    BlinkState blinks[MAX_BLINKS];
    CFRunLoopTimerRef cfTimer;
    BOOL blinksInitialized;
}
- (void)tick;
@end

static void timerCallback(CFRunLoopTimerRef timer, void *info) {
    SHFTScreenSaverView *self = (__bridge SHFTScreenSaverView *)info;
    [self tick];
}

@implementation SHFTScreenSaverView

#define SHFT_GREEN_R (200.0/255.0)
#define SHFT_GREEN_G (216.0/255.0)
#define SHFT_GREEN_B (60.0/255.0)

#define SQ_REL_X      (642.0 / 800.0)
#define SQ_REL_Y_TOP  (324.0 / 800.0)
#define SQ_REL_W      (70.0 / 800.0)
#define SQ_REL_H      (70.0 / 800.0)

- (instancetype)initWithFrame:(NSRect)frame isPreview:(BOOL)isPreview
{
    self = [super initWithFrame:frame isPreview:isPreview];
    if (self) {
        [self setAnimationTimeInterval:86400.0];
        self.wantsLayer = YES;
        self.layer.drawsAsynchronously = YES;
        self.layer.actions = @{
            @"contents": [NSNull null],
            @"onOrderIn": [NSNull null],
            @"onOrderOut": [NSNull null],
            @"sublayers": [NSNull null],
            @"bounds": [NSNull null],
            @"position": [NSNull null]
        };
        self.layer.delegate = (id)self;
        blinksInitialized = NO;
    }
    return self;
}

- (void)startAnimation
{
    [super startAnimation];

    // One-time static setup (shared across all instances in the process)
    if (!s_didSetup) {
        s_didSetup = YES;
        [self setupStaticResources];
    }

    // Per-instance: init blink states once
    if (!blinksInitialized) {
        blinksInitialized = YES;
        for (int i = 0; i < MAX_BLINKS; i++) {
            blinks[i].phase = 0;
            blinks[i].opacity = 0.0f;
            blinks[i].prevOpacity = -1.0f;
            blinks[i].timer = 1.0f + (float)i * 1.2f;
            blinks[i].cellIdx = arc4random_uniform((uint32_t)s_cellCount);
        }
    }

    // Restore layer delegate (cleared in stopAnimation to release backing store)
    self.layer.delegate = (id)self;

    // Force initial draw
    [self.layer setNeedsDisplay];

    // Start per-instance timer
    if (!cfTimer) {
        CFRunLoopTimerContext timerCtx = {0, (__bridge void *)self, NULL, NULL, NULL};
        cfTimer = CFRunLoopTimerCreate(kCFAllocatorDefault,
                                       CFAbsoluteTimeGetCurrent() + 0.5,
                                       0.5, 0, 0,
                                       timerCallback, &timerCtx);
        CFRunLoopAddTimer(CFRunLoopGetCurrent(), cfTimer, kCFRunLoopCommonModes);
    }
}

- (void)setupStaticResources
{
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    if (w <= 0 || h <= 0) return;

    s_imgW = (int)w;
    s_imgH = (int)h;
    s_bytesPerRow = (size_t)s_imgW * 4;
    s_bufferSize = s_bytesPerRow * (size_t)s_imgH;

    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *path = [bundle pathForResource:@"shft_logo" ofType:@"png"];
    CGImageRef logo = NULL;
    if (path) {
        CGDataProviderRef provider = CGDataProviderCreateWithFilename([path UTF8String]);
        if (provider) {
            logo = CGImageCreateWithPNGDataProvider(provider, NULL, true, kCGRenderingIntentDefault);
            CGDataProviderRelease(provider);
        }
    }

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    uint32_t bitmapInfo = kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host;

    // Allocate background buffer via mmap
    s_bgPixels = mmap(NULL, s_bufferSize, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);

    // Draw background into bgPixels
    CGContextRef tmpCtx = CGBitmapContextCreate(s_bgPixels, s_imgW, s_imgH, 8, s_bytesPerRow, cs, bitmapInfo);
    CGContextSetRGBFillColor(tmpCtx, 0, 0, 0, 1);
    CGContextFillRect(tmpCtx, CGRectMake(0, 0, s_imgW, s_imgH));

    CGFloat logoDisplayWidth = w * 0.12;
    CGFloat aspect = logo ? (CGFloat)CGImageGetHeight(logo) / (CGFloat)CGImageGetWidth(logo) : 1.0;
    CGFloat cellH = logoDisplayWidth * aspect;
    CGFloat cellW = logoDisplayWidth;
    CGFloat spacingX = cellW * 1.5;
    CGFloat spacingY = cellH * 1.5;
    int gridCols = (int)(w / spacingX) + 1;
    int gridRows = (int)(h / spacingY) + 1;
    CGFloat totalGridW = (gridCols - 1) * spacingX;
    CGFloat totalGridH = (gridRows - 1) * spacingY;
    CGFloat offsetX = (w - totalGridW) / 2.0;
    CGFloat offsetY = (h - totalGridH) / 2.0;

    s_cellCount = gridCols * gridRows;
    s_cellInfos = (CellInfo *)calloc(s_cellCount, sizeof(CellInfo));

    if (logo) {
        for (int row = 0; row < gridRows; row++) {
            for (int col = 0; col < gridCols; col++) {
                CGFloat cx = offsetX + col * spacingX;
                CGFloat cy = offsetY + row * spacingY;
                CGRect r = CGRectMake(cx - cellW/2, cy - cellH/2, cellW, cellH);
                CGContextSaveGState(tmpCtx);
                CGContextSetAlpha(tmpCtx, 0.85);
                CGContextDrawImage(tmpCtx, r, logo);
                CGContextRestoreGState(tmpCtx);

                int idx = row * gridCols + col;
                CGFloat x = cx - cellW/2;
                CGFloat y = cy - cellH/2;
                s_cellInfos[idx].frame = CGRectMake(
                    x + SQ_REL_X * cellW,
                    y + (1.0 - SQ_REL_Y_TOP - SQ_REL_H) * cellH,
                    SQ_REL_W * cellW,
                    SQ_REL_H * cellH
                );
            }
        }
    }
    if (logo) CGImageRelease(logo);

    // Create persistent background CGImage from the rendered pixels
    s_bgImage = CGBitmapContextCreateImage(tmpCtx);
    CGContextRelease(tmpCtx);

    // bgPixels buffer stays allocated (mmap) - we still need it? No, bgImage has its own copy.
    // Free the mmap buffer since CGBitmapContextCreateImage made a copy
    munmap(s_bgPixels, s_bufferSize);
    s_bgPixels = NULL;

    CGColorSpaceRelease(cs);
}

// Core Animation calls this to draw our layer's content.
// CA manages its own backing store - we just draw into the provided context.
// NO CGImage creation, NO texture churn, ZERO allocation per frame.
- (void)drawLayer:(CALayer *)layer inContext:(CGContextRef)ctx
{
    if (!s_bgImage) return;

    CGRect bounds = CGRectMake(0, 0, s_imgW, s_imgH);

    // Draw background (pre-rendered, immutable)
    CGContextDrawImage(ctx, bounds, s_bgImage);

    // Draw active blink overlays
    for (int i = 0; i < MAX_BLINKS; i++) {
        if (blinks[i].opacity > 0.01f) {
            CGContextSaveGState(ctx);
            CGContextSetAlpha(ctx, blinks[i].opacity);
            CGContextSetRGBFillColor(ctx, SHFT_GREEN_R, SHFT_GREEN_G, SHFT_GREEN_B, 1.0);
            CGContextFillRect(ctx, s_cellInfos[blinks[i].cellIdx].frame);
            CGContextRestoreGState(ctx);
        }
    }
}

- (void)tick
{
    float dt = 0.5f;
    BOOL needsRedraw = NO;

    for (int i = 0; i < MAX_BLINKS; i++) {
        blinks[i].timer -= dt;

        if (blinks[i].phase == 0) {
            if (blinks[i].timer <= 0) {
                blinks[i].cellIdx = arc4random_uniform((uint32_t)s_cellCount);
                blinks[i].fadeInTime = 0.5f + (float)(arc4random_uniform(500)) / 1000.0f;
                blinks[i].fadeOutTime = 1.0f + (float)(arc4random_uniform(1000)) / 1000.0f;
                blinks[i].phase = 1;
                blinks[i].timer = blinks[i].fadeInTime;
            }
        } else if (blinks[i].phase == 1) {
            float progress = 1.0f - (blinks[i].timer / blinks[i].fadeInTime);
            if (progress > 1.0f) progress = 1.0f;
            blinks[i].opacity = progress * progress;
            if (blinks[i].timer <= 0) {
                blinks[i].phase = 2;
                blinks[i].timer = blinks[i].fadeOutTime;
                blinks[i].opacity = 1.0f;
            }
        } else {
            float progress = 1.0f - (blinks[i].timer / blinks[i].fadeOutTime);
            if (progress > 1.0f) progress = 1.0f;
            blinks[i].opacity = 1.0f - progress * progress;
            if (blinks[i].timer <= 0) {
                blinks[i].phase = 0;
                blinks[i].timer = 3.0f + (float)(arc4random_uniform(5000)) / 1000.0f;
                blinks[i].opacity = 0.0f;
            }
        }

        float delta = blinks[i].opacity - blinks[i].prevOpacity;
        if (delta < 0) delta = -delta;
        if (delta > 0.02f) {
            needsRedraw = YES;
            blinks[i].prevOpacity = blinks[i].opacity;
        }
    }

    if (!needsRedraw) return;

    // Ask CA to redraw - it calls drawLayer:inContext: on its managed backing store
    [self.layer setNeedsDisplay];
}

- (void)animateOneFrame { }
- (void)drawRect:(NSRect)rect { }

- (void)stopAnimation
{
    [super stopAnimation];
    if (cfTimer) {
        CFRunLoopTimerInvalidate(cfTimer);
        CFRelease(cfTimer);
        cfTimer = NULL;
    }
    // Release this view's layer backing store so old instances don't hold ~17MB each.
    // Static resources (s_bgImage, s_cellInfos) are unaffected.
    self.layer.delegate = nil;
    self.layer.contents = nil;
}

- (BOOL)hasConfigureSheet { return NO; }
- (NSWindow *)configureSheet { return nil; }

- (void)dealloc
{
    if (cfTimer) {
        CFRunLoopTimerInvalidate(cfTimer);
        CFRelease(cfTimer);
        cfTimer = NULL;
    }
    // Static resources are NOT freed here - they persist for reuse by new instances.
    // They live for the lifetime of the legacyScreenSaver process.
}

@end
