// LCPlus Spatial Workspace — inserted at file scope in DecoratedAppSceneViewController.m.
// This deliberately manipulates the *host* virtual-window layer. LiveProcess guest
// surfaces are already hosted inside this layer; no guest binary injection is needed.
// This is a MONOSCOPIC, rotational 2D viewport, not a stereo VR runtime.
@import CoreMotion;
@import GameController;
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <fcntl.h>
#import <unistd.h>
#import <math.h>

// A relative quaternion removes a fixed Joy-Con mounting angle (including a
// controller strapped sideways). We still need a functioning GCMotion attitude
// stream; this does not expose hidden Bluetooth gyro packets on iOS.
static GCQuaternion LCPlusSpatialMultiplyQuaternion(GCQuaternion a, GCQuaternion b) {
    GCQuaternion r;
    r.x = a.w*b.x + a.x*b.w + a.y*b.z - a.z*b.y;
    r.y = a.w*b.y - a.x*b.z + a.y*b.w + a.z*b.x;
    r.z = a.w*b.z + a.x*b.y - a.y*b.x + a.z*b.w;
    r.w = a.w*b.w - a.x*b.x - a.y*b.y - a.z*b.z;
    return r;
}

@interface LCPlusSpatialRig : NSObject
@property(nonatomic, weak) UIView *workspace;
@property(nonatomic, strong) CADisplayLink *clock;
@property(nonatomic, strong) CMMotionManager *motion;
@property(nonatomic) BOOL centered;
@property(nonatomic) double centerYaw, centerPitch;
@property(nonatomic) double yaw, pitch;
@property(nonatomic) BOOL hasExternalSample, externalWorn, wornKnown;
@property(nonatomic) NSInteger lastRecenter;
@property(nonatomic) NSInteger lastSource;
@property(nonatomic) NSInteger lastControllerIndex;
@property(nonatomic) NSTimeInterval lastExternalSample;
@property(nonatomic) int socketFD;
@property(nonatomic) BOOL controllerSampleReady;
@property(nonatomic) BOOL hasControllerReference;
@property(nonatomic) GCQuaternion controllerReference;
@property(nonatomic) NSTimeInterval lastControllerPoll;
@property(nonatomic, strong) GCController *activeController;
@property(nonatomic, strong) UIView *stereoOverlay;
@property(nonatomic, strong) UIImageView *leftEye;
@property(nonatomic, strong) UIImageView *rightEye;
@property(nonatomic) NSTimeInterval lastCapture;
@property(nonatomic) NSInteger lastRenderMode;
@property(nonatomic) BOOL trackingReady;
@property(nonatomic) BOOL waitingForDisplay;
+ (instancetype)shared;
- (void)attachWorkspace:(UIView *)view;
- (void)tick:(CADisplayLink *)link;
@end

@implementation LCPlusSpatialRig
+ (instancetype)shared {
    static LCPlusSpatialRig *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [LCPlusSpatialRig new]; });
    return s;
}
- (instancetype)init {
    if ((self = [super init])) {
        _socketFD = -1;
        _motion = [CMMotionManager new];
        _motion.deviceMotionUpdateInterval = 1.0 / 60.0;
        _lastRecenter = NSIntegerMin;
        _lastSource = -1;
        _lastControllerIndex = -1;
        _lastRenderMode = -1;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onDisplayChanged:)
                                                     name:UIScreenDidConnectNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onDisplayChanged:)
                                                     name:UIScreenDidDisconnectNotification object:nil];
    }
    return self;
}
- (void)attachWorkspace:(UIView *)view {
    if (!view) return;
    if (self.workspace != view) {
        // Avoid leaving a transformed view behind if the workspace gets replaced.
        self.workspace.transform = CGAffineTransformIdentity;
        [self removeStereoOverlay];
        self.workspace = view;
        [self recenter];
    }
    if (!self.clock) {
        self.clock = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
        self.clock.preferredFramesPerSecond = 60;
        [self.clock addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
}
- (void)recenter {
    // Subsequent valid sample sets the selected tracker's "straight ahead".
    // Clear both Euler and quaternion baselines to also cover side mounting.
    self.centered = NO;
    self.hasControllerReference = NO;
}
- (void)onDisplayChanged:(NSNotification *)event { (void)event; [self recenter]; }
- (void)closeSocket {
    if (self.socketFD >= 0) { close(self.socketFD); self.socketFD = -1; }
    self.hasExternalSample = NO;
    self.wornKnown = NO;
}
- (void)openSocket {
    if (self.socketFD >= 0) return;
    NSInteger port = [NSUserDefaults.lcSharedDefaults integerForKey:@"LCPlusSpatialPort"];
    if (port < 1024 || port > 65535) port = 38271;
    int fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (fd < 0) return;
    int opt = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK);
    struct sockaddr_in addr = {0};
    addr.sin_family = AF_INET;
    addr.sin_port = htons((uint16_t)port);
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) { close(fd); return; }
    self.socketFD = fd;
}
- (void)pollExternal {
    [self openSocket];
    if (self.socketFD < 0) return;
    // Drain at most 8 datagrams per frame. Drop oversized or malformed packets.
    for (int i = 0; i < 8; i++) {
        char buf[513];
        ssize_t n = recv(self.socketFD, buf, sizeof(buf), MSG_DONTWAIT);
        if (n <= 0) break;
        if (n > 512) continue;
        NSData *data = [NSData dataWithBytes:buf length:(NSUInteger)n];
        NSDictionary *msg = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![msg isKindOfClass:NSDictionary.class]) continue;
        id y = msg[@"yaw"], p = msg[@"pitch"];
        if (![y isKindOfClass:NSNumber.class] || ![p isKindOfClass:NSNumber.class]) continue;
        double yaw = [y doubleValue], pitch = [p doubleValue];
        if (!isfinite(yaw) || !isfinite(pitch) || fabs(yaw) > 360000 || fabs(pitch) > 360000) continue;
        self.yaw = yaw * M_PI / 180.0;
        self.pitch = pitch * M_PI / 180.0;
        self.hasExternalSample = YES;
        self.lastExternalSample = NSProcessInfo.processInfo.systemUptime;
        id worn = msg[@"worn"];
        if ([worn isKindOfClass:NSNumber.class]) {
            BOOL nowWorn = [worn boolValue];
            // Only the external tracker can supply real wear status. A display
            // connection alone does NOT prove the user has taken glasses off.
            if (nowWorn && self.wornKnown && !self.externalWorn) [self recenter];
            self.wornKnown = YES;
            self.externalWorn = nowWorn;
        }
    }
}

