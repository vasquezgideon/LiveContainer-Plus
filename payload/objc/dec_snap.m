#pragma mark - LC Plus snapping (added by LC Plus)

- (NSArray<NSValue *> *)lcPlusNeighborFrames {
    NSMutableArray *frames = [NSMutableArray array];
    for (UIView *s in self.view.superview.subviews) {
        if (s == self.view || s.hidden || s.alpha < 0.1 || ![s isKindOfClass:UIStackView.class]) continue;
        [frames addObject:[NSValue valueWithCGRect:s.frame]];
    }
    return frames;
}

// Every position a window edge can snap to: screen edges, the middle, quarters/thirds, the selected grid, other windows
- (void)lcPlusLinesX:(NSArray<NSNumber *> **)xs y:(NSArray<NSNumber *> **)ys {
    CGRect a = LCPlusWorkArea(self.view.window);
    NSMutableArray *X = [NSMutableArray arrayWithObjects:@(CGRectGetMinX(a)), @(CGRectGetMaxX(a)), nil];
    NSMutableArray *Y = [NSMutableArray arrayWithObjects:@(CGRectGetMinY(a)), @(CGRectGetMaxY(a)), nil];
    if (LCPlusBool(@"LCPlusSnapMid", YES)) {
        [X addObject:@(CGRectGetMidX(a))];
        [Y addObject:@(CGRectGetMidY(a))];
    }
    if (LCPlusBool(@"LCPlusSmartSnap", YES)) {
        for (NSNumber *fr in LCPlusFractions()) {
            if (fr.doubleValue >= 1.0) continue;
            [X addObject:@(a.origin.x + a.size.width * fr.doubleValue)];
            [Y addObject:@(a.origin.y + a.size.height * fr.doubleValue)];
        }
    }
    NSInteger cols = 0, rows = 0;
    LCPlusGridDims(&cols, &rows);
    for (NSInteger i = 1; i < cols; i++) [X addObject:@(a.origin.x + a.size.width * i / cols)];
    for (NSInteger i = 1; i < rows; i++) [Y addObject:@(a.origin.y + a.size.height * i / rows)];
    for (NSValue *v in [self lcPlusNeighborFrames]) {
        CGRect f = v.CGRectValue;
        [X addObject:@(CGRectGetMinX(f))];
        [X addObject:@(CGRectGetMaxX(f))];
        [Y addObject:@(CGRectGetMinY(f))];
        [Y addObject:@(CGRectGetMaxY(f))];
    }
    *xs = X;
    *ys = Y;
}

// thin guide lines while a window is locked to a snap line
- (void)lcPlusShowGuidesX:(NSNumber *)x y:(NSNumber *)y {
    UIView *host = self.view.superview;
    if (!host) return;
    NSArray *specs = @[@[@(kLCPlusGuideXTag), x ?: (id)NSNull.null, @YES], @[@(kLCPlusGuideYTag), y ?: (id)NSNull.null, @NO]];
    for (NSArray *s in specs) {
        NSInteger tag = [s[0] integerValue];
        id pos = s[1];
        BOOL vertical = [s[2] boolValue];
        UIView *g = [host viewWithTag:tag];
        if ([pos isKindOfClass:NSNull.class]) {
            [g removeFromSuperview];
            continue;
        }
        if (!g) {
            g = [UIView new];
            g.tag = tag;
            g.userInteractionEnabled = NO;
            g.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.85];
            [host insertSubview:g aboveSubview:self.view];
        }
        CGFloat p = [pos doubleValue];
        g.frame = vertical ? CGRectMake(p - 1, 0, 2, host.bounds.size.height) : CGRectMake(0, p - 1, host.bounds.size.width, 2);
    }
}

- (void)lcPlusSnapStateChanged:(NSInteger)state {
    if ((state & ~self.lcPlusSnapState) != 0) {
        [[UISelectionFeedbackGenerator new] selectionChanged];
    }
    self.lcPlusSnapState = state;
}

