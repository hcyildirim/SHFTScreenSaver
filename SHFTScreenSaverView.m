#import <ScreenSaver/ScreenSaver.h>
#import <AVFoundation/AVFoundation.h>

@interface SHFTScreenSaverView : ScreenSaverView
{
    AVPlayer *player;
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

    if (!player) {
        NSBundle *bundle = [NSBundle bundleForClass:[self class]];
        NSString *path = [bundle pathForResource:@"shft_screensaver" ofType:@"mov"];
        if (!path) return;

        NSURL *url = [NSURL fileURLWithPath:path];
        player = [AVPlayer playerWithURL:url];
        player.actionAtItemEnd = AVPlayerActionAtItemEndNone;

        // Seamless loop: seek to start when video ends (no gap, no new player item)
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(videoDidEnd:)
                                                     name:AVPlayerItemDidPlayToEndTimeNotification
                                                   object:player.currentItem];

        playerLayer = [AVPlayerLayer playerLayerWithPlayer:player];
        playerLayer.frame = self.bounds;
        playerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        playerLayer.backgroundColor = CGColorGetConstantColor(kCGColorBlack);
        [self.layer addSublayer:playerLayer];
    }

    [player seekToTime:kCMTimeZero];
    [player play];
}

- (void)videoDidEnd:(NSNotification *)notification
{
    [player seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
}

- (void)stopAnimation
{
    [player pause];
    [super stopAnimation];
}

- (void)animateOneFrame { }
- (void)drawRect:(NSRect)rect { }

- (BOOL)hasConfigureSheet { return NO; }
- (NSWindow *)configureSheet { return nil; }

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
