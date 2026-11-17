#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

#define kLogPath @"/var/mobile/Documents/lyricbubble.log"
#define kNP      @"/var/mobile/Documents/np.js"
#define kLrcA    @"/var/jb/Library/Application Support/MowangDaFeiYuPet/l.plist"
#define kLrcB    @"/var/jb/Library/Application Support/MowangDaFeiYuPet/lyrics.plist"
#define kLrcC    @"/var/mobile/Library/Caches/dafeiyu_lyrics.plist"
#define kLrcD    @"/var/mobile/Documents/l.plist"
#define kLrcE    @"/var/mobile/Documents/lyrics.plist"

// 可调参数
#define kBubbleYRatio   0.70   // 气泡垂直位置（屏高比例）
#define kSideMargin     24.0   // 左右边距
#define kBubbleHeight   52.0
#define kCornerRadius   16.0
#define kFontSize       17.0
#define kRefresh        0.5

static void LBLog(NSString *fmt, ...);

static NSString *gLastDiag;
static NSDate *gLastDiagAt;

static void DiagLog(NSString *msg) {
    NSDate *now = [NSDate date];
    if (gLastDiagAt && [now timeIntervalSinceDate:gLastDiagAt] < 10 && [msg isEqualToString:gLastDiag]) return;
    gLastDiagAt = now; gLastDiag = msg;
    LBLog(@"diag: %@", msg);
}

static UIWindow *gWin;
static UIView  *gBubble;
static UIView  *gTail;
static UILabel *gLabel;
static BOOL     gShown = NO;

static void LayoutBubble(void);

static void LBLog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSString *line = [NSString stringWithFormat:@"[bubble] %@\n", msg];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *paths = @[kLogPath,
                       @"/var/mobile/Library/Caches/lyricbubble.log",
                       @"/tmp/lyricbubble.log",
                       @"/var/mobile/Media/lyricbubble.log"];
    for (NSString *path in paths) {
        if (![fm fileExistsAtPath:path]) [fm createFileAtPath:path contents:nil attributes:nil];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!fh) continue;
        @try { [fh seekToEndOfFile]; [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; } @catch (NSException *e) {}
        [fh closeFile];
    }
}

static NSString *ScanString(NSString *s, NSString *key) {
    NSString *needle = [NSString stringWithFormat:@"\"%@\":\"", key];
    NSRange r = [s rangeOfString:needle];
    if (r.location == NSNotFound) return nil;
    NSUInteger start = r.location + r.length;
    NSUInteger i = start;
    while (i < s.length) {
        unichar c = [s characterAtIndex:i];
        if (c == '"') break;
        i++;
    }
    if (i <= start) return nil;
    return [s substringWithRange:NSMakeRange(start, i - start)];
}

static double ScanNumber(NSString *s, NSString *key) {
    NSString *needle = [NSString stringWithFormat:@"\"%@\":", key];
    NSRange r = [s rangeOfString:needle];
    if (r.location == NSNotFound) return 0;
    NSUInteger start = r.location + r.length;
    NSUInteger i = start;
    while (i < s.length) {
        unichar c = [s characterAtIndex:i];
        if (c == ',' || c == '}') break;
        i++;
    }
    return [[s substringWithRange:NSMakeRange(start, i - start)] doubleValue];
}