// With the dock collapsed a window that reaches the screen edges should look like a fullscreen launch:
// no rounded corners / border where it touches the edge of the screen.
- (void)lcPlusUpdateChrome {
    UIWindow *w = self.view.window;
    if (!w) return;
    CALayer *l = self.view.layer;
    const CACornerMask all = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner;
    if (!LCPlusFullScreenActive()) {
        l.maskedCorners = all;
        l.borderWidth = _isMaximized ? 0.0 : 1.0;
        return;
    }
    CGRect f = self.view.frame, b = w.bounds;
    const CGFloat e = 1.5;
    BOOL left = CGRectGetMinX(f) <= CGRectGetMinX(b) + e, right = CGRectGetMaxX(f) >= CGRectGetMaxX(b) - e;
    BOOL top = CGRectGetMinY(f) <= CGRectGetMinY(b) + e, bottom = CGRectGetMaxY(f) >= CGRectGetMaxY(b) - e;
    CACornerMask m = 0;
    if (!(left || top)) m |= kCALayerMinXMinYCorner;
    if (!(right || top)) m |= kCALayerMaxXMinYCorner;
    if (!(left || bottom)) m |= kCALayerMinXMaxYCorner;
    if (!(right || bottom)) m |= kCALayerMaxXMaxYCorner;
    l.maskedCorners = m;
    l.borderWidth = (_isMaximized || (left && right && top && bottom)) ? 0.0 : 1.0;
}

// Insets the app should see: with the dock collapsed a window that reaches the screen edges gets the real device
// insets for the part under the notch / home indicator (same as a fullscreen launch); otherwise none.
- (UIEdgeInsets)lcPlusDesiredInsets {
    UIEdgeInsets ins = UIEdgeInsetsZero;
    if (!LCPlusFullScreenActive() || !self.view.window) return ins;
    UIWindow *w = self.view.window;
    UIEdgeInsets dev = w.safeAreaInsets;
    CGRect f = self.view.frame, b = w.bounds;
    ins.top = MAX(0, MIN(f.size.height, dev.top - CGRectGetMinY(f)));
    ins.left = MAX(0, MIN(f.size.width, dev.left - CGRectGetMinX(f)));
    ins.bottom = MAX(0, MIN(f.size.height, CGRectGetMaxY(f) - (CGRectGetMaxY(b) - dev.bottom)));
    ins.right = MAX(0, MIN(f.size.width, CGRectGetMaxX(f) - (CGRectGetMaxX(b) - dev.right)));
    if (!self.navigationBar.hidden) { // the window bar already covers that edge
        if ([NSUserDefaults.lcSharedDefaults boolForKey:@"LCMultitaskBottomWindowBar"]) ins.bottom = 0;
        else ins.top = 0;
    }
    return ins;
}

// Replaces the stock "zero insets" for windowed apps. Runs inside the stock scene-settings callback, so the
// frame/size handling stays exactly as in stock and nothing here can bounce a window.
- (void)lcPlusApplyWindowedInsets:(UIMutableApplicationSceneSettings *)settings {
    UIEdgeInsets ins = [self lcPlusDesiredInsets];
    self.lcPlusInsetsKey = NSStringFromUIEdgeInsets(ins);
    CGFloat r = _scaleRatio > 0 ? _scaleRatio : 1;
    UIEdgeInsets scaled = UIEdgeInsetsMake(ins.top / r, ins.left / r, ins.bottom / r, ins.right / r);
    settings.peripheryInsets = scaled;
    if (UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPad) {
        settings.safeAreaInsetsPortrait = LCUIEdgeInsetsRotateToOrientation(scaled, UIApp.statusBarOrientation);
    } else {
        settings.safeAreaInsetsPortrait = scaled;
    }
}

// Cheap check (called on every layout and after moves): if the insets should change, nudge the stock settings update.
- (void)lcPlusUpdateInsets {
    [self lcPlusUpdateChrome];
    if (_isMaximized) {
        self.lcPlusInsetsKey = nil; // stock code manages the insets while maximized
        return;
    }
    if (!self.view.window || !self.appSceneVC) return;
    NSString *key = NSStringFromUIEdgeInsets([self lcPlusDesiredInsets]);
    if ([key isEqualToString:(self.lcPlusInsetsKey ?: NSStringFromUIEdgeInsets(UIEdgeInsetsZero))]) return;
    [self.appSceneVC updateFrameWithSettingsBlock:nil];
}

