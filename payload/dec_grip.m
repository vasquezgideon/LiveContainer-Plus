#pragma mark - LC Plus window bar grip (added by LC Plus)

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self lcPlusSyncGrip];
}

// When the window bar is hidden (dock collapsed) a thin strip at the top keeps the window movable.
// Drag it to move, double-tap it to show the bar again.
- (void)lcPlusSyncGrip {
    BOOL barHidden = self.navigationBar.hidden || self.navigationBar.alpha < 0.01;
    BOOL need = barHidden && !_isMaximized;
    UIView *grip = [self.view viewWithTag:kLCPlusGripTag];
    if (!need) {
        [grip removeFromSuperview];
        return;
    }
    if (grip) return;

    grip = [UIView new];
    grip.tag = kLCPlusGripTag;
    grip.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *pill = [UIView new];
    pill.translatesAutoresizingMaskIntoConstraints = NO;
    pill.userInteractionEnabled = NO;
    pill.backgroundColor = [UIColor colorWithWhite:1 alpha:0.55];
    pill.layer.cornerRadius = 2;
    pill.layer.shadowColor = UIColor.blackColor.CGColor;
    pill.layer.shadowOpacity = 0.5;
    pill.layer.shadowRadius = 1.5;
    pill.layer.shadowOffset = CGSizeZero;
    [grip addSubview:pill];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(moveWindow:)];
    pan.maximumNumberOfTouches = 1;
    [grip addGestureRecognizer:pan];
    UITapGestureRecognizer *dbl = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(lcPlusGripDoubleTap:)];
    dbl.numberOfTapsRequired = 2;
    [grip addGestureRecognizer:dbl];

    [self.view addSubview:grip];
    [NSLayoutConstraint activateConstraints:@[
        [grip.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [grip.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [grip.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [grip.heightAnchor constraintEqualToConstant:22],
        [pill.centerXAnchor constraintEqualToAnchor:grip.centerXAnchor],
        [pill.topAnchor constraintEqualToAnchor:grip.topAnchor constant:5],
        [pill.widthAnchor constraintEqualToConstant:40],
        [pill.heightAnchor constraintEqualToConstant:4],
    ]];
}

- (void)lcPlusGripDoubleTap:(UITapGestureRecognizer *)g {
    // temporarily show the bar for this window: expand the dock, which re-shows every bar
    if (MultitaskDockManager.shared.isCollapsed) {
        [MultitaskDockManager.shared toggleDockCollapse];
    }
}

