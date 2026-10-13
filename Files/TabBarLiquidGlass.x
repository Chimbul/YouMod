#import "Headers.h"

static NSString * const kYMLiquidGlassCompatibilityKey = @"UIDesignRequiresCompatibility";
static const void *kYMLiquidGlassTabBarStateKey = &kYMLiquidGlassTabBarStateKey;

@interface YMTabBarLiquidGlassState : NSObject
@property (nonatomic, strong) UIVisualEffectView *glassView;
@property (nonatomic, strong) id originalBackgroundColor;
@property (nonatomic, strong) id originalLayerBackgroundColor;
@property (nonatomic, weak) UIView *originalBlurView;
@property (nonatomic, assign) BOOL originalBlurHidden;
@property (nonatomic, assign) BOOL originalOpaque;
@property (nonatomic, assign) BOOL originalClipsToBounds;
@property (nonatomic, assign) BOOL originalMasksToBounds;
@end

@implementation YMTabBarLiquidGlassState
@end

static BOOL YMTabBarLiquidGlassEnabled(void) {
    return INTFORVAL(UseFrostedTabBar) == 1 && NSClassFromString(@"UIGlassEffect") != Nil;
}

static UIVisualEffect *YMCreateTabBarGlassEffect(void) {
    Class effectClass = NSClassFromString(@"UIGlassEffect");
    if (effectClass == Nil) return nil;

    SEL effectSelector = NSSelectorFromString(@"effectWithStyle:");
    Method effectMethod = class_getClassMethod(effectClass, effectSelector);
    if (effectMethod != NULL) {
        IMP implementation = method_getImplementation(effectMethod);
        return ((id (*)(id, SEL, NSInteger))implementation)(effectClass, effectSelector, 0);
    }
    return [[effectClass alloc] init];
}

static UIView *YMTabBarNativeBlurView(YTPivotBarView *bar) {
    SEL blurSelector = NSSelectorFromString(@"blurView");
    Method blurMethod = class_getInstanceMethod([bar class], blurSelector);
    if (blurMethod == NULL) return nil;

    IMP implementation = method_getImplementation(blurMethod);
    return ((id (*)(id, SEL))implementation)(bar, blurSelector);
}

static id YMStoredColor(UIColor *color) {
    return color ?: (id)NSNull.null;
}

static id YMStoredLayerColor(CGColorRef color) {
    return color ? (__bridge id)color : (id)NSNull.null;
}

static void YMRestoreTabBarAppearance(YTPivotBarView *bar, YMTabBarLiquidGlassState *state) {
    id backgroundColor = state.originalBackgroundColor;
    bar.backgroundColor = backgroundColor == NSNull.null ? nil : backgroundColor;

    id layerBackgroundColor = state.originalLayerBackgroundColor;
    bar.layer.backgroundColor = layerBackgroundColor == NSNull.null
        ? nil
        : (__bridge CGColorRef)layerBackgroundColor;
    bar.opaque = state.originalOpaque;
    bar.clipsToBounds = state.originalClipsToBounds;
    bar.layer.masksToBounds = state.originalMasksToBounds;

    UIView *blurView = state.originalBlurView;
    if (blurView != nil) blurView.hidden = state.originalBlurHidden;
}

