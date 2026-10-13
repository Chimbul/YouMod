#import "Headers.h"

void YouModApplyLiquidGlassToView(UIView *view, BOOL wantsBackground) {
    BOOL success = 0;
    if (wantsBackground && [view respondsToSelector:@selector(tuui_applyFlexibleClearGlassWithShadowBackground)]) {
        [view tuui_applyFlexibleClearGlassWithShadowBackground];
        success = 1;
    } else if (!wantsBackground && [view respondsToSelector:@selector(tuui_applyFlexibleSmallGlassBackground)]) {
        [view tuui_applyFlexibleSmallGlassBackground];
        success = 1;
    }
    if (!success) return;
    for (UIView *sub in view.subviews) {
        if ([sub isKindOfClass:%c(YTFrostedGlassView)]) {
            sub.hidden = YES;
            break;
        }
    }
}

%hook YTChipCloudChipView
- (void)didMoveToWindow {
    %orig;
    YouModApplyLiquidGlassToView(self, YES);
}
%end

%hook YTRightNavigationButtons
- (NSArray <YTQTMButton *> *)visibleButtons {
    NSArray <YTQTMButton *> *orig = %orig;
    if (orig && orig.count > 0) for (YTQTMButton *button in orig) YouModApplyLiquidGlassToView(button, YES);
    return orig;
}
%end

%hook YTMainAppControlsOverlayView
- (void)didMoveToWindow {
    %orig;
    UIView *prevBut = [self valueForKey:@"_previousButtonView"];
    UIView *nextBut = [self valueForKey:@"_nextButtonView"];
    if (prevBut != nil) YouModApplyLiquidGlassToView(prevBut, NO);
    if (nextBut != nil) YouModApplyLiquidGlassToView(nextBut, NO);
    prevBut = [self valueForKey:@"_seekBackwardAccessibilityButtonView"];
    nextBut = [self valueForKey:@"_seekForwardAccessibilityButtonView"];
    if (prevBut != nil) YouModApplyLiquidGlassToView(prevBut, NO);
    if (nextBut != nil) YouModApplyLiquidGlassToView(nextBut, NO);
    YouModApplyLiquidGlassToView(self.playPauseButton, NO);
}
%end

%hook YTInlinePlayerBarContainerView
- (void)didMoveToWindow {
    %orig;
    YouModApplyLiquidGlassToView(self.enterExitFullscreenButton, NO);
    YouModApplyLiquidGlassToView(self.exitFullscreenButton, NO);
    YouModApplyLiquidGlassToView(self.timestampGestureView, NO);
    if (self.liveSyncButton != nil) YouModApplyLiquidGlassToView(self.liveSyncButton, NO);
    // YTLightweightQTMButton *button = ((UIView *)[self valueForKey:@"_chapterTitleFrostedGlassView"]).superview;
    // YouModApplyLiquidGlassToView(button);
}
%end

%hook YTEngagementPanelHeaderView
- (void)didMoveToWindow {
    %orig;
    if (self.informationButton != nil) YouModApplyLiquidGlassToView(self.informationButton, YES);
    if (self.sortFilterMenuButton != nil) YouModApplyLiquidGlassToView(self.sortFilterMenuButton, YES);
    if (self.closeButton != nil) YouModApplyLiquidGlassToView(self.closeButton, YES);
    if (self.backButton != nil) YouModApplyLiquidGlassToView(self.backButton, YES);
    for (UIView *button in self.subviews) {
        if ([button isKindOfClass:%c(YTQTMButton)]) {
            YTIButtonRenderer *renderer = [button valueForKey:@"_buttonRenderer"];
            if (renderer == nil) continue;
            NSString *desc = [renderer description];
            if ([desc containsString:@"FEcommunity_page"] || [desc containsString:@"live_chat_filter_mode_option.eml"]) YouModApplyLiquidGlassToView(button, YES);
        }
    }
}
%end

%hook YTSearchBarView
- (void)didMoveToWindow {
    %orig;
    YouModApplyLiquidGlassToView(self, YES);
}
%end

%hook GSKRedMicButton
- (void)didMoveToWindow {
    %orig;
    YouModApplyLiquidGlassToView(self, NO);
}
%end

%hook YTLeftNavigationButtons
- (void)didMoveToWindow {
    %orig;
    if (self.backButton != nil) YouModApplyLiquidGlassToView(self.backButton, YES);
}
%end