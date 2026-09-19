// FakeLocation.m - makes an app think it has location permission and feeds it a fixed position.
// Edit the constants below, build to FakeLocation.dylib, and inject it via LiveContainer.

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <objc/runtime.h>

// ===== CONFIG =====
static const double kLat    = 51.5074;   // latitude
static const double kLon    = -0.1278;   // longitude
static const double kAlt    = 30.0;      // meters
static const double kAcc    = 10.0;      // horizontal accuracy, meters
static const double kJitter = 0.00003;   // random wobble in degrees (~3 m); 0 for none
static const NSTimeInterval kInterval = 2.0; // seconds between updates
// ==================

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static const void *kTimerKey = &kTimerKey;

static CLLocation *FakeLoc(void) {
    double j1 = kJitter ? ((arc4random_uniform(2001) / 1000.0) - 1.0) * kJitter : 0;
    double j2 = kJitter ? ((arc4random_uniform(2001) / 1000.0) - 1.0) * kJitter : 0;
    return [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(kLat + j1, kLon + j2)
                                         altitude:kAlt
                               horizontalAccuracy:kAcc
                                 verticalAccuracy:5.0
                                           course:-1
                                            speed:0
                                        timestamp:[NSDate date]];
}

static void Deliver(CLLocationManager *m) {
    id<CLLocationManagerDelegate> d = m.delegate;
    if ([d respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
        [d locationManager:m didUpdateLocations:@[FakeLoc()]];
    }
}

static void NotifyAuth(CLLocationManager *m) {
    dispatch_async(dispatch_get_main_queue(), ^{
        id d = m.delegate;
        if ([d respondsToSelector:@selector(locationManagerDidChangeAuthorization:)]) {
            [d locationManagerDidChangeAuthorization:m];
        }
        if ([d respondsToSelector:@selector(locationManager:didChangeAuthorizationStatus:)]) {
            [d locationManager:m didChangeAuthorizationStatus:kCLAuthorizationStatusAuthorizedWhenInUse];
        }
    });
}

static void StopTimer(CLLocationManager *m) {
    NSTimer *t = objc_getAssociatedObject(m, kTimerKey);
    [t invalidate];
    objc_setAssociatedObject(m, kTimerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void StartUpdates(CLLocationManager *m) {
    StopTimer(m);
    dispatch_async(dispatch_get_main_queue(), ^{ Deliver(m); });
    __weak CLLocationManager *weakM = m;
    NSTimer *t = [NSTimer scheduledTimerWithTimeInterval:kInterval repeats:YES block:^(NSTimer *timer) {
        CLLocationManager *strongM = weakM;
        if (!strongM) { [timer invalidate]; return; }
        Deliver(strongM);
    }];
    objc_setAssociatedObject(m, kTimerKey, t, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void Replace(Class cls, BOOL classMethod, SEL sel, id block) {
    Class target = classMethod ? object_getClass(cls) : cls;
    Method orig = classMethod ? class_getClassMethod(cls, sel) : class_getInstanceMethod(cls, sel);
    const char *types = orig ? method_getTypeEncoding(orig) : NULL;
    if (!types) return; // method doesn't exist on this iOS version
    class_replaceMethod(target, sel, imp_implementationWithBlock(block), types);
}

__attribute__((constructor))
static void FakeLocationInit(void) {
    Class C = [CLLocationManager class];

    // Authorization state
    Replace(C, YES, @selector(authorizationStatus), ^CLAuthorizationStatus(id s) {
        return kCLAuthorizationStatusAuthorizedWhenInUse;
    });
    Replace(C, NO, @selector(authorizationStatus), ^CLAuthorizationStatus(id s) {
        return kCLAuthorizationStatusAuthorizedWhenInUse;
    });
    Replace(C, YES, @selector(locationServicesEnabled), ^BOOL(id s) { return YES; });
    Replace(C, NO, @selector(accuracyAuthorization), ^CLAccuracyAuthorization(id s) {
        return CLAccuracyAuthorizationFullAccuracy;
    });

    // Permission requests become no-ops that report "granted"
    Replace(C, NO, @selector(requestWhenInUseAuthorization), ^(CLLocationManager *m) { NotifyAuth(m); });
    Replace(C, NO, @selector(requestAlwaysAuthorization), ^(CLLocationManager *m) { NotifyAuth(m); });

    // Location delivery
    Replace(C, NO, @selector(location), ^CLLocation *(id s) { return FakeLoc(); });
    Replace(C, NO, @selector(startUpdatingLocation), ^(CLLocationManager *m) { StartUpdates(m); });
    Replace(C, NO, @selector(startMonitoringSignificantLocationChanges), ^(CLLocationManager *m) { StartUpdates(m); });
    Replace(C, NO, @selector(stopUpdatingLocation), ^(CLLocationManager *m) { StopTimer(m); });
    Replace(C, NO, @selector(stopMonitoringSignificantLocationChanges), ^(CLLocationManager *m) { StopTimer(m); });
    Replace(C, NO, @selector(requestLocation), ^(CLLocationManager *m) {
        dispatch_async(dispatch_get_main_queue(), ^{ Deliver(m); });
    });
}
