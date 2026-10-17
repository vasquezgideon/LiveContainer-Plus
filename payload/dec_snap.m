#pragma mark LC Plus snapping

- (NSArray<NSValue *> *)lcPlusNeighborFrames {
    NSMutableArray *frames = [NSMutableArray array];
    for (UIView *s in self.view.superview.subviews) {
        if (s == self.view || s.hidden || s.alpha < 0.1 || ![s isKindOfClass:UIStackView.class]) continue;
        [frames addObject:[NSValue valueWithCGRect:s.frame]];
    }
    return frames;
}

- (void)lcPlusLinesX:(NSArray<NSNumber *> **)xs y:(NSArray<NSNumber *> **)ys {
    CGRect a = LCPlusWorkArea(self.view.window);
    NSMutableArray *X = [NSMutableArray arrayWithObjects:@(CGRectGetMinX(a)), @(CGRectGetMaxX(a)), nil];
    NSMutableArray *Y = [NSMutableArray arrayWithObjects:@(CGRectGetMinY(a)), @(CGRectGetMaxY(a)), nil];
    if (LCPlusBool(@"LCPlusSnapMid", YES)) {
        [X addObject:@(CGRectGetMidX(a))];
        [Y addObject:@(CGRectGetMidY(a))];
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

// Align the window to the nearest grid cells (called when a move/resize ends and a grid is selected)
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
}

// YES = handled here, NO = fall through to the stock behaviour
- (BOOL)lcPlusHandleMove:(UIPanGestureRecognizer *)g {
    CGFloat thr = LCPlusDouble(@"LCPlusSnapThreshold", 14);
    NSInteger cols = 0, rows = 0;
    LCPlusGridDims(&cols, &rows);
    BOOL edgeDrop = LCPlusBool(@"LCPlusEdgeDrop", YES);
    if (thr <= 0 && cols == 0 && !edgeDrop) return NO;
    if (_isMaximized) return YES;
    UIView *v = self.view;
    if (!v.superview || !v.window) return NO;

    if (g.state == UIGestureRecognizerStateBegan || !self.lcPlusTracking) {
        self.lcRawOrigin = v.frame.origin;
        self.lcPlusTracking = YES;
    }
    CGPoint t = [g translationInView:v];
    [g setTranslation:CGPointZero inView:v];
    self.lcRawOrigin = CGPointMake(self.lcRawOrigin.x + t.x, self.lcRawOrigin.y + t.y);

    CGRect f = v.frame;
    f.origin = self.lcRawOrigin;
    if (thr > 0) {
        NSArray<NSNumber *> *xs = nil, *ys = nil;
        [self lcPlusLinesX:&xs y:&ys];
        CGFloat dx = LCPlusMagnet(@[@(CGRectGetMinX(f)), @(CGRectGetMaxX(f)), @(CGRectGetMidX(f))], xs, thr);
        CGFloat dy = LCPlusMagnet(@[@(CGRectGetMinY(f)), @(CGRectGetMaxY(f))], ys, thr);
        f.origin.x += dx;
        f.origin.y += dy;
    }
    v.frame = f;

    BOOL ended = (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled || g.state == UIGestureRecognizerStateFailed);
    if (ended) {
        self.lcPlusTracking = NO;
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
        if (!placed && cols > 0) [self lcPlusSnapFrameToGrid];
    }
    [self updateOriginalFrame];
    return YES;
}

- (BOOL)lcPlusHandleResize:(UIPanGestureRecognizer *)g {
    CGFloat thr = LCPlusDouble(@"LCPlusSnapThreshold", 14);
    NSInteger cols = 0, rows = 0;
    LCPlusGridDims(&cols, &rows);
    if (thr <= 0 && cols == 0) return NO;
    if (_isMaximized) return YES;
    UIView *v = self.view;
    if (!v.superview || !v.window) return NO;

    if (g.state == UIGestureRecognizerStateBegan || !self.lcPlusTracking) {
        self.lcRawSize = v.frame.size;
        self.lcPlusTracking = YES;
    }
    CGPoint t = [g translationInView:v];
    [g setTranslation:CGPointZero inView:v];
    self.lcRawSize = CGSizeMake(MAX(50, self.lcRawSize.width + t.x), MAX(50, self.lcRawSize.height + t.y));

    CGRect f = v.frame;
    f.size = self.lcRawSize;
    if (thr > 0) {
        NSArray<NSNumber *> *xs = nil, *ys = nil;
        [self lcPlusLinesX:&xs y:&ys];
        CGFloat dx = LCPlusMagnet(@[@(CGRectGetMaxX(f))], xs, thr);
        CGFloat dy = LCPlusMagnet(@[@(CGRectGetMaxY(f))], ys, thr);
        f.size.width = MAX(50, f.size.width + dx);
        f.size.height = MAX(50, f.size.height + dy);
    }
    v.frame = f;

    if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled || g.state == UIGestureRecognizerStateFailed) {
        self.lcPlusTracking = NO;
        if (cols > 0) [self lcPlusSnapFrameToGrid];
    }
    [self updateOriginalFrame];
    return YES;
}

// Put the window in one cell (or a span of cells) of a cols x rows grid
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
    [kids addObject:[self lcPlusGridMenu:@"Quarters (2 x 2)" cols:2 rows:2]];
    [kids addObject:[self lcPlusGridMenu:@"Ninths (3 x 3)" cols:3 rows:3]];
    [kids addObject:[self lcPlusGridMenu:@"Sixteenths (4 x 4)" cols:4 rows:4]];
    if (LCPlusInt(@"LCPlusSnapGrid", 0) == 7) {
        NSInteger cols = 0, rows = 0;
        LCPlusGridDims(&cols, &rows);
        [kids addObject:[self lcPlusGridMenu:[NSString stringWithFormat:@"Custom (%ld x %ld)", (long)cols, (long)rows] cols:cols rows:rows]];
    }
    return [UIMenu menuWithTitle:@"Snap" image:[UIImage systemImageNamed:@"rectangle.split.3x1"] identifier:nil options:0 children:kids];
}

+ (NSArray<DecoratedAppSceneViewController *> *)lcPlusVisibleWindows {
    NSMutableArray *out = [NSMutableArray array];
    for (UIView *v in MultitaskDockManager.shared.windowHostingView.subviews) {
        if (v.hidden || v.alpha < 0.1) continue;
        id vc = ((id (*)(id, SEL))objc_msgSend)(v, NSSelectorFromString(@"_viewDelegate"));
        if ([vc isKindOfClass:DecoratedAppSceneViewController.class]) [out addObject:vc];
    }
    return out;
}

// Arrange every visible window in a grid: the selected snap grid if it is big enough, otherwise automatic
+ (void)lcPlusTileAll {
    NSArray<DecoratedAppSceneViewController *> *wins = [self lcPlusVisibleWindows];
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

