#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

#define kLogPath @"/var/mobile/Documents/lyricbubble.log"
#define kNP      @"/var/mobile/Documents/np.js"
#define kLrcA    @"/var/jb/Library/Application Support/MowangDaFeiYuPet/l.plist"
#define kLrcB    @"/var/jb/Library/Application Support/MowangDaFeiYuPet/lyrics.plist"
#define kLrcC    @"/var/mobile/Library/Caches/dafeiyu_lyrics.plist"

// 可调参数
#define kBubbleYRatio   0.70   // 气泡垂直位置（屏高比例）
#define kSideMargin     24.0   // 左右边距
#define kBubbleHeight   52.0
#define kCornerRadius   16.0
#define kFontSize       17.0
#define kRefresh        0.5

static UIWindow *gWin;
static UIView  *gBubble;
static UILabel *gLabel;
static BOOL     gShown = NO;

static void LBLog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSString *line = [NSString stringWithFormat:@"[bubble] %@\n", msg];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:kLogPath]) [fm createFileAtPath:kLogPath contents:nil attributes:nil];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:kLogPath];
    if (!fh) return;
    @try { [fh seekToEndOfFile]; [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; } @catch (NSException *e) {}
    [fh closeFile];
}

static NSDictionary *ReadJSON(NSString *path) {
    NSData *d = [NSData dataWithContentsOfFile:path];
    if (!d || d.length < 2) return nil;
    id obj = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
    return [obj isKindOfClass:[NSDictionary class]] ? obj : nil;
}

static NSDictionary *ReadPlist(NSString *path) {
    NSData *d = [NSData dataWithContentsOfFile:path];
    if (!d || d.length < 8) return nil;
    id obj = [NSPropertyListSerialization propertyListWithData:d options:NSPropertyListImmutable format:nil error:nil];
    return [obj isKindOfClass:[NSDictionary class]] ? obj : nil;
}

static NSString *CurrentLine(NSString *lrc, double elapsed) {
    if (![lrc isKindOfClass:[NSString class]] || !lrc.length) return nil;
    double best = -1;
    __block NSString *text = nil;
    for (NSString *raw in [lrc componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (line.length < 6 || ![line hasPrefix:@"["]) continue;
        NSRange rb = [line rangeOfString:@"]"];
        if (rb.location == NSNotFound) continue;
        NSString *stamp = [line substringWithRange:NSMakeRange(1, rb.location - 1)];
        NSArray *parts = [stamp componentsSeparatedByString:@":"];
        if (parts.count < 2) continue;
        double t = [parts[0] doubleValue] * 60.0 + [parts[1] doubleValue];
        if (t <= elapsed + 0.6 && t > best) {
            best = t;
            NSString *body = [[line substringFromIndex:rb.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (body.length) text = body;
        }
    }
    return text;
}

static NSAttributedString *Rainbow(NSString *text) {
    NSMutableAttributedString *s = [[NSMutableAttributedString alloc] initWithString:text];
    NSUInteger n = s.length;
    NSArray<UIColor *> *colors = @[
        [UIColor colorWithHue:0.02 saturation:0.90 brightness:1.0 alpha:1.0],
        [UIColor colorWithHue:0.08 saturation:0.90 brightness:1.0 alpha:1.0],
        [UIColor colorWithHue:0.15 saturation:0.90 brightness:1.0 alpha:1.0],
        [UIColor colorWithHue:0.25 saturation:0.90 brightness:1.0 alpha:1.0],
        [UIColor colorWithHue:0.35 saturation:0.90 brightness:1.0 alpha:1.0],
        [UIColor colorWithHue:0.47 saturation:0.90 brightness:1.0 alpha:1.0],
        [UIColor colorWithHue:0.58 saturation:0.90 brightness:1.0 alpha:1.0],
        [UIColor colorWithHue:0.72 saturation:0.90 brightness:1.0 alpha:1.0],
        [UIColor colorWithHue:0.85 saturation:0.90 brightness:1.0 alpha:1.0],
    ];
    for (NSUInteger i = 0; i < n; i++)
        [s addAttribute:NSForegroundColorAttributeName value:colors[i % colors.count] range:NSMakeRange(i, 1)];
    return s;
}

static void SetShown(BOOL show) {
    if (!gBubble || gShown == show) return;
    gShown = show;
    [gBubble setHidden:!show];
}

static void Tick(void) {
    NSDictionary *np = ReadJSON(kNP);
    if (!np) { SetShown(NO); return; }
    if ([np[@"playing"] doubleValue] < 0.5) { SetShown(NO); return; }
    double elapsed = [np[@"elapsed"] doubleValue];

    NSDictionary *pl = ReadPlist(kLrcA) ?: ReadPlist(kLrcB) ?: ReadPlist(kLrcC);
    NSString *line = CurrentLine(pl[@"lrc"], elapsed);
    if (!line.length) {
        NSString *l2 = np[@"lyricLine"];
        if ([l2 isKindOfClass:[NSString class]] && l2.length) line = l2;
    }
    if (!line.length) { SetShown(NO); return; }
    if (!gShown) LBLog(@"line: %@ (elapsed %.2f)", line, elapsed);
    gLabel.attributedText = Rainbow(line);
    SetShown(YES);
}

static void Setup(void) {
    UIWindow *win = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
            if ([sc isKindOfClass:[UIWindowScene class]] && sc.activationState != UISceneActivationStateUnattached) {
                win = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)sc];
                break;
            }
        }
    }
    if (!win) win = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    win.windowLevel = UIWindowLevelAlert + 1;
    win.userInteractionEnabled = NO;
    win.hidden = NO;
    win.rootViewController = [UIViewController new];
    gWin = win;

    CGRect b = [UIScreen mainScreen].bounds;
    CGFloat bw = b.size.width - kSideMargin * 2, bh = kBubbleHeight;
    UIView *bubble = [[UIView alloc] initWithFrame:CGRectMake(kSideMargin, b.size.height * kBubbleYRatio, bw, bh)];
    bubble.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.62];
    bubble.layer.cornerRadius = kCornerRadius;
    bubble.clipsToBounds = YES;
    bubble.userInteractionEnabled = NO;

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectInset(bubble.bounds, 14, 8)];
    label.numberOfLines = 1;
    label.textAlignment = NSTextAlignmentCenter;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.7;
    label.font = [UIFont boldSystemFontOfSize:kFontSize];
    [bubble addSubview:label];
    [win.rootViewController.view addSubview:bubble];

    gBubble = bubble; gLabel = label; gShown = NO;
    [gBubble setHidden:YES];
    LBLog(@"setup ok, window=%@", win);

    [NSTimer scheduledTimerWithTimeInterval:kRefresh repeats:YES block:^(NSTimer *t) { Tick(); }];
}

%ctor {
    LBLog(@"dylib loaded");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        Setup();
    });
}