// GameController is the only public controller-gyro path used here. No raw HID
// or Bluetooth-private API. A connected Joy-Con may expose *no* GCMotion.
- (void)pollControllerAtIndex:(NSInteger)idx {
    NSArray<GCController *> *devices = GCController.controllers;
    if (idx < 0 || idx >= (NSInteger)devices.count) {
        self.controllerSampleReady = NO;
        self.activeController = nil;
        return;
    }
    GCController *c = devices[(NSUInteger)idx];
    GCMotion *m = c.motion;
    if (!m || (!m.hasAttitude && !m.hasRotationRate)) {
        self.controllerSampleReady = NO;
        self.activeController = nil;
        return;
    }
    if (self.activeController != c) {
        self.activeController = c;
        self.controllerSampleReady = NO;
        self.lastControllerPoll = 0;
        self.yaw = 0; self.pitch = 0;
        if (m.sensorsRequireManualActivation) m.sensorsActive = YES;
        [self recenter];
    }
    if (m.hasAttitude) {
        // Quaternion -> yaw and pitch in radians.  Controller orientation depends
        // on how it is strapped to the glasses: zero/heading are relative only.
        GCQuaternion q = m.attitude;
        double norm = sqrt(q.x*q.x + q.y*q.y + q.z*q.z + q.w*q.w);
        if (!isfinite(norm) || norm < 0.5) return;
        GCQuaternion current = { .x=q.x/norm, .y=q.y/norm,
                                 .z=q.z/norm, .w=q.w/norm };
        if (!self.hasControllerReference) {
            self.controllerReference = current;
            self.hasControllerReference = YES;
        }
        // The reference is the controller's attitude while the user looks
        // forward. Relative orientation cancels a constant mounting rotation.
        GCQuaternion base = self.controllerReference;
        GCQuaternion conjugate = { .x=-base.x, .y=-base.y,
                                   .z=-base.z, .w=base.w };
        GCQuaternion delta = LCPlusSpatialMultiplyQuaternion(current, conjugate);
        double x=delta.x, y=delta.y, z=delta.z, w=delta.w;
        self.yaw = atan2(2*(w*z+x*y), 1-2*(y*y+z*z));
        self.pitch = asin(MAX(-1.0, MIN(1.0, 2*(w*y-z*x))));
    } else {
        // Some controllers publish angular velocity but no orientation. Basic
        // gyro integration is possible, but it will drift; recenter regularly.
        NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
        double dt = self.lastControllerPoll > 0 ? MIN(0.1, MAX(0, now-self.lastControllerPoll)) : 0;
        GCRotationRate rate = m.rotationRate; // radians/second
        if (!isfinite(rate.x) || !isfinite(rate.z)) return;
        self.yaw += rate.z * dt;
        self.pitch += rate.x * dt;
        self.lastControllerPoll = now;
    }
    self.controllerSampleReady = YES;
}
- (void)pollXrealController {
    NSArray<GCController *> *devices = GCController.controllers;
    for (NSInteger i = 0; i < (NSInteger)devices.count; i++) {
        NSString *name = [devices[(NSUInteger)i].vendorName lowercaseString] ?: @"";
        if ([name containsString:@"xreal"] || [name containsString:@"nreal"]) {
            [self pollControllerAtIndex:i];
            return;
        }
    }
    self.controllerSampleReady = NO;
    self.activeController = nil;
}
- (void)removeStereoOverlay {
    [self.stereoOverlay removeFromSuperview];
    self.stereoOverlay = nil;
    self.leftEye = nil;
    self.rightEye = nil;
    self.lastCapture = 0;
}
- (void)ensureStereoOverlay {
    UIView *host = self.workspace.superview;
    if (!host) return;
    if (self.stereoOverlay.superview != host) {
        [self removeStereoOverlay];
        UIView *v = [[UIView alloc] initWithFrame:host.bounds];
        v.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        v.userInteractionEnabled = NO;
        v.backgroundColor = UIColor.blackColor;
        v.clipsToBounds = YES;
        UIImageView *l = [UIImageView new];
        UIImageView *r = [UIImageView new];
        for (UIImageView *eye in @[l,r]) {
            eye.contentMode = UIViewContentModeScaleAspectFit;
            eye.clipsToBounds = YES;
            [v addSubview:eye];
        }
        // Add ABOVE just the multitask workspace. Touches still reach the
        // guest UIView because this overlay is non-interactive.
        [host insertSubview:v aboveSubview:self.workspace];
        self.stereoOverlay = v;
        self.leftEye = l;
        self.rightEye = r;
        self.lastCapture = 0;
    }
}
- (void)drawStereoYaw:(double)dyaw pitch:(double)dpitch sensitivity:(double)sensitivity {
    [self ensureStereoOverlay];
    UIView *v = self.stereoOverlay;
    if (!v) return;
    CGFloat w = v.bounds.size.width, h = v.bounds.size.height;
    if (w <= 1 || h <= 1) return;
    // Side-by-side *flat screen at a virtual distance*, not reconstructed 3D.
    // Each eye receives a view of the same 2D surface with tiny parallax.
    CGFloat eyeWidth = w / 2.0;
    double separation = [NSUserDefaults.lcSharedDefaults objectForKey:@"LCPlusSpatialEyeSeparation"] ?
        [NSUserDefaults.lcSharedDefaults doubleForKey:@"LCPlusSpatialEyeSeparation"] : 0.028;
    separation = MAX(0, MIN(0.08, separation));
    CGFloat disparity = eyeWidth * separation;
    CGFloat px = (CGFloat)MAX(-0.8, MIN(0.8, dyaw / (46.0 * M_PI / 180.0))) * eyeWidth * sensitivity;
    CGFloat py = (CGFloat)MAX(-0.8, MIN(0.8, dpitch / (46.0 * M_PI / 180.0))) * h * sensitivity;
    self.leftEye.frame = CGRectMake(-px - disparity/2, py, eyeWidth, h);
    self.rightEye.frame = CGRectMake(eyeWidth - px + disparity/2, py, eyeWidth, h);
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    // Capture at most 15 fps.  iOS remote hosted views can be blank when
    // drawViewHierarchy is used: this is a test mode, not a guaranteed capture.
    if (now - self.lastCapture < 1.0/15.0) return;
    self.lastCapture = now;
    UIView *workspace = self.workspace;
    CGSize size = workspace.bounds.size;
    if (size.width < 1 || size.height < 1) return;
    UIGraphicsImageRendererFormat *f = [UIGraphicsImageRendererFormat defaultFormat];
    f.scale = 1.0; f.opaque = NO;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:f];
    UIImage *frame = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        // Capture the shared window host, not the overlay that displays it.
        // drawViewHierarchy can omit some remotely hosted LiveProcess surfaces.
        [workspace drawViewHierarchyInRect:(CGRect){CGPointZero, size} afterScreenUpdates:NO];
    }];
    self.leftEye.image = frame;
    self.rightEye.image = frame;
}

