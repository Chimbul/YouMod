#import "Headers.h"
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import <CoreMedia/CoreMedia.h>
#import <Photos/Photos.h>
#import <math.h>

// YMLibrary.x — the Download Library tab: a YouTube-feed-style grid of
// everything sitting in YouModDownloadsDirectoryURL() (every file a download
// already lands in, regardless of destination). A UICollectionView with a
// width-driven column count (YMLibraryGridLayout) — 1 column on iPhone, 2 on
// iPad portrait, 3 on iPad landscape, and anything in between for Split View/
// Stage Manager, since it reacts to actual width rather than device idiom.

static NSSet<NSString *> *ymLibraryMediaExtensions(void) {
    static NSSet<NSString *> *exts;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ exts = [NSSet setWithObjects:@"mp4", @"mkv", @"m4a", @"mka", nil]; });
    return exts;
}

static BOOL ymIsAudioOnlyExtension(NSString *extension) {
    NSString *lower = extension.lowercaseString;
    return [lower isEqualToString:@"m4a"] || [lower isEqualToString:@"mka"];
}

// Strips the " [videoID]" suffix YMDownload.x appends to every filename for
// uniqueness — the file on disk keeps it, the feed just shouldn't show it.
static NSString *ymDisplayTitleForFileName(NSString *baseName) {
    NSRange range = [baseName rangeOfString:@" \\[[A-Za-z0-9_-]{11}\\]$" options:NSRegularExpressionSearch];
    if (range.location != NSNotFound) {
        return [baseName stringByReplacingCharactersInRange:range withString:@""];
    }
    return baseName;
}

// The other half of the above: pulls the video ID back out instead of
// stripping it. nil for anything downloaded before the ID suffix existed.
static NSString *ymVideoIDForFileName(NSString *baseName) {
    NSRange range = [baseName rangeOfString:@" \\[[A-Za-z0-9_-]{11}\\]$" options:NSRegularExpressionSearch];
    if (range.location == NSNotFound) return nil;
    return [baseName substringWithRange:NSMakeRange(range.location + 2, 11)];
}

static NSString *ymFormattedFileSize(unsigned long long bytes) {
    NSByteCountFormatter *formatter = [NSByteCountFormatter new];
    formatter.countStyle = NSByteCountFormatterCountStyleFile;
    return [formatter stringFromByteCount:(long long)bytes];
}

static NSArray<NSURL *> *ymLibraryFileURLsNewestFirst(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSURL *> *contents = [fm contentsOfDirectoryAtURL:YouModDownloadsDirectoryURL()
                                    includingPropertiesForKeys:@[NSURLContentModificationDateKey]
                                                       options:NSDirectoryEnumerationSkipsHiddenFiles
                                                         error:nil];
    NSSet<NSString *> *mediaExts = ymLibraryMediaExtensions();
    contents = [contents filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSURL *url, NSDictionary *bindings) {
        return [mediaExts containsObject:url.pathExtension.lowercaseString];
    }]];
    return [contents sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
        NSDate *dateA = nil, *dateB = nil;
        [a getResourceValue:&dateA forKey:NSURLContentModificationDateKey error:nil];
        [b getResourceValue:&dateB forKey:NSURLContentModificationDateKey error:nil];
        return [(dateB ?: NSDate.distantPast) compare:(dateA ?: NSDate.distantPast)];
    }];
}

#pragma mark - Thumbnails

// The real thumbnail YMDownload.x saves alongside the video (same basename,
// .jpg) wins when present; a video downloaded before this existed, or one
// whose thumbnail fetch failed, falls back to a frame grabbed from the video
// itself, cached to Caches/YouMod_Thumbs so it isn't re-decoded every time.
static NSURL *ymSiblingThumbnailURL(NSURL *fileURL) {
    return [[fileURL URLByDeletingPathExtension] URLByAppendingPathExtension:@"jpg"];
}