// Align the window to the nearest cells of the selected grid (called when a move/resize ends)
- (void)lcPlusSnapFrameToGrid {
    NSInteger cols = 0, rows = 0;
    LCPlusGridDims(&cols, &rows);
    if (cols <= 0 || !self.view.window) return;
    CGRect a = LCPlusWorkArea(self.view.window);
    CGRect f = self.view.frame;
    CGFloat cw = a.size.width / cols, ch = a.size.height / rows;
    CGFloat l = round((f.origin.x - a.origin.x) / cw), r = round((CGRectGetMaxX(f) - a.origin.x) / cw);
    CGFloat t = round((f.origin.y - a.origin.y) / ch), b = round((CGRectGetMaxY(f) - a.origin.y) / ch);
    l = MAX(0, MIN((CGFloat)cols - 1, l));
    r = MAX(l + 1, MIN((CGFloat)cols, r));
    t = MAX(0, MIN((CGFloat)rows - 1, t));
    b = MAX(t + 1, MIN((CGFloat)rows, b));
    CGRect nf = CGRectMake(a.origin.x + l * cw, a.origin.y + t * ch, (r - l) * cw, (b - t) * ch);
    [UIView animateWithDuration:0.2 animations:^{
        self.view.frame = CGRectIntegral(nf);
    }];
    [self updateOriginalFrame];
    [self lcPlusUpdateInsets];
}

// Smart snap on release, no grid setting needed: a window that "looks like" a quarter / third / half becomes exactly that,
// and its edges lock to the screen edges, the middle and neighbouring windows.
- (void)lcPlusSmartSnapOnRelease:(BOOL)resizing {
    if (!LCPlusBool(@"LCPlusSmartSnap", YES) || !self.view.window) return;
    UIView *v = self.view;
    CGRect a = LCPlusWorkArea(v.window);
    CGRect f = v.frame;
    CGFloat thr = LCPlusDouble(@"LCPlusSnapThreshold", 20);
    CGFloat tol = MAX(thr * 1.6, 24);
    NSArray<NSNumber *> *xs = nil, *ys = nil;
    [self lcPlusLinesX:&xs y:&ys];
    CGFloat d = 0, line = 0;
    if (resizing) {
        f.size.width = MAX(50, LCPlusSnapLength(f.size.width, a.size.width, tol));
        f.size.height = MAX(50, LCPlusSnapLength(f.size.height, a.size.height, tol));
        if (LCPlusMagnet(@[@(CGRectGetMaxX(f))], xs, tol, &d, &line)) f.size.width = MAX(50, f.size.width + d);
        if (LCPlusMagnet(@[@(CGRectGetMaxY(f))], ys, tol, &d, &line)) f.size.height = MAX(50, f.size.height + d);
    }
    if (LCPlusMagnet(@[@(CGRectGetMinX(f)), @(CGRectGetMaxX(f))], xs, tol, &d, &line)) f.origin.x += d;
    if (LCPlusMagnet(@[@(CGRectGetMinY(f)), @(CGRectGetMaxY(f))], ys, tol, &d, &line)) f.origin.y += d;
    f = CGRectIntegral(f);
    if (CGRectEqualToRect(f, v.frame)) return;
    [UIView animateWithDuration:0.18 animations:^{
        v.frame = f;
    }];
    [self updateOriginalFrame];
    [self lcPlusUpdateInsets];
}