- (void)tick:(CADisplayLink *)link {
    (void)link;
    UIView *view = self.workspace;
    if (!view) return;
    NSUserDefaults *defaults = NSUserDefaults.lcSharedDefaults;
    BOOL enabled = [defaults boolForKey:@"LCPlusSpatialEnabled"];
    BOOL requireDisplay = [defaults objectForKey:@"LCPlusSpatialRequireDisplay"] ?
        [defaults boolForKey:@"LCPlusSpatialRequireDisplay"] : YES;
    BOOL present = UIScreen.screens.count > 1;
    NSInteger nonce = [defaults integerForKey:@"LCPlusSpatialRecenter"];
    if (nonce != self.lastRecenter) { self.lastRecenter = nonce; [self recenter]; }
    if (!enabled || (requireDisplay && !present)) {
        if (!CGAffineTransformIsIdentity(view.transform)) view.transform = CGAffineTransformIdentity;
        if (self.motion.deviceMotionActive) [self.motion stopDeviceMotionUpdates];
        [self closeSocket];
        [self removeStereoOverlay];
        self.activeController = nil;
        [self recenter];
        return;
    }
    NSInteger renderMode = [defaults integerForKey:@"LCPlusSpatialRenderMode"];
    if (renderMode != self.lastRenderMode) {
        self.lastRenderMode = renderMode;
        [self removeStereoOverlay];
        [self recenter];
    }
    NSInteger source = [defaults integerForKey:@"LCPlusSpatialTrackingSource"];
    if (source != self.lastSource) {
        self.lastSource = source;
        [self recenter];
        [self closeSocket];
        self.activeController = nil;
        [self removeStereoOverlay];
    }
    if (source == 1) {
        if (self.motion.deviceMotionActive) [self.motion stopDeviceMotionUpdates];
        [self pollExternal];
        if (!self.hasExternalSample || NSProcessInfo.processInfo.systemUptime - self.lastExternalSample > 2.0 ||
            (self.wornKnown && !self.externalWorn)) {
            [self removeStereoOverlay];
            view.transform = CGAffineTransformIdentity;
            return;
        }
    } else if (source == 2) {
        if (self.motion.deviceMotionActive) [self.motion stopDeviceMotionUpdates];
        [self closeSocket];
        NSInteger idx = [defaults integerForKey:@"LCPlusSpatialControllerIndex"];
        if (idx != self.lastControllerIndex) {
            self.lastControllerIndex = idx;
            self.activeController = nil;
            [self recenter];
        }
        [self pollControllerAtIndex:idx];
        if (!self.controllerSampleReady) {
            [self removeStereoOverlay];
            view.transform = CGAffineTransformIdentity;
            return;
        }
    } else if (source == 3) {
        // Experimental discovery only: no raw USB HID access or fake samples.
        if (self.motion.deviceMotionActive) [self.motion stopDeviceMotionUpdates];
        [self closeSocket];
        [self pollXrealController];
        if (!self.controllerSampleReady) {
            [self removeStereoOverlay];
            view.transform = CGAffineTransformIdentity;
            return;
        }
    } else {
        [self closeSocket];
        if (!self.motion.deviceMotionActive && self.motion.deviceMotionAvailable) {
            [self.motion startDeviceMotionUpdates];
            [self recenter];
        }
        CMDeviceMotion *sample = self.motion.deviceMotion;
        if (!sample) return;
        self.yaw = sample.attitude.yaw;
        self.pitch = sample.attitude.pitch;
    }
    if (!self.centered) {
        self.centerYaw = self.yaw;
        self.centerPitch = self.pitch;
        self.centered = YES;
    }
    // Wrapped radians avoid 360-degree jumps around the yaw boundary.
    double dyaw = atan2(sin(self.yaw - self.centerYaw), cos(self.yaw - self.centerYaw));
    double dpitch = atan2(sin(self.pitch - self.centerPitch), cos(self.pitch - self.centerPitch));
    double sensitivity = [defaults objectForKey:@"LCPlusSpatialSensitivity"] ?
        [defaults doubleForKey:@"LCPlusSpatialSensitivity"] : 1.0;
    sensitivity = MAX(0.2, MIN(3.0, sensitivity));
    CGFloat w = view.bounds.size.width, h = view.bounds.size.height;
    if (w < 1 || h < 1) return;
    // An approximately 46-degree XREAL Air FOV converted to pan in screen points.
    CGFloat tx = (CGFloat)MAX(-w, MIN(w, -dyaw / (46.0 * M_PI / 180.0) * w * sensitivity));
    CGFloat ty = (CGFloat)MAX(-h, MIN(h, dpitch / (46.0 * M_PI / 180.0) * h * sensitivity));
    // Transform the entire hosting view, not individual guest windows. This
    // preserves the virtual window layout and UIKit hit-testing translations.
    if (renderMode == 1) {
        // In SBS mode, keep the source view unchanged so UIKit input remains
        // aligned.  The overlay is a render-only visual surface.
        view.transform = CGAffineTransformIdentity;
        [self drawStereoYaw:dyaw pitch:dpitch sensitivity:sensitivity];
    } else {
        [self removeStereoOverlay];
        view.transform = CGAffineTransformMakeTranslation(tx, ty);
    }
}
@end