static NSURL *ymThumbCacheDirectory(void) {
    NSURL *caches = [[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *dir = [caches URLByAppendingPathComponent:@"YouMod_Thumbs" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

static NSURL *ymGeneratedThumbCacheURL(NSURL *fileURL) {
    return [[ymThumbCacheDirectory() URLByAppendingPathComponent:fileURL.lastPathComponent] URLByAppendingPathExtension:@"jpg"];
}

static UIImage *ymThumbnailForVideoFile(NSURL *fileURL) {
    NSData *real = [NSData dataWithContentsOfURL:ymSiblingThumbnailURL(fileURL)];
    if (real) return [UIImage imageWithData:real];

    NSURL *cacheURL = ymGeneratedThumbCacheURL(fileURL);
    NSData *cached = [NSData dataWithContentsOfURL:cacheURL];
    if (cached) return [UIImage imageWithData:cached];

    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:fileURL options:nil];
    AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
    generator.appliesPreferredTrackTransform = YES;
    NSError *error = nil;
    CGImageRef cgImage = [generator copyCGImageAtTime:CMTimeMake(1, 1) actualTime:nil error:&error];
    if (!cgImage) return nil;
    UIImage *image = [UIImage imageWithCGImage:cgImage];
    CGImageRelease(cgImage);
    NSData *jpeg = UIImageJPEGRepresentation(image, 0.7);
    if (jpeg) [jpeg writeToURL:cacheURL atomically:YES];
    return image;
}

static void ymDeleteThumbnailsForFile(NSURL *fileURL) {
    [[NSFileManager defaultManager] removeItemAtURL:ymSiblingThumbnailURL(fileURL) error:nil];
    [[NSFileManager defaultManager] removeItemAtURL:ymGeneratedThumbCacheURL(fileURL) error:nil];
}

#pragma mark - Media info ("View Info")

static NSString *ymFourCCString(FourCharCode code) {
    char chars[5] = {
        (char)((code >> 24) & 0xFF),
        (char)((code >> 16) & 0xFF),
        (char)((code >> 8) & 0xFF),
        (char)(code & 0xFF),
        0,
    };
    for (int i = 0; i < 4; i++) if (chars[i] < 0x20 || chars[i] > 0x7E) chars[i] = '?';
    return [NSString stringWithUTF8String:chars];
}

static NSString *ymMediaInfoStringForFile(NSURL *fileURL, unsigned long long bytes) {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:fileURL options:nil];
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    [lines addObject:[NSString stringWithFormat:@"%@: %@", LOC(@"LIBRARY_INFO_SIZE"), ymFormattedFileSize(bytes)]];
    [lines addObject:[NSString stringWithFormat:@"%@: %.0fs", LOC(@"LIBRARY_INFO_DURATION"), CMTimeGetSeconds(asset.duration)]];
    [lines addObject:[NSString stringWithFormat:@"%@: %@", LOC(@"LIBRARY_INFO_CONTAINER"), fileURL.pathExtension.uppercaseString]];

    AVAssetTrack *videoTrack = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    if (videoTrack) {
        CGSize size = videoTrack.naturalSize;
        [lines addObject:[NSString stringWithFormat:@"%@: %.0fx%.0f", LOC(@"LIBRARY_INFO_RESOLUTION"), fabs(size.width), fabs(size.height)]];
        [lines addObject:[NSString stringWithFormat:@"%@: %.2f fps", LOC(@"LIBRARY_INFO_FRAMERATE"), videoTrack.nominalFrameRate]];
        NSArray *descs = videoTrack.formatDescriptions;
        if (descs.count > 0) {
            FourCharCode subtype = CMFormatDescriptionGetMediaSubType((__bridge CMFormatDescriptionRef)descs.firstObject);
            [lines addObject:[NSString stringWithFormat:@"%@: %@", LOC(@"LIBRARY_INFO_VIDEO_CODEC"), ymFourCCString(subtype)]];
        }
        if (videoTrack.estimatedDataRate > 0) {
            [lines addObject:[NSString stringWithFormat:@"%@: %.0f kbps", LOC(@"LIBRARY_INFO_VIDEO_BITRATE"), videoTrack.estimatedDataRate / 1000.0]];
        }
    }
    AVAssetTrack *audioTrack = [asset tracksWithMediaType:AVMediaTypeAudio].firstObject;
    if (audioTrack) {
        NSArray *descs = audioTrack.formatDescriptions;
        if (descs.count > 0) {
            FourCharCode subtype = CMFormatDescriptionGetMediaSubType((__bridge CMFormatDescriptionRef)descs.firstObject);
            [lines addObject:[NSString stringWithFormat:@"%@: %@", LOC(@"LIBRARY_INFO_AUDIO_CODEC"), ymFourCCString(subtype)]];
        }
        if (audioTrack.estimatedDataRate > 0) {
            [lines addObject:[NSString stringWithFormat:@"%@: %.0f kbps", LOC(@"LIBRARY_INFO_AUDIO_BITRATE"), audioTrack.estimatedDataRate / 1000.0]];
        }
    }
    return [lines componentsJoinedByString:@"\n"];
}

#pragma mark - Row model

@interface YMLibraryRow : NSObject
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) unsigned long long bytes;
@property (nonatomic, copy) NSString *sizeText;
@property (nonatomic, strong) UIImage *thumbnail;
@property (nonatomic, assign) BOOL isAudio;
@end
@implementation YMLibraryRow
@end

#pragma mark - Feed-style cell

@interface YMLibraryVideoCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *thumbnailImageView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *sizeLabel;
@end

@implementation YMLibraryVideoCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor systemBackgroundColor];

        _thumbnailImageView = [UIImageView new];
        _thumbnailImageView.contentMode = UIViewContentModeScaleAspectFill;
        _thumbnailImageView.clipsToBounds = YES;
        _thumbnailImageView.backgroundColor = [UIColor secondarySystemBackgroundColor];
        _thumbnailImageView.translatesAutoresizingMaskIntoConstraints = NO;

        _titleLabel = [UILabel new];
        _titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        _titleLabel.textColor = [UIColor labelColor];
        _titleLabel.numberOfLines = 2;
        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;

        _sizeLabel = [UILabel new];
        _sizeLabel.font = [UIFont systemFontOfSize:13];
        _sizeLabel.textColor = [UIColor secondaryLabelColor];
        _sizeLabel.translatesAutoresizingMaskIntoConstraints = NO;

        [self.contentView addSubview:_thumbnailImageView];
        [self.contentView addSubview:_titleLabel];
        [self.contentView addSubview:_sizeLabel];

        [NSLayoutConstraint activateConstraints:@[
            [_thumbnailImageView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [_thumbnailImageView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [_thumbnailImageView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [_thumbnailImageView.heightAnchor constraintEqualToAnchor:_thumbnailImageView.widthAnchor multiplier:9.0 / 16.0],

            [_titleLabel.topAnchor constraintEqualToAnchor:_thumbnailImageView.bottomAnchor constant:10],
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:14],
            [_titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-14],

            [_sizeLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:2],
            [_sizeLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_sizeLabel.trailingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor],
            [_sizeLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-14],
        ]];
    }
    return self;
}

