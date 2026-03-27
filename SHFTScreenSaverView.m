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
    float prevOpacity;
    float phase;
    float timer;
    float fadeInTime;
    float fadeOutTime;
} BlinkState;

@interface SHFTScreenSaverView : ScreenSaverView
{
    CGImageRef bgImage;
    CellInfo *cellInfos;
    int cellCount;
    int imgW;
    int imgH;
    BlinkState blinks[MAX_BLINKS];
    CFRunLoopTimerRef cfTimer;
    BOOL didSetup;
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
        self.layer.delegate = (id)self;
        self.layer.actions = @{
            @"contents": [NSNull null],
            @"onOrderIn": [NSNull null],
            @"onOrderOut": [NSNull null],
            @"sublayers": [NSNull null],
            @"bounds": [NSNull null],
            @"position": [NSNull null]
        };
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

    self.layer.delegate = (id)self;
    [self.layer setNeedsDisplay];

    if (!cfTimer) {
        CFRunLoopTimerContext timerCtx = {0, (__bridge void *)self, NULL, NULL, NULL};
        cfTimer = CFRunLoopTimerCreate(kCFAllocatorDefault,
                                       CFAbsoluteTimeGetCurrent() + 0.5,
                                       0.5, 0, 0,
                                       timerCallback, &timerCtx);
        CFRunLoopAddTimer(CFRunLoopGetCurrent(), cfTimer, kCFRunLoopCommonModes);
    }
}

- (void)setupEverything
{
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    if (w <= 0 || h <= 0) return;

    imgW = (int)w;
    imgH = (int)h;
    size_t bytesPerRow = (size_t)imgW * 4;
    size_t bufferSize = bytesPerRow * (size_t)imgH;

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
    CGContextRef tmpCtx = CGBitmapContextCreate(pixels, imgW, imgH, 8, bytesPerRow, cs, bitmapInfo);
    CGContextSetRGBFillColor(tmpCtx, 0, 0, 0, 1);
    CGContextFillRect(tmpCtx, CGRectMake(0, 0, imgW, imgH));

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
                CGContextSaveGState(tmpCtx);
                CGContextSetAlpha(tmpCtx, 0.85);
                CGContextDrawImage(tmpCtx, r, logo);
                CGContextRestoreGState(tmpCtx);

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
    if (logo) CGImageRelease(logo);

    bgImage = CGBitmapContextCreateImage(tmpCtx);
    CGContextRelease(tmpCtx);
    free(pixels);
    CGColorSpaceRelease(cs);

    for (int i = 0; i < MAX_BLINKS; i++) {
        blinks[i].phase = 0;
        blinks[i].opacity = 0.0f;
        blinks[i].prevOpacity = -1.0f;
        blinks[i].timer = 1.0f + (float)i * 1.2f;
        blinks[i].cellIdx = arc4random_uniform((uint32_t)cellCount);
    }
}

- (void)drawLayer:(CALayer *)layer inContext:(CGContextRef)ctx
{
    if (!bgImage) return;

    CGRect bounds = CGRectMake(0, 0, imgW, imgH);
    CGContextDrawImage(ctx, bounds, bgImage);

    for (int i = 0; i < MAX_BLINKS; i++) {
        if (blinks[i].opacity > 0.01f) {
            CGContextSaveGState(ctx);
            CGContextSetAlpha(ctx, blinks[i].opacity);
            CGContextSetRGBFillColor(ctx, SHFT_GREEN_R, SHFT_GREEN_G, SHFT_GREEN_B, 1.0);
            CGContextFillRect(ctx, cellInfos[blinks[i].cellIdx].frame);
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
                blinks[i].cellIdx = arc4random_uniform((uint32_t)cellCount);
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
    // Layer contents and delegate are NOT cleared here.
    // Keeps last frame visible if system cycles stop→start rapidly.
    // LaunchAgent kills the entire process when screensaver is truly dismissed.
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
    if (bgImage) { CGImageRelease(bgImage); bgImage = NULL; }
    if (cellInfos) { free(cellInfos); cellInfos = NULL; }
}

@end