// YES = handled here, NO = fall through to the stock behaviour
- (BOOL)lcPlusHandleMove:(UIPanGestureRecognizer *)g {
    CGFloat thr = LCPlusDouble(@"LCPlusSnapThreshold", 20);
    NSInteger cols = 0, rows = 0;
    LCPlusGridDims(&cols, &rows);
    BOOL edgeDrop = LCPlusBool(@"LCPlusEdgeDrop", YES);
    BOOL smart = LCPlusBool(@"LCPlusSmartSnap", YES);
    if (thr <= 0 && cols == 0 && !edgeDrop && !smart) return NO;
    if (_isMaximized) return YES;
    UIView *v = self.view;
    if (!v.superview || !v.window) return NO;

    if (g.state == UIGestureRecognizerStateBegan || !self.lcPlusTracking) {
        self.lcRawOrigin = v.frame.origin;
        self.lcPlusTracking = YES;
        self.lcPlusSnapState = 0;
    }
    CGPoint t = [g translationInView:v];
    [g setTranslation:CGPointZero inView:v];
    self.lcRawOrigin = CGPointMake(self.lcRawOrigin.x + t.x, self.lcRawOrigin.y + t.y);

    CGRect f = v.frame;
    f.origin = self.lcRawOrigin;
    NSNumber *guideX = nil, *guideY = nil;
    if (thr > 0) {
        NSArray<NSNumber *> *xs = nil, *ys = nil;
        [self lcPlusLinesX:&xs y:&ys];
        CGFloat dx = 0, dy = 0, lx = 0, ly = 0;
        BOOL sx = LCPlusMagnet(@[@(CGRectGetMinX(f)), @(CGRectGetMaxX(f)), @(CGRectGetMidX(f))], xs, thr, &dx, &lx);
        BOOL sy = LCPlusMagnet(@[@(CGRectGetMinY(f)), @(CGRectGetMaxY(f))], ys, thr, &dy, &ly);
        if (sx) { f.origin.x += dx; guideX = @(lx); }
        if (sy) { f.origin.y += dy; guideY = @(ly); }
        [self lcPlusSnapStateChanged:(sx ? 1 : 0) | (sy ? 2 : 0)];
    }
    v.frame = f;

    BOOL ended = (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled || g.state == UIGestureRecognizerStateFailed);
    if (!ended) {
        [self lcPlusShowGuidesX:guideX y:guideY];
        [self updateOriginalFrame];
        return YES;
    }
    self.lcPlusTracking = NO;
    self.lcPlusSnapState = 0;
    [self lcPlusShowGuidesX:nil y:nil];
    BOOL placed = NO;
    if (edgeDrop && g.state == UIGestureRecognizerStateEnded) {
        CGPoint p = [g locationInView:v.superview];
        CGRect a = LCPlusWorkArea(v.window);
        if (p.x <= CGRectGetMinX(a) + 24) {
            [self lcPlusPlaceCols:2 rows:1 col:0 row:0 colSpan:1 rowSpan:1];
            placed = YES;
        } else if (p.x >= CGRectGetMaxX(a) - 24) {
            [self lcPlusPlaceCols:2 rows:1 col:1 row:0 colSpan:1 rowSpan:1];
            placed = YES;
        }
    }
    if (!placed) {
        if (cols > 0) [self lcPlusSnapFrameToGrid];
        else [self lcPlusSmartSnapOnRelease:NO];
    }
    [self updateOriginalFrame];
    [self lcPlusUpdateInsets];
    return YES;
}

- (BOOL)lcPlusHandleResize:(UIPanGestureRecognizer *)g {
    CGFloat thr = LCPlusDouble(@"LCPlusSnapThreshold", 20);
    NSInteger cols = 0, rows = 0;
    LCPlusGridDims(&cols, &rows);
    BOOL smart = LCPlusBool(@"LCPlusSmartSnap", YES);
    if (thr <= 0 && cols == 0 && !smart) return NO;
    if (_isMaximized) return YES;
    UIView *v = self.view;
    if (!v.superview || !v.window) return NO;

    if (g.state == UIGestureRecognizerStateBegan || !self.lcPlusTracking) {
        self.lcRawSize = v.frame.size;
        self.lcPlusTracking = YES;
        self.lcPlusSnapState = 0;
    }
    CGPoint t = [g translationInView:v];
    [g setTranslation:CGPointZero inView:v];
    self.lcRawSize = CGSizeMake(MAX(50, self.lcRawSize.width + t.x), MAX(50, self.lcRawSize.height + t.y));

    CGRect f = v.frame;
    f.size = self.lcRawSize;
    NSNumber *guideX = nil, *guideY = nil;
    if (thr > 0) {
        NSArray<NSNumber *> *xs = nil, *ys = nil;
        [self lcPlusLinesX:&xs y:&ys];
        CGFloat dx = 0, dy = 0, lx = 0, ly = 0;
        BOOL sx = LCPlusMagnet(@[@(CGRectGetMaxX(f))], xs, thr, &dx, &lx);
        BOOL sy = LCPlusMagnet(@[@(CGRectGetMaxY(f))], ys, thr, &dy, &ly);
        if (sx) { f.size.width = MAX(50, f.size.width + dx); guideX = @(lx); }
        if (sy) { f.size.height = MAX(50, f.size.height + dy); guideY = @(ly); }
        [self lcPlusSnapStateChanged:(sx ? 1 : 0) | (sy ? 2 : 0)];
    }
    v.frame = f;

    BOOL ended = (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled || g.state == UIGestureRecognizerStateFailed);
    if (!ended) {
        [self lcPlusShowGuidesX:guideX y:guideY];
        [self updateOriginalFrame];
        return YES;
    }
    self.lcPlusTracking = NO;
    self.lcPlusSnapState = 0;
    [self lcPlusShowGuidesX:nil y:nil];
    if (cols > 0) [self lcPlusSnapFrameToGrid];
    else [self lcPlusSmartSnapOnRelease:YES];
    [self updateOriginalFrame];
    [self lcPlusUpdateInsets];
    return YES;
}