@end

#pragma mark - Grid layout

// Column count follows actual width, not device idiom — 1 column under
// 600pt (every iPhone, a narrow iPad Split View slice), 2 under 900pt (iPad
// portrait), 3 above that (iPad landscape) — so it also does the right thing
// in Split View / Stage Manager sizes nobody explicitly asked for.
@interface YMLibraryGridLayout : UICollectionViewFlowLayout
@end

@implementation YMLibraryGridLayout

- (instancetype)init {
    self = [super init];
    if (self) {
        self.minimumLineSpacing = 12;
        self.minimumInteritemSpacing = 12;
        self.sectionInset = UIEdgeInsetsMake(12, 12, 12, 12);
    }
    return self;
}

- (void)prepareLayout {
    [super prepareLayout];
    CGFloat width = self.collectionView.bounds.size.width;
    NSInteger columns = width < 600 ? 1 : (width < 900 ? 2 : 3);
    CGFloat spacing = self.minimumInteritemSpacing * (columns - 1) + self.sectionInset.left + self.sectionInset.right;
    CGFloat itemWidth = floor((width - spacing) / columns);
    CGFloat itemHeight = (itemWidth * 9.0 / 16.0) + 80; // thumbnail aspect + title/size text area
    self.itemSize = CGSizeMake(itemWidth, itemHeight);
}