static NSDictionary *ReadNP(void) {
    NSData *d = [NSData dataWithContentsOfFile:kNP];
    if (!d || d.length < 8) return nil;
    id obj = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
    if ([obj isKindOfClass:[NSDictionary class]]) return obj;

    NSString *raw = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    if (!raw) return nil;

    // np.js 实际是 window.NP_DATA={...};  取出中间对象再解析
    NSRange b = [raw rangeOfString:@"{"];
    NSRange e = [raw rangeOfString:@"}" options:NSBackwardsSearch];
    if (b.location != NSNotFound && e.location != NSNotFound && e.location > b.location) {
        NSString *j = [raw substringWithRange:NSMakeRange(b.location, e.location - b.location + 1)];
        id o2 = [NSJSONSerialization JSONObjectWithData:[j dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        if ([o2 isKindOfClass:[NSDictionary class]]) return o2;
    }

    // 最后兜底：按 key 直接扫文本
    NSMutableDictionary *m = [NSMutableDictionary dictionary];
    NSString *line = ScanString(raw, @"lyricLine");
    NSString *title = ScanString(raw, @"title");
    NSString *artist = ScanString(raw, @"artist");
    if (line) m[@"lyricLine"] = line;
    if (title) m[@"title"] = title;
    if (artist) m[@"artist"] = artist;
    m[@"playing"] = @(ScanNumber(raw, @"playing"));
    m[@"elapsed"] = @(ScanNumber(raw, @"elapsed"));
    return m.count > 2 ? m : nil;
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
    [gTail setHidden:!show];
}

static void Tick(void) {
    NSDictionary *np = ReadNP();
    if (!np) { DiagLog(@"np.js 读不到/解析失败"); SetShown(NO); return; }
    double playing = [np[@"playing"] doubleValue];
    if (playing < 0.5) { DiagLog([NSString stringWithFormat:@"playing=%.2f", playing]); SetShown(NO); return; }
    double elapsed = [np[@"elapsed"] doubleValue];

    // 首选 np.js 自带的当前行（npbridged 已算好，无需再解析 lrc）
    NSString *line = nil;
    id l2 = np[@"lyricLine"];
    if ([l2 isKindOfClass:[NSString class]] && [l2 length]) line = l2;

    // 兜底：自己从 plist 里按时间轴算
    if (!line.length) {
        for (NSString *path in @[kLrcD, kLrcE, kLrcA, kLrcB, kLrcC]) {
            NSDictionary *pl = ReadPlist(path);
            if (!pl) continue;
            NSString *lrc = pl[@"lrc"];
            if ([lrc isKindOfClass:[NSString class]] && lrc.length)
                line = CurrentLine(lrc, elapsed);
            if (line.length) { DiagLog([NSString stringWithFormat:@"用 %@ 算出当前行", path]); break; }
        }
    }

    if (!line.length) {
        DiagLog([NSString stringWithFormat:@"无歌词 el=%.2f playing=%.2f", elapsed, playing]);
        SetShown(NO);
        return;
    }
    gLabel.attributedText = Rainbow(line);
    LayoutBubble();
    SetShown(YES);
}

static UIView *FindDescendant(UIView *root, NSString *cls) {
    if (!root) return nil;
    if ([NSStringFromClass([root class]) containsString:cls]) return root;
    for (UIView *sub in root.subviews) {
        UIView *hit = FindDescendant(sub, cls);
        if (hit) return hit;
    }
    return nil;
}

static UIView *FindPetView(void) {
    NSArray<UIWindow *> *wins = [UIApplication sharedApplication].windows;
    for (UIWindow *w in wins) {
        if ([NSStringFromClass([w class]) containsString:@"MowangDaFeiYuPet"]) {
            UIView *v = FindDescendant(w, @"TouchView") ?: w;
            return v;
        }
    }
    for (UIWindow *w in wins) {
        if (w == gWin) continue;
        UIView *v = FindDescendant(w, @"MowangDaFeiYuPetTouchView");
        if (!v) v = FindDescendant(w, @"MowangDaFeiYuPet");
        if (v) return v;
    }
    return nil;
}

static void LayoutBubble(void) {
    if (!gBubble) return;
    CGRect sb = [UIScreen mainScreen].bounds;
    CGFloat bw = MIN(300.0, sb.size.width - 32.0), bh = kBubbleHeight;
    UIView *pet = FindPetView();
    CGFloat cx = sb.size.width / 2, top = sb.size.height * kBubbleYRatio;
    if (pet) {
        CGRect pr = [pet convertRect:pet.bounds toView:nil];
        if (pr.size.width > 0 && pr.size.height > 0) {
            cx = CGRectGetMidX(pr);
            top = CGRectGetMinY(pr) - bh - 14.0;
            if (top < 70) top = CGRectGetMaxY(pr) + 14.0;
        }
    }
    CGFloat x = cx - bw / 2;
    if (x < 8) x = 8;
    if (x + bw > sb.size.width - 8) x = sb.size.width - 8 - bw;
    gBubble.frame = CGRectMake(x, top, bw, bh);
    CGFloat tx = cx - 9;
    if (tx < x + 12) tx = x + 12;
    if (tx > x + bw - 30) tx = x + bw - 30;
    gTail.frame = CGRectMake(tx, top + bh - 9, 18, 18);
    gTail.hidden = !gShown;
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
    win.windowLevel = UIWindowLevelAlert + 10;
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

    // 自检标记：注入成功后 5 秒内屏幕中部出现红块 + "LB OK"
    UIView *selfTest = [[UIView alloc] initWithFrame:CGRectMake((b.size.width-180)/2, b.size.height*0.42, 180, 64)];
    selfTest.backgroundColor = [UIColor redColor];
    selfTest.layer.cornerRadius = 10;
    selfTest.userInteractionEnabled = NO;
    UILabel *t = [[UILabel alloc] initWithFrame:CGRectInset(selfTest.bounds, 6, 6)];
    t.text = @"LB 1.6 已注入";
    t.textColor = [UIColor whiteColor];
    t.textAlignment = NSTextAlignmentCenter;
    t.font = [UIFont boldSystemFontOfSize:15];
    [selfTest addSubview:t];
    [win.rootViewController.view addSubview:selfTest];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [selfTest removeFromSuperview];
    });

    UIView *tail = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 18, 18)];
    tail.backgroundColor = bubble.backgroundColor;
    tail.layer.cornerRadius = 4;
    tail.transform = CGAffineTransformMakeRotation(M_PI / 4);
    tail.userInteractionEnabled = NO;
    [win.rootViewController.view addSubview:tail];

    gBubble = bubble; gLabel = label; gTail = tail; gShown = NO;
    [gBubble setHidden:YES];
    LBLog(@"setup ok, window=%@", win);

    [NSTimer scheduledTimerWithTimeInterval:kRefresh repeats:YES block:^(NSTimer *t) { Tick(); }];
}

%ctor {
    LBLog(@"dylib loaded v1.6");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        Setup();
    });
}
