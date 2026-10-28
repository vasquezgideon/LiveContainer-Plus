// Inserted into LCBootstrap.m before guest entry point execution.
// Best effort: reactivates the external display coordinator after an ordinary
// app's UIKit application delegate becomes active in the LiveContainer process.
// No guest app view, touch, or lifecycle methods are replaced.
static void LCPlusSpatialGuestDidActivate(NSNotification *note) {
    (void)note;
    Class bridge = NSClassFromString(@"LCPlusSpatialBootstrap");
    SEL sel = NSSelectorFromString(@"activate");
    if (!bridge || ![bridge respondsToSelector:sel]) return;
    IMP implementation = [bridge methodForSelector:sel];
    if (implementation) ((void (*)(id, SEL))implementation)(bridge, sel);
}
__attribute__((constructor)) static void LCPlusSpatialInstallGuestActivation(void) {
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
        object:nil queue:[NSOperationQueue mainQueue]
        usingBlock:^(NSNotification *note) {
            LCPlusSpatialGuestDidActivate(note);
        }];
}