- (BOOL)shouldInvalidateLayoutForBoundsChange:(CGRect)newBounds {
    return newBounds.size.width != self.collectionView.bounds.size.width;
}

@end

// Real YouTube theme colors (see YTCommonColorPalette in Headers.h) instead
// of iOS system colors, so this screen's chrome actually matches native
// tabs — dynamic so it tracks light/dark (and OLED, via Apperence.x's
// existing hook on these same selectors) automatically.
static UIColor *ymYouTubeBackgroundColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection *traitCollection) {
        id palette = traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [%c(YTCommonColorPalette) darkPalette]
            : [%c(YTCommonColorPalette) lightPalette];
        return [palette baseBackground];
    }];
}

#pragma mark - Library view controller

@interface YMLibraryViewController : UIViewController <UICollectionViewDataSource, UICollectionViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) NSMutableArray<YMLibraryRow *> *allRows; // unfiltered backing store
@property (nonatomic, strong) NSMutableArray<YMLibraryRow *> *rows;    // currently displayed (search-filtered)
@property (nonatomic, weak) id hostParentResponder;
@end

@implementation YMLibraryViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = LOC(@"DOWNLOAD_LIBRARY_TAB");
    self.view.backgroundColor = ymYouTubeBackgroundColor();
    self.allRows = [NSMutableArray array];
    self.rows = [NSMutableArray array];

    // Matches the real YTHeaderView's background and height (106pt, measured
    // off-device) so the tab reads as consistent chrome with Home/Shorts/
    // Subscriptions/You rather than a bespoke settings-style screen. Anchored
    // to the true top of the view (not the safe area) since the real header's
    // frame starts at y=0 too — its background runs behind the status bar,
    // only its content is safe-area-inset.
    UIView *topBar = [UIView new];
    // baseBackground, not raisedBackground: the real header sits flush with
    // the body color (confirmed against a screenshot of the real You tab),
    // it isn't visually elevated/lighter.
    topBar.backgroundColor = ymYouTubeBackgroundColor();
    topBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:topBar];

    UIView *topBarSeparator = [UIView new];
    topBarSeparator.backgroundColor = [UIColor separatorColor];
    topBarSeparator.translatesAutoresizingMaskIntoConstraints = NO;
    [topBar addSubview:topBarSeparator];

    _searchBar = [UISearchBar new];
    _searchBar.delegate = self;
    _searchBar.placeholder = LOC(@"SEARCH");
    _searchBar.searchBarStyle = UISearchBarStyleMinimal;
    _searchBar.translatesAutoresizingMaskIntoConstraints = NO;

    // YT_SETTINGS (44) — the real gear glyph YouTube itself uses (YTIcon.h),
    // via the same YouModYTIconImage helper other menus already use, instead
    // of an SF Symbol approximation.
    UIButton *settingsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [settingsButton setImage:YouModYTIconImage(44, NO, nil) forState:UIControlStateNormal];
    settingsButton.tintColor = [UIColor labelColor];
    [settingsButton addTarget:self action:@selector(openSettingsTapped) forControlEvents:UIControlEventTouchUpInside];
    settingsButton.translatesAutoresizingMaskIntoConstraints = NO;

    [topBar addSubview:_searchBar];
    [topBar addSubview:settingsButton];

    // The row of controls (search bar, settings button) has to sit below the
    // status bar even though topBar's own background starts above it — this
    // guide marks that safe sub-region within topBar's fixed 106pt height.
    UILayoutGuide *headerContentGuide = [UILayoutGuide new];
    [topBar addLayoutGuide:headerContentGuide];

    _collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:[YMLibraryGridLayout new]];
    _collectionView.dataSource = self;
    _collectionView.delegate = self;
    _collectionView.backgroundColor = ymYouTubeBackgroundColor();
    _collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    [_collectionView registerClass:[YMLibraryVideoCell class] forCellWithReuseIdentifier:@"video"];
    [self.view addSubview:_collectionView];

    [NSLayoutConstraint activateConstraints:@[
        [topBar.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [topBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [topBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [topBar.heightAnchor constraintEqualToConstant:106],

        [topBarSeparator.leadingAnchor constraintEqualToAnchor:topBar.leadingAnchor],
        [topBarSeparator.trailingAnchor constraintEqualToAnchor:topBar.trailingAnchor],
        [topBarSeparator.bottomAnchor constraintEqualToAnchor:topBar.bottomAnchor],
        [topBarSeparator.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],

        [headerContentGuide.topAnchor constraintEqualToAnchor:topBar.safeAreaLayoutGuide.topAnchor],
        [headerContentGuide.bottomAnchor constraintEqualToAnchor:topBar.bottomAnchor],
        [headerContentGuide.leadingAnchor constraintEqualToAnchor:topBar.leadingAnchor],
        [headerContentGuide.trailingAnchor constraintEqualToAnchor:topBar.trailingAnchor],

        [_searchBar.leadingAnchor constraintEqualToAnchor:headerContentGuide.leadingAnchor],
        [_searchBar.centerYAnchor constraintEqualToAnchor:headerContentGuide.centerYAnchor],

        [settingsButton.leadingAnchor constraintEqualToAnchor:_searchBar.trailingAnchor constant:4],
        [settingsButton.trailingAnchor constraintEqualToAnchor:headerContentGuide.trailingAnchor constant:-14],
        [settingsButton.centerYAnchor constraintEqualToAnchor:_searchBar.centerYAnchor],
        [settingsButton.widthAnchor constraintEqualToConstant:32],

        [_collectionView.topAnchor constraintEqualToAnchor:topBar.bottomAnchor],
        [_collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];

    _emptyLabel = [UILabel new];
    _emptyLabel.text = LOC(@"DOWNLOAD_LIBRARY_EMPTY");
    _emptyLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    _emptyLabel.textColor = [UIColor secondaryLabelColor];
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.hidden = YES;
    _emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_emptyLabel];
    [NSLayoutConstraint activateConstraints:@[
        [_emptyLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [_emptyLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:24],
        [_emptyLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-24],
    ]];

    [self reload];
}

// Replicates -[YTHeaderViewController didPressAccountPanelButton:]'s non-
// incognito, non-iPad branch (confirmed via decompile), just with
// YTSettingsViewController pushed instead of YTAccountPanelViewController —
// the same wrapper class and the same responder-event based presentation the
// real header button uses, rather than a raw presentViewController: (which
// left the tab bar visible and no working close button).
- (void)openSettingsTapped {
    id parentResponder = self.hostParentResponder ?: self;

    // %c(): these classes only exist in the host YouTube binary at runtime,
    // not in anything we link against — a bare class reference fails at link
    // time ("_OBJC_CLASS_$_YTSettingsViewController" undefined).
    //
    // parentResponder must be a real node in YouTube's own responder-chain
    // (it implements -parentResponder itself, walked internally by settings/
    // DI code) — passing self here crashes with "unrecognized selector
    // parentResponder" the moment that walk reaches our plain UIViewController.
    // hostParentResponder is the YTPivotBarViewController that swapped us in,
    // which already implements this correctly.
    YTSettingsViewController *settingsVC = [[%c(YTSettingsViewController) alloc] initWithAccountID:nil parentResponder:parentResponder];
    if (!settingsVC) return;
    // Force the grouped layout (General/YouMod etc. as single tap-through
    // rows) — confirmed against screenshots: 1 = grouped (what's wanted), a
    // fresh instance otherwise renders flat/inline (every row expanded
    // directly into the list, not what's wanted).
    settingsVC.appearance = 1;

    YTNavigationController *nav = [[%c(YTNavigationController) alloc] initWithParentResponder:parentResponder];
    nav.modalPresentationStyle = UIModalPresentationFormSheet; // value 2, matching the real button
    [nav pushViewController:settingsVC animated:NO];

    YTPresentModalResponderEvent *event = [%c(YTPresentModalResponderEvent) eventWithViewController:nav animated:YES firstResponder:parentResponder];
    [event send];
}

- (void)reload {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSArray<NSURL *> *files = ymLibraryFileURLsNewestFirst();
        NSMutableArray<YMLibraryRow *> *rows = [NSMutableArray arrayWithCapacity:files.count];
        for (NSURL *fileURL in files) {
            NSNumber *size = nil;
            [fileURL getResourceValue:&size forKey:NSURLFileSizeKey error:nil];

            YMLibraryRow *row = [YMLibraryRow new];
            row.path = fileURL.path;
            row.title = ymDisplayTitleForFileName(fileURL.lastPathComponent.stringByDeletingPathExtension);
            row.bytes = size.unsignedLongLongValue;
            row.sizeText = ymFormattedFileSize(row.bytes);
            row.isAudio = ymIsAudioOnlyExtension(fileURL.pathExtension);
            row.thumbnail = row.isAudio ? [UIImage systemImageNamed:@"music.note"] : ymThumbnailForVideoFile(fileURL);
            [rows addObject:row];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self.allRows = rows;
            [self applyFilter:self.searchBar.text];
            self.emptyLabel.hidden = rows.count > 0;
        });
    });
}

- (void)applyFilter:(NSString *)query {
    query = [query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (query.length == 0) {
        self.rows = [self.allRows mutableCopy];
    } else {
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"title CONTAINS[cd] %@", query];
        self.rows = [[self.allRows filteredArrayUsingPredicate:predicate] mutableCopy];
    }
    [self.collectionView reloadData];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    [self applyFilter:searchText];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.rows.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    YMLibraryVideoCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"video" forIndexPath:indexPath];
    YMLibraryRow *row = self.rows[indexPath.item];
    cell.titleLabel.text = row.title;
    cell.sizeLabel.text = row.sizeText;
    cell.thumbnailImageView.image = row.thumbnail;
    cell.thumbnailImageView.tintColor = row.isAudio ? [UIColor secondaryLabelColor] : nil;
    return cell;
}

