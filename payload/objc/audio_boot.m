#include <unistd.h>

// ---- LC Plus: let apps in different windows play audio/video at the same time ----
// Every window runs in its own process, and iOS pauses one process's audio when another process activates a
// non-mixable audio session ("the last one that starts playing wins"). For guests running in a window we add the
// "mix with others" option to every category that allows it. Events are logged to <app container>/Documents/LCPlusAudio.log
// so a pause that still happens can be traced.
static IMP lcpOrigCatErr, lcpOrigCatOpt, lcpOrigCatModeOpt, lcpOrigCatModePolicyOpt;

static void lcpLog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void lcpLog(NSString *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSString *path = [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:@"LCPlusAudio.log"];
    NSData *line = [[NSString stringWithFormat:@"%@ [pid %d] %@\n", [NSDate date], getpid(), msg] dataUsingEncoding:NSUTF8StringEncoding];
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm fileExistsAtPath:path]) {
        [fm createFileAtPath:path contents:line attributes:nil];
        return;
    }
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!h) return;
    if ([h seekToEndOfFile] > 200000) [h truncateFileAtOffset:0];
    [h writeData:line];
    [h closeFile];
}

static BOOL lcpMixable(NSString *category) {
    return [category isEqualToString:@"AVAudioSessionCategoryPlayback"]
        || [category isEqualToString:@"AVAudioSessionCategoryPlayAndRecord"]
        || [category isEqualToString:@"AVAudioSessionCategoryMultiRoute"];
}

static BOOL lcpCatErr(id self, SEL _cmd, NSString *category, NSError **error) {
    if (lcpMixable(category) && lcpOrigCatOpt) {
        lcpLog(@"setCategory:%@ -> mixing", category);
        return ((BOOL (*)(id, SEL, NSString *, NSUInteger, NSError **))lcpOrigCatOpt)(self, sel_registerName("setCategory:withOptions:error:"), category, 1, error);
    }
    lcpLog(@"setCategory:%@ (not mixable, unchanged)", category);
    return ((BOOL (*)(id, SEL, NSString *, NSError **))lcpOrigCatErr)(self, _cmd, category, error);
}

static BOOL lcpCatOpt(id self, SEL _cmd, NSString *category, NSUInteger options, NSError **error) {
    NSUInteger before = options;
    if (lcpMixable(category)) options |= 1; // AVAudioSessionCategoryOptionMixWithOthers
    lcpLog(@"setCategory:%@ options %lu -> %lu", category, (unsigned long)before, (unsigned long)options);
    return ((BOOL (*)(id, SEL, NSString *, NSUInteger, NSError **))lcpOrigCatOpt)(self, _cmd, category, options, error);
}

static BOOL lcpCatModeOpt(id self, SEL _cmd, NSString *category, NSString *mode, NSUInteger options, NSError **error) {
    NSUInteger before = options;
    if (lcpMixable(category)) options |= 1;
    lcpLog(@"setCategory:%@ mode:%@ options %lu -> %lu", category, mode, (unsigned long)before, (unsigned long)options);
    return ((BOOL (*)(id, SEL, NSString *, NSString *, NSUInteger, NSError **))lcpOrigCatModeOpt)(self, _cmd, category, mode, options, error);
}

static BOOL lcpCatModePolicyOpt(id self, SEL _cmd, NSString *category, NSString *mode, NSUInteger policy, NSUInteger options, NSError **error) {
    NSUInteger beforeOptions = options, beforePolicy = policy;
    if (lcpMixable(category)) {
        options |= 1;
        policy = 0; // long-form routing policies (Netflix/YouTube style) can't be mixed, so fall back to the default policy
    }
    lcpLog(@"setCategory:%@ mode:%@ policy %lu -> %lu options %lu -> %lu", category, mode,
           (unsigned long)beforePolicy, (unsigned long)policy, (unsigned long)beforeOptions, (unsigned long)options);
    return ((BOOL (*)(id, SEL, NSString *, NSString *, NSUInteger, NSUInteger, NSError **))lcpOrigCatModePolicyOpt)(self, _cmd, category, mode, policy, options, error);
}

static void LCPlusMixAudioInstall(void) {
    dlopen("/System/Library/Frameworks/AVFAudio.framework/AVFAudio", RTLD_NOW);
    dlopen("/System/Library/Frameworks/AVFoundation.framework/AVFoundation", RTLD_NOW);
    Class c = NSClassFromString(@"AVAudioSession");
    if (!c) return;
    struct { const char *sel; IMP imp; IMP *orig; } hooks[] = {
        { "setCategory:error:", (IMP)lcpCatErr, &lcpOrigCatErr },
        { "setCategory:withOptions:error:", (IMP)lcpCatOpt, &lcpOrigCatOpt },
        { "setCategory:mode:options:error:", (IMP)lcpCatModeOpt, &lcpOrigCatModeOpt },
        { "setCategory:mode:routeSharingPolicy:options:error:", (IMP)lcpCatModePolicyOpt, &lcpOrigCatModePolicyOpt },
    };
    for (size_t i = 0; i < sizeof(hooks) / sizeof(hooks[0]); i++) {
        Method m = class_getInstanceMethod(c, sel_registerName(hooks[i].sel));
        if (m) *hooks[i].orig = method_setImplementation(m, hooks[i].imp);
    }
    [[NSNotificationCenter defaultCenter] addObserverForName:@"AVAudioSessionInterruptionNotification" object:nil queue:nil
                                                  usingBlock:^(NSNotification *note) {
        lcpLog(@"INTERRUPTION %@", note.userInfo);
    }];
    lcpLog(@"mix-with-others hooks installed");
}

