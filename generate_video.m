#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreVideo/CoreVideo.h>

#define VIDEO_W 1280
#define VIDEO_H 800
#define FPS 30
#define DURATION_SECS 60
#define TOTAL_FRAMES (FPS * DURATION_SECS)
#define MAX_BLINKS 6

#define SHFT_GREEN_R (200.0f/255.0f)
#define SHFT_GREEN_G (216.0f/255.0f)
#define SHFT_GREEN_B (60.0f/255.0f)

#define SQ_REL_X      (642.0f / 800.0f)
#define SQ_REL_Y_TOP  (324.0f / 800.0f)
#define SQ_REL_W      (70.0f / 800.0f)
#define SQ_REL_H      (70.0f / 800.0f)

typedef struct { CGRect frame; } CellInfo;

typedef struct {
    int cellIdx;
    float opacity;
    int phase;
    float timer;
    float fadeInTime;
    float fadeOutTime;
} BlinkState;

// Deterministic PRNG (fixed seed = reproducible video)
static unsigned int rng_state = 42;
static unsigned int det_rand(void) {
    rng_state = rng_state * 1103515245 + 12345;
    return (rng_state >> 16) & 0x7FFF;
}
static unsigned int det_rand_range(unsigned int maxVal) {
    return det_rand() % maxVal;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *projectDir = [[NSString stringWithUTF8String:argv[0]] stringByDeletingLastPathComponent];
        if ([projectDir length] == 0) projectDir = [[NSFileManager defaultManager] currentDirectoryPath];
        NSString *logoPath = [projectDir stringByAppendingPathComponent:@"shft_logo.png"];

        // Load logo
        CGDataProviderRef logoProvider = CGDataProviderCreateWithFilename([logoPath UTF8String]);
        if (!logoProvider) {
            // Try current directory
            logoPath = [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:@"shft_logo.png"];
            logoProvider = CGDataProviderCreateWithFilename([logoPath UTF8String]);
        }
        if (!logoProvider) {
            fprintf(stderr, "ERROR: Cannot find shft_logo.png\n");
            return 1;
        }
        CGImageRef logo = CGImageCreateWithPNGDataProvider(logoProvider, NULL, true, kCGRenderingIntentDefault);
        CGDataProviderRelease(logoProvider);
        if (!logo) {
            fprintf(stderr, "ERROR: Cannot decode shft_logo.png\n");
            return 1;
        }

        // Calculate grid layout (same as screen saver)
        CGFloat w = VIDEO_W;
        CGFloat h = VIDEO_H;
        CGFloat logoDisplayWidth = w * 0.12;
        CGFloat aspect = (CGFloat)CGImageGetHeight(logo) / (CGFloat)CGImageGetWidth(logo);
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

        int cellCount = gridCols * gridRows;
        CellInfo *cells = calloc(cellCount, sizeof(CellInfo));

        // Pre-render background (black + SHFT logos)
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        uint32_t bitmapInfo = kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host;
        size_t bytesPerRow = VIDEO_W * 4;
        size_t bufSize = bytesPerRow * VIDEO_H;
        void *bgPixels = malloc(bufSize);

        CGContextRef bgCtx = CGBitmapContextCreate(bgPixels, VIDEO_W, VIDEO_H, 8, bytesPerRow, cs, bitmapInfo);
        CGContextSetRGBFillColor(bgCtx, 0, 0, 0, 1);
        CGContextFillRect(bgCtx, CGRectMake(0, 0, w, h));

        for (int row = 0; row < gridRows; row++) {
            for (int col = 0; col < gridCols; col++) {
                CGFloat cx = offsetX + col * spacingX;
                CGFloat cy = offsetY + row * spacingY;
                CGRect r = CGRectMake(cx - cellW/2, cy - cellH/2, cellW, cellH);
                CGContextSaveGState(bgCtx);
                CGContextSetAlpha(bgCtx, 0.85);
                CGContextDrawImage(bgCtx, r, logo);
                CGContextRestoreGState(bgCtx);

                int idx = row * gridCols + col;
                CGFloat x = cx - cellW/2;
                CGFloat y = cy - cellH/2;
                cells[idx].frame = CGRectMake(
                    x + SQ_REL_X * cellW,
                    y + (1.0 - SQ_REL_Y_TOP - SQ_REL_H) * cellH,
                    SQ_REL_W * cellW,
                    SQ_REL_H * cellH
                );
            }
        }
        CGImageRelease(logo);
        CGContextRelease(bgCtx);

        // Initialize blink states
        BlinkState blinks[MAX_BLINKS];
        for (int i = 0; i < MAX_BLINKS; i++) {
            blinks[i].phase = 0;
            blinks[i].opacity = 0.0f;
            blinks[i].timer = 1.0f + (float)i * 1.2f;
            blinks[i].cellIdx = det_rand_range(cellCount);
            blinks[i].fadeInTime = 0;
            blinks[i].fadeOutTime = 0;
        }

        // Setup AVAssetWriter
        NSString *outPath = [[[NSFileManager defaultManager] currentDirectoryPath] stringByAppendingPathComponent:@"build/shft_screensaver.mov"];
        [[NSFileManager defaultManager] removeItemAtPath:outPath error:nil];

        NSError *error = nil;
        NSURL *outURL = [NSURL fileURLWithPath:outPath];
        AVAssetWriter *writer = [[AVAssetWriter alloc] initWithURL:outURL fileType:AVFileTypeQuickTimeMovie error:&error];
        if (error) {
            fprintf(stderr, "ERROR: Cannot create writer: %s\n", [[error description] UTF8String]);
            return 1;
        }

        NSDictionary *videoSettings = @{
            AVVideoCodecKey: AVVideoCodecTypeH264,
            AVVideoWidthKey: @(VIDEO_W),
            AVVideoHeightKey: @(VIDEO_H),
            AVVideoCompressionPropertiesKey: @{
                AVVideoAverageBitRateKey: @(8000000),
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: @(TOTAL_FRAMES),
                AVVideoMaxKeyFrameIntervalDurationKey: @(DURATION_SECS),
            }
        };

        AVAssetWriterInput *writerInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoSettings];
        writerInput.expectsMediaDataInRealTime = NO;

        NSDictionary *pbAttrs = @{
            (NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
            (NSString *)kCVPixelBufferWidthKey: @(VIDEO_W),
            (NSString *)kCVPixelBufferHeightKey: @(VIDEO_H),
        };
        AVAssetWriterInputPixelBufferAdaptor *adaptor =
            [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:writerInput
                                                                             sourcePixelBufferAttributes:pbAttrs];

        [writer addInput:writerInput];
        [writer startWriting];
        [writer startSessionAtSourceTime:kCMTimeZero];

        float dt = 1.0f / (float)FPS;

        for (int frame = 0; frame < TOTAL_FRAMES; frame++) {
            @autoreleasepool {
                float t = (float)frame * dt;

                // Update blink states
                for (int i = 0; i < MAX_BLINKS; i++) {
                    blinks[i].timer -= dt;

                    if (blinks[i].phase == 0) {
                        if (blinks[i].timer <= 0) {
                            blinks[i].cellIdx = det_rand_range(cellCount);
                            blinks[i].fadeInTime = 0.5f + (float)(det_rand_range(500)) / 1000.0f;
                            blinks[i].fadeOutTime = 1.0f + (float)(det_rand_range(1000)) / 1000.0f;
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
                            blinks[i].timer = 3.0f + (float)(det_rand_range(5000)) / 1000.0f;
                            blinks[i].opacity = 0.0f;
                        }
                    }
                }

                // No fade at loop boundaries - blinks are subtle enough that
                // a hard cut is invisible. Avoids visible dimming every loop.

                // Get pixel buffer from pool
                CVPixelBufferRef pixelBuffer = NULL;
                CVReturn status = CVPixelBufferPoolCreatePixelBuffer(NULL, adaptor.pixelBufferPool, &pixelBuffer);
                if (status != kCVReturnSuccess) {
                    fprintf(stderr, "ERROR: Failed to create pixel buffer at frame %d\n", frame);
                    continue;
                }

                CVPixelBufferLockBaseAddress(pixelBuffer, 0);
                void *pxData = CVPixelBufferGetBaseAddress(pixelBuffer);
                size_t pxBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);

                // Copy pre-rendered background
                if (pxBytesPerRow == bytesPerRow) {
                    memcpy(pxData, bgPixels, bufSize);
                } else {
                    for (int row = 0; row < VIDEO_H; row++) {
                        memcpy((uint8_t *)pxData + row * pxBytesPerRow,
                               (uint8_t *)bgPixels + row * bytesPerRow,
                               bytesPerRow);
                    }
                }

                // Draw blink overlays
                CGContextRef ctx = CGBitmapContextCreate(pxData, VIDEO_W, VIDEO_H, 8, pxBytesPerRow, cs, bitmapInfo);
                for (int i = 0; i < MAX_BLINKS; i++) {
                    float op = blinks[i].opacity;
                    if (op > 0.01f) {
                        CGContextSaveGState(ctx);
                        CGContextSetAlpha(ctx, op);
                        CGContextSetRGBFillColor(ctx, SHFT_GREEN_R, SHFT_GREEN_G, SHFT_GREEN_B, 1.0);
                        CGContextFillRect(ctx, cells[blinks[i].cellIdx].frame);
                        CGContextRestoreGState(ctx);
                    }
                }
                CGContextRelease(ctx);

                CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);

                // Wait for writer
                while (!writerInput.isReadyForMoreMediaData) {
                    [NSThread sleepForTimeInterval:0.005];
                }

                CMTime presentTime = CMTimeMake(frame, FPS);
                [adaptor appendPixelBuffer:pixelBuffer withPresentationTime:presentTime];
                CVPixelBufferRelease(pixelBuffer);

                if (frame % 150 == 0) {
                    fprintf(stdout, "  Frame %d/%d (%.1fs)\n", frame, TOTAL_FRAMES, t);
                    fflush(stdout);
                }
            }
        }

        [writerInput markAsFinished];

        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        [writer finishWritingWithCompletionHandler:^{
            dispatch_semaphore_signal(sem);
        }];
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);

        if (writer.status == AVAssetWriterStatusCompleted) {
            NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:outPath error:nil];
            fprintf(stdout, "Video saved: %s (%.1f MB)\n", [outPath UTF8String], [attrs fileSize] / 1048576.0);
        } else {
            fprintf(stderr, "ERROR: %s\n", [[writer.error description] UTF8String]);
            free(bgPixels);
            free(cells);
            CGColorSpaceRelease(cs);
            return 1;
        }

        free(bgPixels);
        free(cells);
        CGColorSpaceRelease(cs);
    }
    return 0;
}