// Single tap: try the built-in player, fall back to sharing if the file
// isn't natively playable (e.g. mkv/mka, which need something like VLC).
- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:YES];
    YMLibraryRow *row = self.rows[indexPath.item];
    NSURL *fileURL = [NSURL fileURLWithPath:row.path];

    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:fileURL options:nil];
    if (asset.isPlayable) {
        AVPlayerViewController *playerVC = [AVPlayerViewController new];
        playerVC.player = [AVPlayer playerWithURL:fileURL];
        [self presentViewController:playerVC animated:YES completion:^{
            [playerVC.player play];
        }];
    } else {
        YouModShareItem(fileURL, self);
    }
}

// Long press: native context menu (shows live while held, with the system
// blur/scale preview) instead of a UILongPressGestureRecognizer + presented
// UIAlertController — that combination only visibly animates in after the
// touch ends, since the alert's presentation gets deferred until the current
// touch-tracking run loop finishes.
- (UIContextMenuConfiguration *)collectionView:(UICollectionView *)collectionView contextMenuConfigurationForItemAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu * _Nullable(NSArray<UIMenuElement *> * _Nonnull suggestedActions) {
        return [self contextMenuForRowAtIndexPath:indexPath];
    }];
}

- (UIMenu *)contextMenuForRowAtIndexPath:(NSIndexPath *)indexPath {
    YMLibraryRow *row = self.rows[indexPath.item];
    NSURL *fileURL = [NSURL fileURLWithPath:row.path];

    UIAction *openVideo = [UIAction actionWithTitle:LOC(@"LIBRARY_OPEN_VIDEO") image:[UIImage systemImageNamed:@"play.rectangle"] identifier:nil handler:^(UIAction *action) {
        [self openOriginalVideoForRow:row];
    }];
    UIAction *share = [UIAction actionWithTitle:LOC(@"LIBRARY_SHARE") image:[UIImage systemImageNamed:@"square.and.arrow.up"] identifier:nil handler:^(UIAction *action) {
        YouModShareItem(fileURL, self);
    }];
    UIAction *saveThumbnail = [UIAction actionWithTitle:LOC(@"LIBRARY_SAVE_THUMBNAIL") image:[UIImage systemImageNamed:@"photo"] identifier:nil handler:^(UIAction *action) {
        [self saveThumbnailToPhotosForRow:row];
    }];
    UIAction *viewInfo = [UIAction actionWithTitle:LOC(@"LIBRARY_VIEW_INFO") image:[UIImage systemImageNamed:@"info.circle"] identifier:nil handler:^(UIAction *action) {
        [self presentInfoForFileURL:fileURL bytes:row.bytes];
    }];
    UIAction *delete = [UIAction actionWithTitle:LOC(@"LIBRARY_DELETE") image:[UIImage systemImageNamed:@"trash"] identifier:nil handler:^(UIAction *action) {
        [self deleteRowAtIndexPath:indexPath];
    }];
    delete.attributes = UIMenuElementAttributesDestructive;

    return [UIMenu menuWithTitle:row.title children:@[share, saveThumbnail, openVideo, viewInfo, delete]];
}

