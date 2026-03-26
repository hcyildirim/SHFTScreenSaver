#import <ScreenSaver/ScreenSaver.h>
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

#define MAX_BLINKS 6

typedef struct {
    CGRect frame;
} CellInfo;

typedef struct {
    int cellIdx;
    float opacity;
    float phase;        // 0=waiting, 1=fading in, 2=fading out
    float timer;
    float fadeInTime;
    float fadeOutTime;
} BlinkState;

@interface SHFTScreenSaverView : ScreenSaverView
{
    BOOL didSetup;
    CGImageRef bgImageRef;
    CellInfo *cellInfos;
    int cellCount;
    CALayer *blinkLayers[MAX_BLINKS];
    BlinkState blinks[MAX_BLINKS];
    CFRunLoopTimerRef cfTimer;
}
- (void)tick;
@end

// C callback - no ObjC dispatch overhead
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
        didSetup = NO;
    }
    return self;
}

- (void)startAnimation
{
    [super startAnimation];
    if (!didSetup) {
        didSetup = YES;
        [self setupEverything];
    }
}

- (void)setupEverything
{
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    if (w <= 0 || h <= 0) return;

    int iw = (int)w;
    int ih = (int)h;

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
    CGContextRef ctx = CGBitmapContextCreate(NULL, iw, ih, 8, iw * 4, cs,
                                              kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
    CGColorSpaceRelease(cs);

    CGContextSetRGBFillColor(ctx, 0, 0, 0, 1);
    CGContextFillRect(ctx, CGRectMake(0, 0, iw, ih));

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

    cellCount = gridCols * gridRows;
    cellInfos = (CellInfo *)calloc(cellCount, sizeof(CellInfo));

    if (logo) {
        for (int row = 0; row < gridRows; row++) {
            for (int col = 0; col < gridCols; col++) {
                CGFloat cx = offsetX + col * spacingX;
                CGFloat cy = offsetY + row * spacingY;
                CGRect r = CGRectMake(cx - cellW/2, cy - cellH/2, cellW, cellH);
                CGContextSaveGState(ctx);
                CGContextSetAlpha(ctx, 0.85);
                CGContextDrawImage(ctx, r, logo);
                CGContextRestoreGState(ctx);

                int idx = row * gridCols + col;
                CGFloat x = cx - cellW/2;
                CGFloat y = cy - cellH/2;
                cellInfos[idx].frame = CGRectMake(
                    x + SQ_REL_X * cellW,
                    y + (1.0 - SQ_REL_Y_TOP - SQ_REL_H) * cellH,
                    SQ_REL_W * cellW,
                    SQ_REL_H * cellH
                );
            }
        }
    }

    CGImageRef bgImage = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    if (logo) CGImageRelease(logo);

    bgImageRef = bgImage;
    self.layer.contents = (__bridge id)bgImageRef;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    CGColorRef greenColor = CGColorCreateGenericRGB(SHFT_GREEN_R, SHFT_GREEN_G, SHFT_GREEN_B, 1.0);
    NSDictionary *noActions = @{
        @"opacity": [NSNull null],
        @"position": [NSNull null],
        @"bounds": [NSNull null],
        @"frame": [NSNull null]
    };

    for (int i = 0; i < MAX_BLINKS; i++) {
        blinkLayers[i] = [CALayer layer];
        blinkLayers[i].backgroundColor = greenColor;
        blinkLayers[i].opacity = 0.0f;
        blinkLayers[i].frame = CGRectMake(0, 0, 1, 1);
        blinkLayers[i].actions = noActions;
        [self.layer addSublayer:blinkLayers[i]];

        blinks[i].phase = 0;
        blinks[i].opacity = 0.0f;
        blinks[i].timer = 1.0f + (float)i * 1.2f;
        blinks[i].cellIdx = arc4random_uniform((uint32_t)cellCount);
    }

    CGColorRelease(greenColor);
    [CATransaction commit];

    // CFRunLoopTimer - pure C timer, zero ObjC overhead per fire
    CFRunLoopTimerContext timerCtx = {0, (__bridge void *)self, NULL, NULL, NULL};
    cfTimer = CFRunLoopTimerCreate(kCFAllocatorDefault,
                                   CFAbsoluteTimeGetCurrent() + 0.2,
                                   0.2,  // 5 fps
                                   0, 0,
                                   timerCallback,
                                   &timerCtx);
    CFRunLoopAddTimer(CFRunLoopGetCurrent(), cfTimer, kCFRunLoopCommonModes);
}

- (void)tick
{
    @autoreleasepool {
        // Purge recovery
        if (bgImageRef && !self.layer.contents) {
            self.layer.contents = (__bridge id)bgImageRef;
        }

        float dt = 0.2f;

        for (int i = 0; i < MAX_BLINKS; i++) {
            blinks[i].timer -= dt;

            if (blinks[i].phase == 0) {
                if (blinks[i].timer <= 0) {
                    blinks[i].cellIdx = arc4random_uniform((uint32_t)cellCount);
                    blinks[i].fadeInTime = 0.3f + (float)(arc4random_uniform(200)) / 1000.0f;
                    blinks[i].fadeOutTime = 0.5f + (float)(arc4random_uniform(400)) / 1000.0f;
                    blinks[i].phase = 1;
                    blinks[i].timer = blinks[i].fadeInTime;
                    blinkLayers[i].frame = cellInfos[blinks[i].cellIdx].frame;
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
                    blinks[i].timer = 2.0f + (float)(arc4random_uniform(4000)) / 1000.0f;
                    blinks[i].opacity = 0.0f;
                }
            }

            blinkLayers[i].opacity = blinks[i].opacity;
        }
    } // @autoreleasepool drains ALL hidden CA internal objects immediately
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
    if (cellInfos) { free(cellInfos); cellInfos = NULL; }
    if (bgImageRef) { CGImageRelease(bgImageRef); bgImageRef = NULL; }
}

@end
