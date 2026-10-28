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
static const NSInteger kLCPlusGuideXTag = 0x4C50B1;
static const NSInteger kLCPlusGuideYTag = 0x4C50B2;

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

// With the dock collapsed the windows use the WHOLE screen (no bezel of LiveContainer showing around them)
static BOOL LCPlusFullScreenActive(void) {
    return LCPlusBool(@"LCPlusFullScreenCollapsed", YES) && MultitaskDockManager.shared.isCollapsed;
}

static CGRect LCPlusWorkArea(UIWindow *w) {
    if (LCPlusFullScreenActive()) return w.bounds;
    return UIEdgeInsetsInsetRect(w.bounds, w.safeAreaInsets);
}

// Common split points used for smart snapping: quarters, thirds, halves (they cover the 2x2, 3x3 and 4x4 grids too)
static NSArray<NSNumber *> *LCPlusFractions(void) {
    return @[@0.25, @(1.0 / 3.0), @0.5, @(2.0 / 3.0), @0.75, @1.0];
}

// closest probe/line pair within tolerance: delta = move needed, line = the line that was hit
static BOOL LCPlusMagnet(NSArray<NSNumber *> *probes, NSArray<NSNumber *> *lines, CGFloat tolerance, CGFloat *delta, CGFloat *line) {
    BOOL found = NO;
    CGFloat best = 0, bestLine = 0;
    for (NSNumber *p in probes) {
        for (NSNumber *l in lines) {
            CGFloat d = l.doubleValue - p.doubleValue;
            if (fabs(d) <= tolerance && (!found || fabs(d) < fabs(best))) {
                best = d;
                bestLine = l.doubleValue;
                found = YES;
            }
        }
    }
    if (delta) *delta = best;
    if (line) *line = bestLine;
    return found;
}

// length close to a fraction of the total (e.g. "looks like a quarter") becomes exactly that fraction
static CGFloat LCPlusSnapLength(CGFloat len, CGFloat total, CGFloat tolerance) {
    CGFloat best = len, bestDist = CGFLOAT_MAX;
    for (NSNumber *f in LCPlusFractions()) {
        CGFloat target = total * f.doubleValue;
        CGFloat d = fabs(len - target);
        CGFloat tol = f.doubleValue >= 1.0 ? MIN(tolerance, 14) : tolerance; // don't jump to "fills the screen" too eagerly
        if (d <= tol && d < bestDist) {
            best = target;
            bestDist = d;
        }
    }
    return best;
}

static CGFloat LCPlusMapCoord(CGFloat v, CGFloat fromMin, CGFloat fromSize, CGFloat toMin, CGFloat toSize) {
    return fromSize > 0 ? toMin + (v - fromMin) * toSize / fromSize : v;
}

