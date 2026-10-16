// LCPlus.m — extra multitask-window features for LiveContainer.
// Injected into the LiveContainer *host* app (not guest apps). Pure runtime hooks by selector name,
// so it survives version drift: any hook whose target is missing is skipped and logged.
// Log: LiveContainer Documents/LCPlus.log
//
// Features (via the extra button in every window's title bar):
//   - New instance: launches the same app in the next free container, in a new window
//   - Hide window bar: chromeless mode at ANY window size (drag the top strip to move,
//     double-tap the strip to bring the bar back)
//   - Snap: left/right half, thirds, two-thirds, full
//   - Optional: snap when a window drag ends at the left/right screen edge
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#pragma mark - util

static void LCLog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void LCLog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *line = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSLog(@"[LCPlus] %@", line);
    static NSString *path;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        path = [docs stringByAppendingPathComponent:@"LCPlus.log"];
    });
    NSData *d = [[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fh) { [d writeToFile:path atomically:YES]; return; }
    [fh seekToEndOfFile]; [fh writeData:d]; [fh closeFile];
}

static char kChromeless, kGrip, kGripOwner;

static id LCGet(id o, NSString *k) {
    if (!o) return nil;
    @try { return [o valueForKey:k]; } @catch (NSException *e) { return nil; }
}
static BOOL LCBool(id o, NSString *k) { return [LCGet(o, k) boolValue]; }
static void LCPoke(id o, NSString *sel) {
    SEL s = NSSelectorFromString(sel);
    if (o && [o respondsToSelector:s]) ((void (*)(id, SEL))objc_msgSend)(o, s);
}
static BOOL LCIsChromeless(id vc) { return [objc_getAssociatedObject(vc, &kChromeless) boolValue]; }

static Class LCFindClass(NSString *name) {
    Class c = NSClassFromString(name);
    if (c) return c;
    // Swift classes are registered as "Module.Name" unless @objc(Name) is used
    NSString *suffix = [@"." stringByAppendingString:name];
    const char *suf = suffix.UTF8String; size_t sl = strlen(suf);
    unsigned int n = 0; Class *all = objc_copyClassList(&n);
    for (unsigned int i = 0; i < n; i++) {
        const char *cn = class_getName(all[i]); size_t l = strlen(cn);
        if (l > sl && strcmp(cn + l - sl, suf) == 0) { c = all[i]; break; }
    }
    free(all);
    return c;
}

#pragma mark - snapping

typedef NS_ENUM(NSInteger, LCSnapKind) {
    LCSnapLeftHalf, LCSnapRightHalf, LCSnapLeftThird, LCSnapMiddleThird,
    LCSnapRightThird, LCSnapLeftTwoThirds, LCSnapRightTwoThirds, LCSnapFull
};

static CGRect LCWorkArea(id vc) {
    UIView *v = LCGet(vc, @"view");
    UIView *host = v.superview ?: v.window;
    UIEdgeInsets in = v.window.safeAreaInsets;
    return UIEdgeInsetsInsetRect(host.bounds, in);
}

static CGRect LCSnapFrame(CGRect a, LCSnapKind k) {
    CGFloat x = a.origin.x, y = a.origin.y, w = a.size.width, h = a.size.height;
    switch (k) {
        case LCSnapLeftHalf:        return CGRectMake(x, y, w / 2, h);
        case LCSnapRightHalf:       return CGRectMake(x + w / 2, y, w / 2, h);
        case LCSnapLeftThird:       return CGRectMake(x, y, w / 3, h);
        case LCSnapMiddleThird:     return CGRectMake(x + w / 3, y, w / 3, h);
        case LCSnapRightThird:      return CGRectMake(x + 2 * w / 3, y, w / 3, h);
        case LCSnapLeftTwoThirds:   return CGRectMake(x, y, 2 * w / 3, h);
        case LCSnapRightTwoThirds:  return CGRectMake(x + w / 3, y, 2 * w / 3, h);
        default:                    return a;
    }
}

static void LCSnap(id vc, LCSnapKind k) {
    if (!vc) return;
    BOOL maxed = LCBool(vc, @"isMaximized");
    if (k == LCSnapFull) { if (!maxed) LCPoke(vc, @"maximizeWindow"); return; }
    __weak id w = vc;
    void (^apply)(void) = ^{
        id s = w; if (!s) return;
        UIView *v = LCGet(s, @"view");
        CGRect target = CGRectIntegral(LCSnapFrame(LCWorkArea(s), k));
        [UIView animateWithDuration:0.25 animations:^{ v.frame = target; [v layoutIfNeeded]; }];
        LCPoke(s, @"updateOriginalFrame");
    };
    if (maxed) {  // restore from maximized first
        LCPoke(vc, @"maximizeWindow");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), apply);
    } else {
        apply();
    }
}

