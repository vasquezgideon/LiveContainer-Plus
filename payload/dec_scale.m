#pragma mark - LC Plus default scale (added by LC Plus)

- (void)lcPlusApplyInitialScale {
    double r = MAX(0.5, MIN(2.0, LCPlusDouble(@"LCPlusDefaultScale", 1.0)));
    if (fabs(r - 1.0) < 0.001 || fabs(_scaleRatio - 1.0) > 0.001) return;
    self.scaleRatio = r;
    self.appSceneVC.scaleRatio = r;
    if (self.appSceneVC.usesHostingControllerAPI) {
        self.appSceneVC.contentView.transform = CGAffineTransformMakeScale(r, r);
    } else {
        self.appSceneVC.contentView.layer.sublayerTransform = CATransform3DMakeScale(r, r, 1.0);
    }
}

