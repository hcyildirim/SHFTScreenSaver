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
        AVPlayerItem *templateItem = [AVPlayerItem playerItemWithURL:url];
        queuePlayer = [AVQueuePlayer queuePlayerWithItems:@[templateItem]];
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
    [super stopAnimation];
    [queuePlayer pause];
}

- (void)animateOneFrame { }
- (void)drawRect:(NSRect)rect { }

- (BOOL)hasConfigureSheet { return NO; }
- (NSWindow *)configureSheet { return nil; }

- (void)dealloc
{
    [queuePlayer pause];
    [playerLayer removeFromSuperlayer];
}

@end