static void YMUpdateTabBarLiquidGlass(YTPivotBarView *bar, BOOL refreshOriginalAppearance) {
    YMTabBarLiquidGlassState *state = objc_getAssociatedObject(bar, kYMLiquidGlassTabBarStateKey);
    if (!YMTabBarLiquidGlassEnabled()) {
        if (state != nil) {
            [state.glassView removeFromSuperview];
            YMRestoreTabBarAppearance(bar, state);
            objc_setAssociatedObject(bar, kYMLiquidGlassTabBarStateKey, nil,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return;
    }
    UIView *blurView = YMTabBarNativeBlurView(bar);

    if (state == nil) {
        state = [YMTabBarLiquidGlassState new];
        state.originalBackgroundColor = YMStoredColor(bar.backgroundColor);
        state.originalLayerBackgroundColor = YMStoredLayerColor(bar.layer.backgroundColor);
        state.originalOpaque = bar.opaque;
        state.originalClipsToBounds = bar.clipsToBounds;
        state.originalMasksToBounds = bar.layer.masksToBounds;
        objc_setAssociatedObject(bar, kYMLiquidGlassTabBarStateKey, state,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (refreshOriginalAppearance) {
        if (bar.backgroundColor != nil && CGColorGetAlpha(bar.backgroundColor.CGColor) > 0.0) {
            state.originalBackgroundColor = bar.backgroundColor;
        }
        if (bar.layer.backgroundColor != NULL && CGColorGetAlpha(bar.layer.backgroundColor) > 0.0) {
            state.originalLayerBackgroundColor = YMStoredLayerColor(bar.layer.backgroundColor);
        }
    }

    if (blurView != nil && blurView != state.originalBlurView) {
        state.originalBlurView = blurView;
        state.originalBlurHidden = blurView.hidden;
    }

    if (state.glassView == nil) {
        UIVisualEffect *effect = YMCreateTabBarGlassEffect();
        if (effect == nil) {
            [state.glassView removeFromSuperview];
            YMRestoreTabBarAppearance(bar, state);
            objc_setAssociatedObject(bar, kYMLiquidGlassTabBarStateKey, nil,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            return;
        }
        state.glassView = [[UIVisualEffectView alloc] initWithEffect:effect];
        state.glassView.userInteractionEnabled = NO;
        state.glassView.layer.cornerCurve = kCACornerCurveContinuous;
        state.glassView.clipsToBounds = NO;
    }

    blurView.hidden = YES;
    bar.backgroundColor = UIColor.clearColor;
    bar.layer.backgroundColor = UIColor.clearColor.CGColor;
    bar.opaque = NO;
    bar.clipsToBounds = NO;
    bar.layer.masksToBounds = NO;

    if (state.glassView.superview != bar) {
        [state.glassView removeFromSuperview];
        [bar insertSubview:state.glassView atIndex:0];
    } else {
        [bar sendSubviewToBack:state.glassView];
    }

    CGFloat itemHeight = CGRectGetHeight(bar.bounds) - bar.safeAreaInsets.bottom;
    CGFloat glassHeight = MAX(itemHeight, 44.0) + 14.0;
    CGFloat glassTop = MIN(0.0, CGRectGetHeight(bar.bounds) - glassHeight - 4.0);
    CGFloat glassWidth = MAX(0.0, CGRectGetWidth(bar.bounds) - 28.0);
    CGRect glassFrame = CGRectMake((CGRectGetWidth(bar.bounds) - glassWidth) * 0.5,
                                   glassTop, glassWidth, glassHeight);

    state.glassView.frame = glassFrame;
    state.glassView.layer.cornerRadius = CGRectGetHeight(glassFrame) * 0.5;
    state.glassView.alpha = 1.0;
}

__attribute__((constructor)) static void YMEnableLiquidGlassDesign(void) {
    if (!YMTabBarLiquidGlassEnabled()) return;

    id infoDictionary = (__bridge id)CFBundleGetInfoDictionary(CFBundleGetMainBundle());
    if ([infoDictionary isKindOfClass:[NSMutableDictionary class]]) {
        [(NSMutableDictionary *)infoDictionary removeObjectForKey:kYMLiquidGlassCompatibilityKey];
    }
}

%hook NSBundle
- (NSDictionary *)infoDictionary {
    NSDictionary *original = %orig;
    if (self != NSBundle.mainBundle || !YMTabBarLiquidGlassEnabled() ||
        original[kYMLiquidGlassCompatibilityKey] == nil) return original;

    NSMutableDictionary *updated = [original mutableCopy];
    [updated removeObjectForKey:kYMLiquidGlassCompatibilityKey];
    return updated;
}

- (id)objectForInfoDictionaryKey:(NSString *)key {
    if (self == NSBundle.mainBundle && YMTabBarLiquidGlassEnabled() &&
        [key isEqualToString:kYMLiquidGlassCompatibilityKey]) return nil;
    return %orig;
}
%end

%hook YTPivotBarView
- (void)layoutSubviews {
    %orig;
    YMUpdateTabBarLiquidGlass(self, NO);
}

- (void)styleBackgroundColors {
    %orig;
    YMUpdateTabBarLiquidGlass(self, YES);
}

- (void)setBackgroundStyle:(int)style {
    %orig(style);
    YMUpdateTabBarLiquidGlass(self, YES);
}
%end
