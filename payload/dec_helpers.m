#pragma mark - LC Plus helpers (added by LC Plus)
#import <objc/message.h>

static BOOL LCPlusBool(NSString *key, BOOL def) {
    id v = [NSUserDefaults.lcSharedDefaults objectForKey:key];
    return v ? [v boolValue] : def;
}

static NSInteger LCPlusInt(NSString *key, NSInteger def) {
    id v = [NSUserDefaults.lcSharedDefaults objectForKey:key];
    return v ? [v integerValue] : def;
}

static double LCPlusDouble(NSString *key, double def) {
    id v = [NSUserDefaults.lcSharedDefaults objectForKey:key];
    return v ? [v doubleValue] : def;
}

static const NSInteger kLCPlusGripTag = 0x4C50A1;

// Snap grid from settings: cols/rows = 0 when snapping to a grid is off
static void LCPlusGridDims(NSInteger *cols, NSInteger *rows) {
    switch (LCPlusInt(@"LCPlusSnapGrid", 0)) {
        case 1: *cols = 2; *rows = 1; break;
        case 2: *cols = 3; *rows = 1; break;
        case 3: *cols = 4; *rows = 1; break;
        case 4: *cols = 2; *rows = 2; break;
        case 5: *cols = 3; *rows = 3; break;
        case 6: *cols = 4; *rows = 4; break;
        case 7:
            *cols = MAX(1, MIN(8, LCPlusInt(@"LCPlusSnapCols", 3)));
            *rows = MAX(1, MIN(8, LCPlusInt(@"LCPlusSnapRows", 2)));
            break;
        default: *cols = 0; *rows = 0; break;
    }
}

static CGRect LCPlusWorkArea(UIWindow *w) {
    return UIEdgeInsetsInsetRect(w.bounds, w.safeAreaInsets);
}

// smallest signed move that puts one of the probes on one of the lines, or 0 when nothing is within threshold
static CGFloat LCPlusMagnet(NSArray<NSNumber *> *probes, NSArray<NSNumber *> *lines, CGFloat threshold) {
    CGFloat best = 0;
    BOOL found = NO;
    for (NSNumber *p in probes) {
        for (NSNumber *l in lines) {
            CGFloat d = l.doubleValue - p.doubleValue;
            if (fabs(d) <= threshold && (!found || fabs(d) < fabs(best))) {
                best = d;
                found = YES;
            }
        }
    }
    return best;
}

