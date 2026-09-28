#import "Headers.h"

static const void *kASViewKey = &kASViewKey;

%hook _ASDisplayView
%property (nonatomic, assign) _ASDisplayView *currentDownloadButton;
- (void)didMoveToWindow {
    %orig;
    if (objc_getAssociatedObject(self, kASViewKey)) return;
    NSString *iden = self.accessibilityIdentifier;
    YouModApplyOLEDToDisplayView(self, iden);
    YouModConfigureDownloadButton(self, iden);
    YouModSetupDownloadGestures(self, iden);
    if (IS_ENABLED(RemoveAds)) YouModFilterAdsDisplayView(self, iden);
    YouModFilterVideoButtons(self, iden);
    YouModFilterShortsDisplayView(self, iden);
    YouModRemoveShortsPausedButtons(self, iden);
    objc_setAssociatedObject(self, kASViewKey, @YES, OBJC_ASSOCIATION_ASSIGN);
}
%new
- (void)YouModHandleCommentLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;
    YouModHandleCommentLongPressAction(self);
}
%new
- (void)YouModHandlePostLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;
    YouModHandlePostLongPressAction(self);
}
%new
- (void)YouModDownloadButtonTapped:(UITapGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateEnded) return;
    YouModHandleDownloadButtonAction(self);
}
%new
- (void)YouModHandleNewDownloadButtonTapped:(UITapGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateEnded) return;
    YTDefaultSheetController *sheetController = [self.currentDownloadButton._viewControllerForAncestor valueForKey:@"_delegate"];
    _ASDisplayView *moreButton = [sheetController valueForKey:@"_sourceView"];
    [sheetController dismissViewControllerAnimated:YES completion:^{
        YouModHandleDownloadButtonAction(moreButton);
    }];
}
%end

static BOOL isLikeDislikeButtonSeperator(ASDisplayNode *node) {
    int boolCount = 0;
    if (IS_ENABLED(RemoveVideoLikeButton)) boolCount++;
    if (IS_ENABLED(RemoveVideoDislikeButton)) boolCount++;
    if (boolCount == 0 || boolCount == 2) return NO;
    else if ([node.description containsString:@"id.video."] && [node.description hasSuffix:@"like.button"]) return NO;
    NSString *desc = nil;
    @try {
        desc = [[[[[[node nodeController] performSelector:@selector(parent)] performSelector:@selector(parent)] performSelector:@selector(owningComponent)] performSelector:@selector(owningComponent)] description];
    } @catch (id ex) {
        return NO;
    }
    if (desc != nil && [desc containsString:@"segmented_like_dislike_button_inner.eml"]) return YES;
    return NO;
}

%hook ELMContainerNode
- (void)insertYogaChild:(ASDisplayNode *)child atIndex:(NSUInteger)index {
    if (isLikeDislikeButtonSeperator(child)) return;
    %orig;
}
%end

%hook ASCollectionView
- (void)didMoveToWindow {
    %orig;
    if (objc_getAssociatedObject(self, kASViewKey)) return;
    YouModApplyOLEDCollectionView(self, self.accessibilityIdentifier);
    objc_setAssociatedObject(self, kASViewKey, @YES, OBJC_ASSOCIATION_ASSIGN);
}
%end

%hook YTELMViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (objc_getAssociatedObject(self, kASViewKey)) return;
    NSString *desc = [[self valueForKey:@"_renderer"] description];
    // The watermark is an ELM element rendered into one layer, so it has no
    // subview and no identifier to filter on. The renderer name is the only handle.
    if (IS_ENABLED(HideWaterMark) && [desc containsString:@"featured_channel_watermark_overlay.eml"]) {
        self.view.hidden = YES;
    } else if ([desc containsString:@"more_drawer.eml"]) {
        if (IS_ENABLED(RemoveAds)) YouModRemoveDrawerAds(self);
        if (IS_ENABLED(OLEDTheme)) {
            self.view.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traitCollection) {
                return isDarkMode(self.view) ? [UIColor blackColor] : [UIColor whiteColor];
            }];
        }
    } else if (IS_ENABLED(OLEDTheme) && ([desc containsString:@"report_form_reason_select_page.eml"] || [desc containsString:@"report_form_sign_in_page.eml"] || [desc containsString:@"transcript_panel.eml"])) {
        self.view.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traitCollection) {
            return isDarkMode(self.view) ? [UIColor blackColor] : [UIColor clearColor];
        }];
    } else if (IS_ENABLED(OLEDTheme) && [desc containsString:@"timeline_search_input_form_id"] && [desc containsString:@"search_input.eml"]) {
        self.view.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traitCollection) {
            return isDarkMode(self.view) ? [UIColor blackColor] : [UIColor whiteColor];
        }];
    } else if (IS_ENABLED(OLEDTheme) && [desc containsString:@"subs_channel_bar.eml"]) {
        UIView *sub = self.view.subviews[0];
        sub.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traitCollection) {
            return isDarkMode(sub) ? [UIColor blackColor] : [UIColor clearColor];
        }];
    } else if ([desc containsString:@"quick_actions.eml"]) {
        YouModRemoveFullscreenActionsButtons(self);
    }
    objc_setAssociatedObject(self, kASViewKey, @YES, OBJC_ASSOCIATION_ASSIGN);
}
%end