#pragma mark - chromeless

static void LCApplyChromeless(id vc) {
    UINavigationBar *bar = LCGet(vc, @"navigationBar");
    UIView *root = LCGet(vc, @"view");
    UIView *scene = [LCGet(vc, @"appSceneVC") view];
    if (!bar || !root || !scene) return;
    NSArray *old = LCGet(vc, @"activatedVerticalConstraints");
    if (old) [NSLayoutConstraint deactivateConstraints:old];
    bar.hidden = YES; bar.alpha = 0;
    NSArray *nw = @[
        [scene.topAnchor constraintEqualToAnchor:root.topAnchor],
        [scene.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [bar.heightAnchor constraintEqualToConstant:0],
    ];
    [NSLayoutConstraint activateConstraints:nw];
    @try { [vc setValue:nw forKey:@"activatedVerticalConstraints"]; } @catch (NSException *e) {}
    [root layoutIfNeeded];
}

@interface LCPlusHelper : NSObject
+ (instancetype)shared;
- (void)gripDoubleTap:(UITapGestureRecognizer *)g;
@end

static void LCSetChromeless(id vc, BOOL on);

@implementation LCPlusHelper
+ (instancetype)shared {
    static LCPlusHelper *h; static dispatch_once_t o;
    dispatch_once(&o, ^{ h = [LCPlusHelper new]; });
    return h;
}
- (void)gripDoubleTap:(UITapGestureRecognizer *)g {
    id vc = [objc_getAssociatedObject(g.view, &kGripOwner) nonretainedObjectValue];
    if (vc) LCSetChromeless(vc, NO);
}
@end

static void LCSyncGrip(id vc) {
    UIView *root = LCGet(vc, @"view");
    UIView *grip = objc_getAssociatedObject(vc, &kGrip);
    if (!LCIsChromeless(vc)) {
        [grip removeFromSuperview];
        objc_setAssociatedObject(vc, &kGrip, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if (grip.superview || !root) return;
    grip = [UIView new];
    grip.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *pill = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 40, 4)];
    pill.backgroundColor = [UIColor colorWithWhite:1 alpha:0.55];
    pill.layer.cornerRadius = 2;
    pill.layer.shadowColor = UIColor.blackColor.CGColor;
    pill.layer.shadowOpacity = 0.5; pill.layer.shadowRadius = 1.5; pill.layer.shadowOffset = CGSizeZero;
    pill.translatesAutoresizingMaskIntoConstraints = NO;
    pill.userInteractionEnabled = NO;
    [grip addSubview:pill];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:vc action:NSSelectorFromString(@"moveWindow:")];
    pan.minimumNumberOfTouches = 1; pan.maximumNumberOfTouches = 1;
    [grip addGestureRecognizer:pan];
    UITapGestureRecognizer *dbl = [[UITapGestureRecognizer alloc] initWithTarget:LCPlusHelper.shared action:@selector(gripDoubleTap:)];
    dbl.numberOfTapsRequired = 2;
    [grip addGestureRecognizer:dbl];
    objc_setAssociatedObject(grip, &kGripOwner, [NSValue valueWithNonretainedObject:vc], OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [root addSubview:grip];
    [NSLayoutConstraint activateConstraints:@[
        [grip.topAnchor constraintEqualToAnchor:root.topAnchor],
        [grip.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [grip.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [grip.heightAnchor constraintEqualToConstant:22],
        [pill.centerXAnchor constraintEqualToAnchor:grip.centerXAnchor],
        [pill.topAnchor constraintEqualToAnchor:grip.topAnchor constant:5],
        [pill.widthAnchor constraintEqualToConstant:40],
        [pill.heightAnchor constraintEqualToConstant:4],
    ]];
    objc_setAssociatedObject(vc, &kGrip, grip, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void LCSetChromeless(id vc, BOOL on) {
    if (!vc) return;
    objc_setAssociatedObject(vc, &kChromeless, @(on), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    LCPoke(vc, @"updateVerticalConstraints");   // our hook applies; the original restores when off
    LCSyncGrip(vc);
    UIView *handle = LCGet(vc, @"resizeHandle");
    if (!LCBool(vc, @"isMaximized")) handle.alpha = on ? 0.45 : 1.0;
}

#pragma mark - new instance

static BOOL LCContainerInUse(NSString *folder) {
    BOOL used = NO;
    Class mm = LCFindClass(@"MultitaskManager");
    SEL s1 = NSSelectorFromString(@"isUsingWithContainer:");
    if (mm && [mm respondsToSelector:s1]) used = ((BOOL (*)(id, SEL, NSString *))objc_msgSend)(mm, s1, folder);
    if (!used) {
        Class su = NSClassFromString(@"LCSharedUtils");
        SEL s2 = NSSelectorFromString(@"getContainerUsingLCSchemeWithFolderName:");
        if (su && [su respondsToSelector:s2]) used = ((id (*)(id, SEL, NSString *))objc_msgSend)(su, s2, folder) != nil;
    }
    return used;
}

static NSString *LCOwnScheme(void) {
    for (NSDictionary *t in NSBundle.mainBundle.infoDictionary[@"CFBundleURLTypes"])
        for (NSString *s in t[@"CFBundleURLSchemes"])
            if ([s hasPrefix:@"livecontainer"]) return s;
    return @"livecontainer";
}

static void LCAlert(id vc, NSString *title, NSString *msg) {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    UIViewController *top = [(UIViewController *)vc view].window.rootViewController ?: vc;
    while (top.presentedViewController) top = top.presentedViewController;
    [top presentViewController:a animated:YES completion:nil];
}

static void LCNewInstance(id vc) {
    if (!vc) return;
    id scene = LCGet(vc, @"appSceneVC");
    NSString *bundleId = LCGet(scene, @"bundleId");
    NSString *cur = LCGet(scene, @"dataUUID") ?: LCGet(vc, @"dataUUID");
    if (!bundleId) { LCLog(@"new instance: no bundleId"); LCAlert(vc, @"New instance", @"Couldn't read this window's app."); return; }

    NSString *bundlePath = nil;
    Class su = NSClassFromString(@"LCSharedUtils");
    SEL fs = NSSelectorFromString(@"findBundleWithBundleId:isSharedAppOut:");
    if (su && [su respondsToSelector:fs]) {
        bool shared = false;
        NSBundle *b = ((NSBundle *(*)(id, SEL, NSString *, bool *))objc_msgSend)(su, fs, bundleId, &shared);
        bundlePath = b.bundlePath;
    }
    if (!bundlePath) {
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        bundlePath = [[docs stringByAppendingPathComponent:@"Applications"] stringByAppendingPathComponent:bundleId];
    }
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[bundlePath stringByAppendingPathComponent:@"LCAppInfo.plist"]];
    NSArray *containers = info[@"LCContainers"];
    NSString *free = nil;
    for (NSDictionary *c in containers) {
        if (![c isKindOfClass:NSDictionary.class]) continue;
        NSString *fn = c[@"folderName"];
        if (!fn.length || [fn isEqualToString:cur]) continue;
        if (!LCContainerInUse(fn)) { free = fn; break; }
    }
    LCLog(@"new instance: app=%@ cur=%@ containers=%lu free=%@", bundlePath.lastPathComponent, cur, (unsigned long)containers.count, free);
    if (!free) {
        LCAlert(vc, @"No free container",
                @"Every container of this app is already running. Add another one in LiveContainer (long-press the app → Containers), then try again.");
        return;
    }
    NSURLComponents *u = [NSURLComponents new];
    u.scheme = LCOwnScheme();
    u.host = @"livecontainer-launch";
    u.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"bundle-name" value:bundlePath.lastPathComponent],
        [NSURLQueryItem queryItemWithName:@"container-folder-name" value:free],
    ];
    [UIApplication.sharedApplication openURL:u.URL options:@{} completionHandler:^(BOOL ok) {
        LCLog(@"new instance: openURL %@ -> %d", u.URL, ok);
    }];
}

#pragma mark - menu button

static NSArray<UIMenuElement *> *LCMenuItems(id vc) {
    __weak id w = vc;
    UIAction *inst = [UIAction actionWithTitle:@"New instance" image:[UIImage systemImageNamed:@"plus.square.on.square"]
                                    identifier:nil handler:^(UIAction *a) { LCNewInstance(w); }];
    BOOL chrome = LCIsChromeless(vc);
    UIAction *bar = [UIAction actionWithTitle:(chrome ? @"Show window bar" : @"Hide window bar")
                                        image:[UIImage systemImageNamed:@"rectangle.topthird.inset.filled"]
                                   identifier:nil handler:^(UIAction *a) { LCSetChromeless(w, !LCIsChromeless(w)); }];
    NSArray *titles = @[@"Left half", @"Right half", @"Left third", @"Middle third", @"Right third",
                        @"Left two-thirds", @"Right two-thirds", @"Full screen"];
    NSMutableArray *snaps = [NSMutableArray array];
    for (NSInteger i = 0; i < (NSInteger)titles.count; i++) {
        [snaps addObject:[UIAction actionWithTitle:titles[i] image:nil identifier:nil
                                           handler:^(UIAction *a) { LCSnap(w, (LCSnapKind)i); }]];
    }
    UIMenu *snap = [UIMenu menuWithTitle:@"Snap" image:[UIImage systemImageNamed:@"rectangle.split.3x1"]
                              identifier:nil options:0 children:snaps];
    BOOL edge = [NSUserDefaults.standardUserDefaults boolForKey:@"LCPlusEdgeSnap"];
    UIAction *edgeA = [UIAction actionWithTitle:@"Snap when dragged to edge" image:nil identifier:nil
                                        handler:^(UIAction *a) {
        [NSUserDefaults.standardUserDefaults setBool:!edge forKey:@"LCPlusEdgeSnap"];
    }];
    edgeA.state = edge ? UIMenuElementStateOn : UIMenuElementStateOff;
    return @[inst, bar, snap, edgeA];
}

static void LCInstallButton(id vc) {
    UINavigationItem *item = LCGet(vc, @"navigationItem");
    if (!item) return;
    __weak id w = vc;
    UIDeferredMenuElement *def = [UIDeferredMenuElement elementWithUncachedProvider:^(void (^completion)(NSArray<UIMenuElement *> *)) {
        completion(LCMenuItems(w));
    }];
    UIImage *img = [[UIImage systemImageNamed:@"square.grid.2x2"]
        imageWithConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightMedium]];
    UIBarButtonItem *btn = [[UIBarButtonItem alloc] initWithImage:img menu:[UIMenu menuWithChildren:@[def]]];
    btn.tintColor = UIColor.systemBlueColor;
    if (item.leftBarButtonItems.count)
        item.leftBarButtonItems = [item.leftBarButtonItems arrayByAddingObject:btn];
    else
        item.rightBarButtonItems = [(item.rightBarButtonItems ?: @[]) arrayByAddingObject:btn];
}

#pragma mark - hooks

static void (*orig_setup)(id, SEL);
static void hook_setup(id self, SEL _cmd) {
    orig_setup(self, _cmd);
    __weak id w = self;
    // the original init adds its own bar buttons after this returns; append ours once it's done
    dispatch_async(dispatch_get_main_queue(), ^{ id s = w; if (s) LCInstallButton(s); });
}

static void (*orig_updateVC)(id, SEL);
static void hook_updateVC(id self, SEL _cmd) {
    orig_updateVC(self, _cmd);
    if (LCIsChromeless(self)) LCApplyChromeless(self);
}

static void (*orig_move)(id, SEL, UIPanGestureRecognizer *);
static void hook_move(id self, SEL _cmd, UIPanGestureRecognizer *g) {
    orig_move(self, _cmd, g);
    if (g.state != UIGestureRecognizerStateEnded) return;
    if (![NSUserDefaults.standardUserDefaults boolForKey:@"LCPlusEdgeSnap"]) return;
    if (LCBool(self, @"isMaximized")) return;
    UIView *host = ((UIView *)LCGet(self, @"view")).superview;
    if (!host) return;
    CGPoint p = [g locationInView:host];
    if (p.x <= CGRectGetMinX(host.bounds) + 20) LCSnap(self, LCSnapLeftHalf);
    else if (p.x >= CGRectGetMaxX(host.bounds) - 20) LCSnap(self, LCSnapRightHalf);
}

static BOOL LCHook(Class c, NSString *sel, IMP imp, IMP *orig) {
    Method m = class_getInstanceMethod(c, NSSelectorFromString(sel));
    if (!m) { LCLog(@"hook skipped, selector missing: %@", sel); return NO; }
    *orig = method_setImplementation(m, imp);
    LCLog(@"hooked %@", sel);
    return YES;
}

static void LCInstall(int attempt) {
    Class dc = LCFindClass(@"DecoratedAppSceneViewController");
    if (!dc) {
        if (attempt < 5) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ LCInstall(attempt + 1); });
        } else {
            LCLog(@"DecoratedAppSceneViewController not found: unsupported LiveContainer build, nothing patched");
        }
        return;
    }
    LCLog(@"installing on %s (iOS %@)", class_getName(dc), UIDevice.currentDevice.systemVersion);
    LCHook(dc, @"setupDecoratedView", (IMP)hook_setup, (IMP *)&orig_setup);
    LCHook(dc, @"updateVerticalConstraints", (IMP)hook_updateVC, (IMP *)&orig_updateVC);
    LCHook(dc, @"moveWindow:", (IMP)hook_move, (IMP *)&orig_move);
}

__attribute__((constructor)) static void LCPlusInit(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ LCInstall(0); });
}