// Put the window in one cell (or a span of cells) of a cols x rows grid of the work area
- (void)lcPlusPlaceCols:(NSInteger)cols rows:(NSInteger)rows col:(NSInteger)c row:(NSInteger)r colSpan:(NSInteger)cs rowSpan:(NSInteger)rs {
    __weak typeof(self) weakSelf = self;
    void (^apply)(void) = ^{
        typeof(self) s = weakSelf;
        if (!s || !s.view.window) return;
        CGRect a = LCPlusWorkArea(s.view.window);
        CGFloat cw = a.size.width / cols, ch = a.size.height / rows;
        CGRect f = CGRectMake(a.origin.x + c * cw, a.origin.y + r * ch, cs * cw, rs * ch);
        [UIView animateWithDuration:0.25 animations:^{
            s.view.frame = CGRectIntegral(f);
        }];
        [s updateOriginalFrame];
        [s lcPlusUpdateInsets];
    };
    if (_isMaximized) {
        [self maximizeWindow]; // leave fullscreen first
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), apply);
    } else {
        apply();
    }
}

- (UIMenu *)lcPlusGridMenu:(NSString *)title cols:(NSInteger)cols rows:(NSInteger)rows {
    __weak typeof(self) weakSelf = self;
    NSMutableArray *kids = [NSMutableArray array];
    for (NSInteger r = 0; r < rows; r++) {
        for (NSInteger c = 0; c < cols; c++) {
            NSString *t = rows == 1
                ? [NSString stringWithFormat:@"%ld of %ld", (long)c + 1, (long)cols]
                : [NSString stringWithFormat:@"Row %ld, column %ld", (long)r + 1, (long)c + 1];
            [kids addObject:[UIAction actionWithTitle:t image:nil identifier:nil handler:^(UIAction *action) {
                [weakSelf lcPlusPlaceCols:cols rows:rows col:c row:r colSpan:1 rowSpan:1];
            }]];
        }
    }
    return [UIMenu menuWithTitle:title children:kids];
}

- (UIMenuElement *)lcPlusSnapMenu {
    __weak typeof(self) weakSelf = self;
    UIAction *(^act)(NSString *, NSInteger, NSInteger, NSInteger, NSInteger, NSInteger, NSInteger) =
    ^UIAction *(NSString *title, NSInteger cols, NSInteger rows, NSInteger c, NSInteger r, NSInteger cs, NSInteger rs) {
        return [UIAction actionWithTitle:title image:nil identifier:nil handler:^(UIAction *action) {
            [weakSelf lcPlusPlaceCols:cols rows:rows col:c row:r colSpan:cs rowSpan:rs];
        }];
    };
    NSMutableArray *kids = [NSMutableArray array];
    [kids addObject:[UIAction actionWithTitle:@"Full screen" image:[UIImage systemImageNamed:@"arrow.up.left.and.arrow.down.right"] identifier:nil handler:^(UIAction *action) {
        if (!weakSelf.isMaximized) [weakSelf maximizeWindow];
    }]];
    [kids addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[
        act(@"Left half", 2, 1, 0, 0, 1, 1), act(@"Right half", 2, 1, 1, 0, 1, 1),
        act(@"Top half", 1, 2, 0, 0, 1, 1), act(@"Bottom half", 1, 2, 0, 1, 1, 1),
    ]]];
    [kids addObject:[UIMenu menuWithTitle:@"Thirds" children:@[
        act(@"Left third", 3, 1, 0, 0, 1, 1), act(@"Middle third", 3, 1, 1, 0, 1, 1), act(@"Right third", 3, 1, 2, 0, 1, 1),
        act(@"Left two-thirds", 3, 1, 0, 0, 2, 1), act(@"Right two-thirds", 3, 1, 1, 0, 2, 1),
    ]]];
    [kids addObject:[self lcPlusGridMenu:@"Fourths (4 columns)" cols:4 rows:1]];
    [kids addObject:[self lcPlusGridMenu:@"Quarters (2 × 2)" cols:2 rows:2]];
    [kids addObject:[self lcPlusGridMenu:@"Ninths (3 × 3)" cols:3 rows:3]];
    [kids addObject:[self lcPlusGridMenu:@"Sixteenths (4 × 4)" cols:4 rows:4]];
    if (LCPlusInt(@"LCPlusSnapGrid", 0) == 7) {
        NSInteger cols = 0, rows = 0;
        LCPlusGridDims(&cols, &rows);
        [kids addObject:[self lcPlusGridMenu:[NSString stringWithFormat:@"Custom (%ld × %ld)", (long)cols, (long)rows] cols:cols rows:rows]];
    }
    return [UIMenu menuWithTitle:@"Snap" image:[UIImage systemImageNamed:@"rectangle.split.3x1"] identifier:nil options:0 children:kids];
}