// Reuses the youtube:// scheme handoff YMOpenLinkFromClipboard (Tabbar.x)
// already relies on, with the ID pulled straight from the filename instead
// of parsed out of a pasted URL.
- (void)openOriginalVideoForRow:(YMLibraryRow *)row {
    NSString *videoID = ymVideoIDForFileName(row.path.lastPathComponent.stringByDeletingPathExtension);
    NSURL *youtubeURL = videoID ? [NSURL URLWithString:[NSString stringWithFormat:@"youtube://%@", videoID]] : nil;
    if (!youtubeURL || ![[UIApplication sharedApplication] canOpenURL:youtubeURL]) {
        YouModSendError(LOC(@"LIBRARY_NO_VIDEO_ID"));
        return;
    }
    [[UIApplication sharedApplication] openURL:youtubeURL options:@{} completionHandler:nil];
}

- (void)saveThumbnailToPhotosForRow:(YMLibraryRow *)row {
    UIImage *image = row.thumbnail;
    if (!image || row.isAudio) {
        YouModSendError(LOC(@"NO_THUMBNAIL_FOUND"));
        return;
    }
    YouModRequestPhotoAccess(^(BOOL granted) {
        if (!granted) {
            YouModSendError(LOC(@"PHOTO_ACCESS_DENINED"));
            return;
        }
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            [PHAssetChangeRequest creationRequestForAssetFromImage:image];
        } completionHandler:^(BOOL success, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (success) {
                    YouModSendSuccess(LOC(@"SAVED_TO_PHOTOS"));
                } else {
                    YouModSendError(error.localizedDescription ?: LOC(@"SAVE_FAILED"));
                }
            });
        }];
    });
}

- (void)presentInfoForFileURL:(NSURL *)fileURL bytes:(unsigned long long)bytes {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *info = ymMediaInfoStringForFile(fileURL, bytes);
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:LOC(@"LIBRARY_VIEW_INFO") message:info preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:LOC(@"OK") style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        });
    });
}

- (void)deleteRowAtIndexPath:(NSIndexPath *)indexPath {
    YMLibraryRow *row = self.rows[indexPath.item];
    NSURL *fileURL = [NSURL fileURLWithPath:row.path];
    [[NSFileManager defaultManager] removeItemAtURL:fileURL error:nil];
    ymDeleteThumbnailsForFile(fileURL);
    [self.allRows removeObject:row];
    [self.rows removeObjectAtIndex:indexPath.item];
    [self.collectionView deleteItemsAtIndexPaths:@[indexPath]];
    self.emptyLabel.hidden = self.allRows.count > 0;
}

@end

#pragma mark - Entry point

UIViewController *YouModDownloadLibraryViewController(id hostParentResponder) {
    YMLibraryViewController *vc = [YMLibraryViewController new];
    vc.hostParentResponder = hostParentResponder;
    return vc;
}
