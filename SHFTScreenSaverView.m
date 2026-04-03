#import <ScreenSaver/ScreenSaver.h>
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>

#define MAX_BLINKS 6
#define MAX_RSS_BYTES (80 * 1024 * 1024)  // 80 MB — kill process above this

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

// Shared resources — single copy in process, never duplicated.
// Memory growth per cycle is ~15MB from legacyScreenSaver's own NSView
// allocation (confirmed with empty view test). Our code adds zero overhead.
static CGImageRef s_bgImage = NULL;
static CellInfo *s_cellInfos = NULL;
static int s_cellCount = 0;
static int s_imgW = 0;
static int s_imgH = 0;
static CGColorRef s_blinkColor = NULL;
static BOOL s_setupDone = NO;

@interface SHFTScreenSaverView : ScreenSaverView
{
    BlinkState blinks[MAX_BLINKS];
    CFRunLoopTimerRef cfTimer;
    CALayer *blinkLayers[MAX_BLINKS];
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
        self.layer.actions = @{
            @"contents": [NSNull null],
            @"onOrderIn": [NSNull null],
            @"onOrderOut": [NSNull null],
            @"sublayers": [NSNull null],
            @"bounds": [NSNull null],
            @"position": [NSNull null]
        };
    }
    return self;
}

- (void)startAnimation
{
    [super startAnimation];

    // Self-monitoring: kill process if RSS exceeds threshold.
    // legacyScreenSaver leaks ~15MB per cycle (Apple bug).
    // _exit(0) kills the entire process; system restarts fresh on next activation.
    {
        struct mach_task_basic_info info;
        mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
        if (task_info(mach_task_self(), MACH_TASK_BASIC_INFO,
                      (task_info_t)&info, &count) == KERN_SUCCESS) {
            if (info.resident_size > MAX_RSS_BYTES) {
                _exit(0);
            }
        }
    }

    if (!s_setupDone) {
        s_setupDone = YES;
        [self setupSharedResources];
    }

    // Set background — just a CGImage reference, no backing store allocated.
    self.layer.contents = (__bridge id)s_bgImage;
    self.layer.contentsGravity = kCAGravityResize;

    // Create blink sublayers (reused across start/stop cycles)
    for (int i = 0; i < MAX_BLINKS; i++) {
        if (!blinkLayers[i]) {
            blinkLayers[i] = [CALayer layer];
            blinkLayers[i].backgroundColor = s_blinkColor;
            blinkLayers[i].opacity = 0;
            blinkLayers[i].actions = @{
                @"opacity": [NSNull null],
                @"position": [NSNull null],
                @"bounds": [NSNull null]
            };
        }
        if (blinkLayers[i].superlayer != self.layer) {
            [self.layer addSublayer:blinkLayers[i]];
        }
    }

    // Initialize blink states
    for (int i = 0; i < MAX_BLINKS; i++) {
        blinks[i].phase = 0;
        blinks[i].opacity = 0.0f;
        blinks[i].prevOpacity = -1.0f;
        blinks[i].timer = 1.0f + (float)i * 1.2f;
        blinks[i].cellIdx = arc4random_uniform((uint32_t)s_cellCount);
        blinkLayers[i].frame = s_cellInfos[blinks[i].cellIdx].frame;
        blinkLayers[i].opacity = 0;
    }

    if (!cfTimer) {
        CFRunLoopTimerContext timerCtx = {0, (__bridge void *)self, NULL, NULL, NULL};
        cfTimer = CFRunLoopTimerCreate(kCFAllocatorDefault,
                                       CFAbsoluteTimeGetCurrent() + 0.5,
                                       0.5, 0, 0,
                                       timerCallback, &timerCtx);
        CFRunLoopAddTimer(CFRunLoopGetCurrent(), cfTimer, kCFRunLoopCommonModes);
    }
}

- (void)setupSharedResources
{
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    if (w <= 0 || h <= 0) return;

    s_imgW = (int)w;
    s_imgH = (int)h;
    size_t bytesPerRow = (size_t)s_imgW * 4;
    size_t bufferSize = bytesPerRow * (size_t)s_imgH;

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

    void *pixels = malloc(bufferSize);
    CGContextRef tmpCtx = CGBitmapContextCreate(pixels, s_imgW, s_imgH, 8, bytesPerRow, cs, bitmapInfo);
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

    s_bgImage = CGBitmapContextCreateImage(tmpCtx);
    CGContextRelease(tmpCtx);
    free(pixels);
    CGColorSpaceRelease(cs);

    if (!s_blinkColor) {
        s_blinkColor = CGColorCreateGenericRGB(SHFT_GREEN_R, SHFT_GREEN_G, SHFT_GREEN_B, 1.0);
    }
}

- (void)tick
{
    float dt = 0.5f;

    for (int i = 0; i < MAX_BLINKS; i++) {
        blinks[i].timer -= dt;

        if (blinks[i].phase == 0) {
            if (blinks[i].timer <= 0) {
                blinks[i].cellIdx = arc4random_uniform((uint32_t)s_cellCount);
                blinks[i].fadeInTime = 0.5f + (float)(arc4random_uniform(500)) / 1000.0f;
                blinks[i].fadeOutTime = 1.0f + (float)(arc4random_uniform(1000)) / 1000.0f;
                blinks[i].phase = 1;
                blinks[i].timer = blinks[i].fadeInTime;
                blinkLayers[i].frame = s_cellInfos[blinks[i].cellIdx].frame;
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
            blinkLayers[i].opacity = blinks[i].opacity;
            blinks[i].prevOpacity = blinks[i].opacity;
        }
    }
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
    // Hide sublayers — reused on next startAnimation, no reallocation.
    for (int i = 0; i < MAX_BLINKS; i++) {
        blinkLayers[i].opacity = 0;
    }
    // layer.contents (shared CGImage ref) stays visible during rapid cycling.
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
    for (int i = 0; i < MAX_BLINKS; i++) {
        [blinkLayers[i] removeFromSuperlayer];
        blinkLayers[i] = nil;
    }
}

@end