+ (NSArray<DecoratedAppSceneViewController *> *)lcPlusWindowsIncludingHidden:(BOOL)includeHidden {
    NSMutableArray *out = [NSMutableArray array];
    for (UIView *v in MultitaskDockManager.shared.windowHostingView.subviews) {
        if (!includeHidden && (v.hidden || v.alpha < 0.1)) continue;
        if (![v isKindOfClass:UIStackView.class]) continue;
        id vc = ((id (*)(id, SEL))objc_msgSend)(v, NSSelectorFromString(@"_viewDelegate"));
        if ([vc isKindOfClass:DecoratedAppSceneViewController.class]) [out addObject:vc];
    }
    return out;
}

// Arrange every visible window in a grid: the selected snap grid if it is big enough, otherwise automatic
+ (void)lcPlusTileAll {
    NSArray<DecoratedAppSceneViewController *> *wins = [self lcPlusWindowsIncludingHidden:NO];
    NSInteger n = wins.count;
    if (n == 0) return;
    NSInteger cols = 0, rows = 0;
    LCPlusGridDims(&cols, &rows);
    if (cols * rows < n) {
        if (n == 1) { cols = 1; rows = 1; }
        else if (n == 2) { cols = 2; rows = 1; }
        else if (n == 3) { cols = 3; rows = 1; }
        else if (n == 4) { cols = 2; rows = 2; }
        else if (n <= 6) { cols = 3; rows = 2; }
        else if (n <= 9) { cols = 3; rows = 3; }
        else if (n <= 12) { cols = 4; rows = 3; }
        else { cols = 4; rows = 4; }
    }
    for (NSInteger i = 0; i < n; i++) {
        NSInteger c = i % cols, r = i / cols;
        NSInteger span = 1;
        BOOL lastRowIncomplete = (i == n - 1) && (r == (n - 1) / cols);
        if (lastRowIncomplete) span = cols - c; // last window fills the rest of its row
        [wins[i] lcPlusPlaceCols:cols rows:rows col:c row:r colSpan:span rowSpan:1];
    }
}

// The dock was collapsed or expanded: collapsed = windows use the whole screen, expanded = the safe area again.
// Windows are stretched/shrunk with that area so a snapped layout keeps filling it.
+ (void)lcPlusDockCollapseChanged {
    static BOOL wasFull = NO;
    NSArray<DecoratedAppSceneViewController *> *wins = [self lcPlusWindowsIncludingHidden:YES];
    if (wins.count == 0) return;
    UIWindow *w = wins.firstObject.view.window;
    if (!w) return;
    BOOL nowFull = LCPlusFullScreenActive();
    if (nowFull != wasFull) {
        CGRect safe = UIEdgeInsetsInsetRect(w.bounds, w.safeAreaInsets), full = w.bounds;
        CGRect from = wasFull ? full : safe, to = nowFull ? full : safe;
        wasFull = nowFull;
        for (DecoratedAppSceneViewController *vc in wins) {
            if (vc.isMaximized) continue;
            CGRect f = vc.view.frame;
            CGFloat x0 = LCPlusMapCoord(CGRectGetMinX(f), from.origin.x, from.size.width, to.origin.x, to.size.width);
            CGFloat x1 = LCPlusMapCoord(CGRectGetMaxX(f), from.origin.x, from.size.width, to.origin.x, to.size.width);
            CGFloat y0 = LCPlusMapCoord(CGRectGetMinY(f), from.origin.y, from.size.height, to.origin.y, to.size.height);
            CGFloat y1 = LCPlusMapCoord(CGRectGetMaxY(f), from.origin.y, from.size.height, to.origin.y, to.size.height);
            CGRect nf = CGRectIntegral(CGRectMake(x0, y0, MAX(50, x1 - x0), MAX(50, y1 - y0)));
            [UIView animateWithDuration:0.3 animations:^{
                vc.view.frame = nf;
            }];
            [vc updateOriginalFrame];
        }
    }
    for (DecoratedAppSceneViewController *vc in wins) {
        vc.lcPlusInsetsKey = nil;
        [vc lcPlusUpdateInsets];
    }
}

