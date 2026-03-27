#import <ScreenSaver/ScreenSaver.h>
#import <AVFoundation/AVFoundation.h>

@interface SHFTScreenSaverView : ScreenSaverView
{
    AVQueuePlayer *queuePlayer;
    AVPlayerLooper *looper;
    AVPlayerLayer *playerLayer;
}
@end

@implementation SHFTScreenSaverView

- (instancetype)initWithFrame:(NSRect)frame isPreview:(BOOL)isPreview
{
    self = [super initWithFrame:frame isPreview:isPreview];
    if (self) {
        [self setAnimationTimeInterval:86400.0];
        self.wantsLayer = YES;
    }
    return self;
}

- (void)startAnimation
{
    [super startAnimation];

    if (!queuePlayer) {
        NSBundle *bundle = [NSBundle bundleForClass:[self class]];
        NSString *path = [bundle pathForResource:@"shft_screensaver" ofType:@"mov"];
        if (!path) return;

        NSURL *url = [NSURL fileURLWithPath:path];
        AVAsset *asset = [AVAsset assetWithURL:url];
        AVPlayerItem *templateItem = [AVPlayerItem playerItemWithAsset:asset];

        queuePlayer = [AVQueuePlayer queuePlayerWithItems:@[]];
        queuePlayer.actionAtItemEnd = AVPlayerActionAtItemEndAdvance;

        // AVPlayerLooper handles gapless looping - pre-buffers next iteration
        looper = [AVPlayerLooper playerLooperWithPlayer:queuePlayer templateItem:templateItem];

        playerLayer = [AVPlayerLayer playerLayerWithPlayer:queuePlayer];
        playerLayer.frame = self.bounds;
        playerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        playerLayer.backgroundColor = CGColorGetConstantColor(kCGColorBlack);
        [self.layer addSublayer:playerLayer];
    }

    [queuePlayer play];
}

- (void)stopAnimation
{
    [queuePlayer pause];
    [super stopAnimation];
}

- (void)animateOneFrame { }
- (void)drawRect:(NSRect)rect { }

- (BOOL)hasConfigureSheet { return NO; }
- (NSWindow *)configureSheet { return nil; }

@end
