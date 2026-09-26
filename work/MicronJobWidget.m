#import <Cocoa/Cocoa.h>

@interface FlippedView : NSView
@end
@implementation FlippedView
- (BOOL)isFlipped { return YES; }
@end

static NSString *ConfigPath;
static NSString *AlertPath;
static NSString *AlertHistoryPath;
static NSString *LastRunPath;
static NSString *const IconMovedNotification = @"MicronJobIconMoved";

static void ConfigureStoragePaths(void) {
    NSString *base = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    NSString *directory = [base stringByAppendingPathComponent:@"JobMonitor"];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    ConfigPath = [directory stringByAppendingPathComponent:@"job-monitor-config.json"];
    AlertPath = [directory stringByAppendingPathComponent:@"job-alert.json"];
    AlertHistoryPath = [directory stringByAppendingPathComponent:@"job-alert-history.json"];
    LastRunPath = [directory stringByAppendingPathComponent:@"job-monitor-last-run.json"];
}

@interface DraggableButton : NSButton
@end

@implementation DraggableButton
- (void)mouseDown:(NSEvent *)event {
    NSPoint startMouse = NSEvent.mouseLocation;
    NSPoint startWindow = self.window.frame.origin;
    BOOL dragged = NO;
    while (YES) {
        NSEvent *next = [self.window nextEventMatchingMask:(NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp)];
        if (next.type == NSEventTypeLeftMouseUp) break;
        NSPoint current = NSEvent.mouseLocation;
        CGFloat dx = current.x - startMouse.x;
        CGFloat dy = current.y - startMouse.y;
        if (fabs(dx) > 3 || fabs(dy) > 3) dragged = YES;
        if (dragged) {
            [self.window setFrameOrigin:NSMakePoint(startWindow.x + dx, startWindow.y + dy)];
            [NSNotificationCenter.defaultCenter postNotificationName:IconMovedNotification object:nil];
        }
    }
    if (dragged) {
        [NSUserDefaults.standardUserDefaults setObject:NSStringFromPoint(self.window.frame.origin) forKey:@"JobWidgetIconPosition"];
    } else {
        [NSApp sendAction:self.action to:self.target from:self];
    }
}
@end

@interface AppDelegate : NSObject <NSApplicationDelegate, NSTextFieldDelegate, NSTokenFieldDelegate, NSSearchFieldDelegate>
@property(strong) NSPanel *bubblePanel;
@property(strong) NSPanel *iconPanel;
@property(strong) NSPanel *settingsPanel;
@property(strong) NSPanel *companyListPanel;
@property(strong) NSPanel *alertListPanel;
@property(strong) NSStackView *alertListStack;
@property(strong) NSStackView *bubbleAlertStack;
@property(strong) NSStackView *companyCardsStack;
@property(strong) NSTextView *companyListText;
@property(strong) NSTextField *messageLabel;
@property(strong) NSTextField *companyLabel;
@property(strong) NSTextField *metaLabel;
@property(strong) NSButton *openJobButton;
@property(strong) NSTextField *unreadBadge;
@property(strong) NSURL *currentJobURL;
@property(strong) NSArray<NSDictionary *> *currentJobs;
@property(strong) NSButton *iconButton;
@property(strong) NSArray<NSButton *> *roleChecks;
@property(strong) NSTokenField *roleTokenField;
@property(strong) NSPopover *rolePopover;
@property(strong) NSSearchField *roleSearchField;
@property(strong) NSStackView *roleOptionsStack;
@property(strong) NSScrollView *roleOptionsScroll;
@property(strong) NSView *roleOptionsDocument;
@property(strong) NSButton *internshipRadio;
@property(strong) NSTextField *companyNameError;
@property(strong) NSTextField *companyURLError;
@property(strong) NSTextField *roleError;
@property(assign) BOOL companyNameAutoFilled;
@property(strong) NSPopUpButton *companySelector;
@property(strong) NSTextField *companyNameField;
@property(strong) NSTextField *companyURLField;
@property(strong) NSMutableArray<NSMutableDictionary *> *monitors;
@property(assign) NSInteger editingIndex;
@property(strong) NSStatusItem *statusItem;
@property(strong) NSDate *lastAlertDate;
@property(strong) NSDate *lastScanDate;
@property(strong) NSTimer *alertTimer;
@property(assign) BOOL bubbleVisible;
@end

@implementation AppDelegate

- (NSTextField *)label:(NSString *)text size:(CGFloat)size color:(NSColor *)color {
    NSTextField *field = [NSTextField labelWithString:text];
    field.font = [NSFont systemFontOfSize:size];
    field.textColor = color;
    return field;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    if (self.iconPanel != nil) return;
    ConfigureStoragePaths();
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    [self installStandardMenus];
    [self buildIcon];
    [self buildBubble];
    [self buildSettings];
    [self buildCompanyListPanel];
    [self buildAlertListPanel];
    [self buildStatusItem];
    [self loadSettings];
    [self startAlertWatcher];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(iconMoved:) name:IconMovedNotification object:nil];
    [self.iconPanel makeKeyAndOrderFront:nil];
    [self.bubblePanel orderOut:nil];
}

- (void)installStandardMenus {
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"MainMenu"];

    NSMenuItem *appItem = [[NSMenuItem alloc] initWithTitle:@"App" action:nil keyEquivalent:@""];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"App"];
    [appMenu addItemWithTitle:@"退出岗位助手" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu;
    [mainMenu addItem:appItem];

    NSMenuItem *editItem = [[NSMenuItem alloc] initWithTitle:@"编辑" action:nil keyEquivalent:@""];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"编辑"];
    [editMenu addItemWithTitle:@"撤销" action:@selector(undo:) keyEquivalent:@"z"];
    [editMenu addItemWithTitle:@"重做" action:@selector(redo:) keyEquivalent:@"Z"];
    [editMenu addItem:NSMenuItem.separatorItem];
    [editMenu addItemWithTitle:@"剪切" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"复制" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"粘贴" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"全选" action:@selector(selectAll:) keyEquivalent:@"a"];
    editItem.submenu = editMenu;
    [mainMenu addItem:editItem];
    NSApp.mainMenu = mainMenu;
}

- (void)buildIcon {
    NSRect frame = NSMakeRect(0, 0, 56, 56);
    self.iconPanel = [[NSPanel alloc] initWithContentRect:frame styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    self.iconPanel.backgroundColor = NSColor.clearColor;
    self.iconPanel.opaque = NO;
    self.iconPanel.hasShadow = YES;
    self.iconPanel.level = NSFloatingWindowLevel;
    self.iconPanel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
    
    NSView *root = [[NSView alloc] initWithFrame:frame];
    root.wantsLayer = YES;
    self.iconPanel.contentView = root;

    self.iconButton = [[DraggableButton alloc] init];
    self.iconButton.title = @"M";
    self.iconButton.target = self;
    self.iconButton.action = @selector(toggleBubble:);
    self.iconButton.font = [NSFont systemFontOfSize:22 weight:NSFontWeightHeavy];
    self.iconButton.contentTintColor = NSColor.whiteColor;
    self.iconButton.bordered = NO;
    self.iconButton.toolTip = @"显示或收起岗位提醒";
    self.iconButton.wantsLayer = YES;
    
    // 美化悬浮按钮：加入阴影和更现代的蓝色
    self.iconButton.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.0 green:0.478 blue:1.0 alpha:0.95].CGColor;
    self.iconButton.layer.cornerRadius = 24;
    self.iconButton.layer.borderWidth = 2;
    self.iconButton.layer.borderColor = [NSColor colorWithWhite:1.0 alpha:0.5].CGColor;
    self.iconButton.layer.shadowColor = NSColor.blackColor.CGColor;
    self.iconButton.layer.shadowOffset = NSMakeSize(0, -2);
    self.iconButton.layer.shadowOpacity = 0.25;
    self.iconButton.layer.shadowRadius = 4;
    
    self.iconButton.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:self.iconButton];
    self.unreadBadge = [self label:@"" size:9 color:NSColor.whiteColor];
    self.unreadBadge.font = [NSFont systemFontOfSize:9 weight:NSFontWeightBold];
    self.unreadBadge.alignment = NSTextAlignmentCenter;
    self.unreadBadge.wantsLayer = YES;
    self.unreadBadge.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.94 green:0.20 blue:0.24 alpha:1.0].CGColor;
    self.unreadBadge.layer.cornerRadius = 9;
    self.unreadBadge.layer.borderWidth = 2;
    self.unreadBadge.layer.borderColor = NSColor.whiteColor.CGColor;
    self.unreadBadge.translatesAutoresizingMaskIntoConstraints = NO;
    self.unreadBadge.hidden = YES;
    [root addSubview:self.unreadBadge];
    [NSLayoutConstraint activateConstraints:@[
        [self.iconButton.widthAnchor constraintEqualToConstant:48],
        [self.iconButton.heightAnchor constraintEqualToConstant:48],
        [self.iconButton.centerXAnchor constraintEqualToAnchor:root.centerXAnchor],
        [self.iconButton.centerYAnchor constraintEqualToAnchor:root.centerYAnchor],
        [self.unreadBadge.widthAnchor constraintGreaterThanOrEqualToConstant:18],
        [self.unreadBadge.heightAnchor constraintEqualToConstant:18],
        [self.unreadBadge.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-1],
        [self.unreadBadge.topAnchor constraintEqualToAnchor:root.topAnchor constant:1]
    ]];

    NSString *saved = [NSUserDefaults.standardUserDefaults stringForKey:@"JobWidgetIconPosition"];
    if (saved.length > 0) [self.iconPanel setFrameOrigin:NSPointFromString(saved)];
    else {
        NSRect screen = NSScreen.mainScreen.visibleFrame;
        [self.iconPanel setFrameOrigin:NSMakePoint(NSMinX(screen) + 24, NSMaxY(screen) - 78)];
    }
}

- (void)buildBubble {
    NSRect frame = NSMakeRect(0, 0, 366, 300);
    self.bubblePanel = [[NSPanel alloc] initWithContentRect:frame styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    self.bubblePanel.backgroundColor = NSColor.clearColor;
    self.bubblePanel.opaque = NO;
    self.bubblePanel.hasShadow = YES;
    self.bubblePanel.level = NSFloatingWindowLevel;
    self.bubblePanel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
    
    NSView *surface = [[NSView alloc] initWithFrame:frame];
    surface.wantsLayer = YES;
    surface.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.995 green:0.995 blue:1.0 alpha:0.98].CGColor;
    surface.layer.cornerRadius = 16;
    surface.layer.masksToBounds = YES;
    surface.layer.borderWidth = 0.7;
    surface.layer.borderColor = [NSColor colorWithCalibratedRed:0.88 green:0.89 blue:0.92 alpha:1.0].CGColor;
    self.bubblePanel.contentView = surface;

    NSStackView *header = [[NSStackView alloc] init];
    header.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    header.alignment = NSLayoutAttributeCenterY;
    header.spacing = 7;
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [surface addSubview:header];

    NSView *brandDot = [[NSView alloc] init];
    brandDot.wantsLayer = YES;
    brandDot.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.20 green:0.44 blue:1.0 alpha:1.0].CGColor;
    brandDot.layer.cornerRadius = 4;
    [brandDot.widthAnchor constraintEqualToConstant:8].active = YES;
    [brandDot.heightAnchor constraintEqualToConstant:8].active = YES;

    NSTextField *title = [self label:@"职位助手" size:11 color:[NSColor colorWithCalibratedRed:0.09 green:0.10 blue:0.14 alpha:1.0]];
    title.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];

    NSButton *settings = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"gearshape.fill" accessibilityDescription:nil] target:self action:@selector(showSettings:)];
    settings.bordered = NO;
    settings.contentTintColor = [NSColor colorWithCalibratedRed:0.53 green:0.56 blue:0.62 alpha:1.0];
    settings.toolTip = @"设置";
    [settings.widthAnchor constraintEqualToConstant:22].active = YES;

    NSButton *companies = [NSButton buttonWithTitle:@"监控公司" target:self action:@selector(showCompanies:)];
    companies.bezelStyle = NSBezelStyleInline;
    companies.controlSize = NSControlSizeMini;
    companies.font = [NSFont systemFontOfSize:10 weight:NSFontWeightMedium];
    companies.contentTintColor = [NSColor colorWithCalibratedRed:0.35 green:0.38 blue:0.44 alpha:1.0];

    [header addArrangedSubview:brandDot];
    [header addArrangedSubview:title];
    [header addArrangedSubview:[[NSView alloc] init]];
    [header addArrangedSubview:companies];
    [header addArrangedSubview:settings];

    NSView *separator = [[NSView alloc] init];
    separator.wantsLayer = YES;
    separator.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.93 green:0.94 blue:0.96 alpha:1.0].CGColor;
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    [surface addSubview:separator];

    NSScrollView *bubbleScroll = [[NSScrollView alloc] init];
    bubbleScroll.drawsBackground = NO;
    bubbleScroll.hasVerticalScroller = YES;
    bubbleScroll.scrollerStyle = NSScrollerStyleOverlay;
    bubbleScroll.translatesAutoresizingMaskIntoConstraints = NO;
    FlippedView *bubbleDocument = [[FlippedView alloc] init];
    bubbleDocument.translatesAutoresizingMaskIntoConstraints = NO;
    self.bubbleAlertStack = [[NSStackView alloc] init];
    self.bubbleAlertStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.bubbleAlertStack.alignment = NSLayoutAttributeLeading;
    self.bubbleAlertStack.spacing = 6;
    self.bubbleAlertStack.edgeInsets = NSEdgeInsetsMake(8, 0, 8, 0);
    self.bubbleAlertStack.translatesAutoresizingMaskIntoConstraints = NO;
    [bubbleDocument addSubview:self.bubbleAlertStack];
    bubbleScroll.documentView = bubbleDocument;
    [surface addSubview:bubbleScroll];
    [NSLayoutConstraint activateConstraints:@[
        [bubbleScroll.leadingAnchor constraintEqualToAnchor:surface.leadingAnchor constant:12],
        [bubbleScroll.trailingAnchor constraintEqualToAnchor:surface.trailingAnchor constant:-10],
        [bubbleScroll.topAnchor constraintEqualToAnchor:separator.bottomAnchor constant:5],
        [bubbleScroll.bottomAnchor constraintEqualToAnchor:surface.bottomAnchor constant:-43],
        [bubbleDocument.widthAnchor constraintEqualToAnchor:bubbleScroll.contentView.widthAnchor],
        [self.bubbleAlertStack.leadingAnchor constraintEqualToAnchor:bubbleDocument.leadingAnchor],
        [self.bubbleAlertStack.trailingAnchor constraintEqualToAnchor:bubbleDocument.trailingAnchor],
        [self.bubbleAlertStack.topAnchor constraintEqualToAnchor:bubbleDocument.topAnchor],
        [self.bubbleAlertStack.bottomAnchor constraintEqualToAnchor:bubbleDocument.bottomAnchor]
    ]];

    self.companyLabel = [self label:@"监控中" size:10 color:[NSColor colorWithCalibratedRed:0.14 green:0.36 blue:0.92 alpha:1.0]];
    self.companyLabel.font = [NSFont systemFontOfSize:10 weight:NSFontWeightSemibold];
    self.companyLabel.alignment = NSTextAlignmentCenter;
    self.companyLabel.wantsLayer = YES;
    self.companyLabel.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.92 green:0.95 blue:1.0 alpha:1.0].CGColor;
    self.companyLabel.layer.cornerRadius = 5;
    self.companyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [surface addSubview:self.companyLabel];

    self.messageLabel = [self label:@"等待符合条件的新岗位" size:13 color:[NSColor colorWithCalibratedRed:0.09 green:0.10 blue:0.14 alpha:1.0]];
    self.messageLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    self.messageLabel.maximumNumberOfLines = 2;
    self.messageLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.messageLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [surface addSubview:self.messageLabel];

    self.metaLabel = [self label:@"⌖ Singapore  ·  自动检查已开启" size:10 color:[NSColor colorWithCalibratedRed:0.53 green:0.56 blue:0.62 alpha:1.0]];
    self.metaLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [surface addSubview:self.metaLabel];

    self.openJobButton = [NSButton buttonWithTitle:@"查看  →" target:self action:@selector(openCurrentJob:)];
    self.openJobButton.bordered = NO;
    self.openJobButton.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
    self.openJobButton.wantsLayer = YES;
    self.openJobButton.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.20 green:0.44 blue:1.0 alpha:1.0].CGColor;
    self.openJobButton.layer.cornerRadius = 7;
    self.openJobButton.contentTintColor = NSColor.whiteColor;
    self.openJobButton.enabled = NO;
    self.openJobButton.keyEquivalent = @"\r";
    self.openJobButton.translatesAutoresizingMaskIntoConstraints = NO;
    [surface addSubview:self.openJobButton];

    self.companyLabel.hidden = YES;
    self.messageLabel.hidden = YES;
    self.metaLabel.hidden = YES;
    self.openJobButton.hidden = YES;

    [NSLayoutConstraint activateConstraints:@[
        [header.leadingAnchor constraintEqualToAnchor:surface.leadingAnchor constant:16],
        [header.trailingAnchor constraintEqualToAnchor:surface.trailingAnchor constant:-12],
        [header.topAnchor constraintEqualToAnchor:surface.topAnchor constant:11],
        [header.heightAnchor constraintEqualToConstant:22],
        [separator.leadingAnchor constraintEqualToAnchor:surface.leadingAnchor constant:16],
        [separator.trailingAnchor constraintEqualToAnchor:surface.trailingAnchor constant:-16],
        [separator.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:7],
        [separator.heightAnchor constraintEqualToConstant:1],
        [self.companyLabel.leadingAnchor constraintEqualToAnchor:surface.leadingAnchor constant:16],
        [self.companyLabel.topAnchor constraintEqualToAnchor:separator.bottomAnchor constant:12],
        [self.companyLabel.heightAnchor constraintEqualToConstant:20],
        [self.companyLabel.widthAnchor constraintGreaterThanOrEqualToConstant:58],
        [self.messageLabel.leadingAnchor constraintEqualToAnchor:surface.leadingAnchor constant:16],
        [self.messageLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.openJobButton.leadingAnchor constant:-8],
        [self.messageLabel.topAnchor constraintEqualToAnchor:self.companyLabel.bottomAnchor constant:7],
        [self.metaLabel.leadingAnchor constraintEqualToAnchor:surface.leadingAnchor constant:16],
        [self.metaLabel.trailingAnchor constraintEqualToAnchor:surface.trailingAnchor constant:-16],
        [self.metaLabel.topAnchor constraintEqualToAnchor:self.messageLabel.bottomAnchor constant:5],
        [self.openJobButton.trailingAnchor constraintEqualToAnchor:surface.trailingAnchor constant:-16],
        [self.openJobButton.centerYAnchor constraintEqualToAnchor:self.messageLabel.centerYAnchor],
        [self.openJobButton.widthAnchor constraintEqualToConstant:68],
        [self.openJobButton.heightAnchor constraintEqualToConstant:28]
    ]];
}

- (void)positionBubbleNextToIcon {
    const CGFloat bubbleWidth = 366;
    const CGFloat bubbleHeight = 300;
    NSRect icon = self.iconPanel.frame;
    NSRect visible = (self.iconPanel.screen ?: NSScreen.mainScreen).visibleFrame;
    
    CGFloat x = NSMaxX(icon) + 12;
    if (x + bubbleWidth > NSMaxX(visible)) {
        x = NSMinX(icon) - bubbleWidth - 12;
    }
    
    CGFloat y = NSMaxY(icon) - bubbleHeight;
    y = MAX(NSMinY(visible) + 8, MIN(y, NSMaxY(visible) - bubbleHeight));
    
    [self.bubblePanel setFrame:NSMakeRect(x, y, bubbleWidth, bubbleHeight) display:YES];
}
- (NSButton *)check:(NSString *)title {
    NSButton *button = [NSButton checkboxWithTitle:title target:nil action:nil];
    button.font = [NSFont systemFontOfSize:13];
    return button;
}

- (void)buildCompanyListPanel {
    NSRect frame = NSMakeRect(0, 0, 500, 500);
    self.companyListPanel = [[NSPanel alloc] initWithContentRect:frame styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskFullSizeContentView backing:NSBackingStoreBuffered defer:NO];
    self.companyListPanel.title = @"监控公司";
    self.companyListPanel.titlebarAppearsTransparent = YES;
    self.companyListPanel.releasedWhenClosed = NO;
    self.companyListPanel.level = NSFloatingWindowLevel;

    NSView *bg = [[NSView alloc] initWithFrame:frame];
    bg.wantsLayer = YES;
    bg.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.969 green:0.976 blue:0.988 alpha:1.0].CGColor;
    self.companyListPanel.contentView = bg;

    NSTextField *heading = [self label:@"监控公司" size:24 color:[NSColor colorWithCalibratedRed:0.11 green:0.13 blue:0.16 alpha:1.0]];
    heading.font = [NSFont systemFontOfSize:24 weight:NSFontWeightBold];
    heading.translatesAutoresizingMaskIntoConstraints = NO;
    [bg addSubview:heading];
    NSTextField *caption = [self label:@"管理每家公司的招聘网址和岗位方向。每天 09:30 与 18:30 检查。" size:12 color:[NSColor colorWithCalibratedRed:0.53 green:0.57 blue:0.62 alpha:1.0]];
    caption.translatesAutoresizingMaskIntoConstraints = NO;
    [bg addSubview:caption];
    NSButton *add = [NSButton buttonWithTitle:@"+  添加公司" target:self action:@selector(addCompanyFromList:)];
    add.bordered = NO;
    add.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
    add.contentTintColor = NSColor.whiteColor;
    add.wantsLayer = YES;
    add.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.086 green:0.365 blue:1.0 alpha:1.0].CGColor;
    add.layer.cornerRadius = 6;
    add.translatesAutoresizingMaskIntoConstraints = NO;
    [bg addSubview:add];

    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.hasVerticalScroller = YES;
    scroll.drawsBackground = NO;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [bg addSubview:scroll];
    FlippedView *document = [[FlippedView alloc] init];
    document.translatesAutoresizingMaskIntoConstraints = NO;
    self.companyCardsStack = [[NSStackView alloc] init];
    self.companyCardsStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.companyCardsStack.alignment = NSLayoutAttributeLeading;
    self.companyCardsStack.spacing = 10;
    self.companyCardsStack.edgeInsets = NSEdgeInsetsMake(8, 0, 18, 0);
    self.companyCardsStack.translatesAutoresizingMaskIntoConstraints = NO;
    [document addSubview:self.companyCardsStack];
    scroll.documentView = document;
    [NSLayoutConstraint activateConstraints:@[
        [heading.leadingAnchor constraintEqualToAnchor:bg.leadingAnchor constant:24],
        [heading.topAnchor constraintEqualToAnchor:bg.topAnchor constant:42],
        [caption.leadingAnchor constraintEqualToAnchor:heading.leadingAnchor],
        [caption.topAnchor constraintEqualToAnchor:heading.bottomAnchor constant:4],
        [add.trailingAnchor constraintEqualToAnchor:bg.trailingAnchor constant:-24],
        [add.centerYAnchor constraintEqualToAnchor:heading.centerYAnchor],
        [add.widthAnchor constraintEqualToConstant:100],
        [add.heightAnchor constraintEqualToConstant:30],
        [scroll.leadingAnchor constraintEqualToAnchor:bg.leadingAnchor constant:18],
        [scroll.trailingAnchor constraintEqualToAnchor:bg.trailingAnchor constant:-18],
        [scroll.topAnchor constraintEqualToAnchor:caption.bottomAnchor constant:16],
        [scroll.bottomAnchor constraintEqualToAnchor:bg.bottomAnchor constant:-16],
        [document.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor],
        [self.companyCardsStack.leadingAnchor constraintEqualToAnchor:document.leadingAnchor],
        [self.companyCardsStack.trailingAnchor constraintEqualToAnchor:document.trailingAnchor],
        [self.companyCardsStack.topAnchor constraintEqualToAnchor:document.topAnchor],
        [self.companyCardsStack.bottomAnchor constraintEqualToAnchor:document.bottomAnchor]
    ]];
}

- (void)refreshCompanyCards {
    for (NSView *view in self.companyCardsStack.arrangedSubviews.copy) {
        [self.companyCardsStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    if (self.monitors.count == 0) {
        NSTextField *empty = [self label:@"还没有监控公司，点击右上角“添加公司”开始。" size:12 color:NSColor.secondaryLabelColor];
        [self.companyCardsStack addArrangedSubview:empty];
        return;
    }
    [self.monitors enumerateObjectsUsingBlock:^(NSDictionary *item, NSUInteger idx, BOOL *stop) {
        NSView *card = [[NSView alloc] init];
        card.wantsLayer = YES;
        card.layer.backgroundColor = NSColor.whiteColor.CGColor;
        card.layer.cornerRadius = 10;
        card.layer.borderWidth = 1;
        card.layer.borderColor = [NSColor colorWithCalibratedRed:0.90 green:0.91 blue:0.93 alpha:1.0].CGColor;
        card.layer.shadowColor = NSColor.blackColor.CGColor;
        card.layer.shadowOpacity = 0.035;
        card.layer.shadowOffset = NSMakeSize(0, -2);
        card.layer.shadowRadius = 8;
        NSStackView *row = [[NSStackView alloc] init];
        row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        row.alignment = NSLayoutAttributeCenterY;
        row.spacing = 10;
        row.edgeInsets = NSEdgeInsetsMake(13, 14, 13, 14);
        row.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:row];
        [NSLayoutConstraint activateConstraints:@[
            [row.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
            [row.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
            [row.topAnchor constraintEqualToAnchor:card.topAnchor],
            [row.bottomAnchor constraintEqualToAnchor:card.bottomAnchor]
        ]];
        NSView *logo = [[NSView alloc] init];
        logo.wantsLayer = YES;
        logo.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.91 green:0.95 blue:1.0 alpha:1.0].CGColor;
        logo.layer.cornerRadius = 9;
        [logo.widthAnchor constraintEqualToConstant:36].active = YES;
        [logo.heightAnchor constraintEqualToConstant:36].active = YES;
        NSString *companyName = [item[@"company"] isKindOfClass:NSString.class] && [item[@"company"] length] ? item[@"company"] : @"?";
        NSTextField *initial = [self label:[[companyName substringToIndex:1] uppercaseString] size:14 color:[NSColor colorWithCalibratedRed:0.086 green:0.365 blue:1.0 alpha:1.0]];
        initial.font = [NSFont systemFontOfSize:14 weight:NSFontWeightBold];
        initial.alignment = NSTextAlignmentCenter;
        initial.frame = NSMakeRect(0, 9, 36, 18);
        [logo addSubview:initial];
        NSStackView *info = [[NSStackView alloc] init];
        info.orientation = NSUserInterfaceLayoutOrientationVertical;
        info.alignment = NSLayoutAttributeLeading;
        info.spacing = 3;
        NSTextField *name = [self label:item[@"company"] ?: @"未命名公司" size:14 color:[NSColor colorWithCalibratedRed:0.11 green:0.13 blue:0.16 alpha:1.0]];
        name.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
        NSString *roles = [item[@"roles"] componentsJoinedByString:@" · "] ?: @"";
        NSArray *custom = [item[@"custom_keywords"] isKindOfClass:NSArray.class] ? item[@"custom_keywords"] : @[];
        if (custom.count) roles = roles.length ? [roles stringByAppendingFormat:@" · %@", [custom componentsJoinedByString:@" / "]] : [custom componentsJoinedByString:@" / "];
        NSString *detail = [NSString stringWithFormat:@"%@  ·  仅实习  ·  09:30 / 18:30", roles];
        NSTextField *meta = [self label:detail size:10 color:[NSColor colorWithCalibratedRed:0.31 green:0.35 blue:0.41 alpha:1.0]];
        NSString *fullURL = item[@"url"] ?: @"";
        NSTextField *url = [self label:fullURL size:9 color:[NSColor colorWithCalibratedRed:0.53 green:0.57 blue:0.62 alpha:1.0]];
        url.lineBreakMode = NSLineBreakByTruncatingTail;
        url.maximumNumberOfLines = 1;
        url.toolTip = fullURL;
        [url.widthAnchor constraintLessThanOrEqualToConstant:275].active = YES;
        [url setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        [info addArrangedSubview:name]; [info addArrangedSubview:meta]; [info addArrangedSubview:url];
        [info setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
        NSButton *edit = [NSButton buttonWithTitle:@"编辑" target:self action:@selector(editCompanyFromList:)];
        edit.bordered = NO; edit.controlSize = NSControlSizeSmall; edit.tag = idx;
        edit.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold]; edit.contentTintColor = [NSColor colorWithCalibratedRed:0.086 green:0.365 blue:1.0 alpha:1.0];
        edit.wantsLayer = YES; edit.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.91 green:0.95 blue:1.0 alpha:1.0].CGColor; edit.layer.cornerRadius = 6;
        [edit.widthAnchor constraintEqualToConstant:52].active = YES; [edit.heightAnchor constraintEqualToConstant:28].active = YES;
        NSButton *remove = [NSButton buttonWithTitle:@"删除" target:self action:@selector(deleteCompanyFromList:)];
        remove.bordered = NO; remove.controlSize = NSControlSizeSmall; remove.tag = idx;
        remove.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium]; remove.contentTintColor = [NSColor colorWithCalibratedRed:0.96 green:0.27 blue:0.29 alpha:1.0];
        [row addArrangedSubview:logo]; [row addArrangedSubview:info]; [row addArrangedSubview:[[NSView alloc] init]]; [row addArrangedSubview:edit]; [row addArrangedSubview:remove];
        [self.companyCardsStack addArrangedSubview:card];
        [card.widthAnchor constraintEqualToAnchor:self.companyCardsStack.widthAnchor].active = YES;
    }];
}

- (void)addCompanyFromList:(id)sender {
    [self newCompany:nil];
    [self.settingsPanel center];
    [self.settingsPanel makeKeyAndOrderFront:nil];
}

- (void)editCompanyFromList:(NSButton *)sender {
    if (sender.tag >= (NSInteger)self.monitors.count) return;
    [self.companySelector selectItemAtIndex:sender.tag];
    [self loadSelectedCompany:nil];
    [self.settingsPanel center];
    [self.settingsPanel makeKeyAndOrderFront:nil];
}

- (void)deleteCompanyFromList:(NSButton *)sender {
    if (sender.tag >= (NSInteger)self.monitors.count) return;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"删除 %@？", self.monitors[sender.tag][@"company"] ?: @"这家公司"];
    alert.informativeText = @"删除后将停止该公司的岗位检查。";
    [alert addButtonWithTitle:@"删除"];
    [alert addButtonWithTitle:@"取消"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    [self.monitors removeObjectAtIndex:sender.tag];
    [self writeConfig:@{@"monitors": self.monitors}];
    [self refreshCompanySelector];
    [self refreshCompanyCards];
}

- (void)buildAlertListPanel {
    NSRect frame = NSMakeRect(0, 0, 460, 500);
    self.alertListPanel = [[NSPanel alloc] initWithContentRect:frame styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    self.alertListPanel.title = @"职位提醒";
    self.alertListPanel.releasedWhenClosed = NO;
    self.alertListPanel.level = NSFloatingWindowLevel;

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:self.alertListPanel.contentView.bounds];
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scroll.hasVerticalScroller = YES;
    scroll.drawsBackground = NO;

    FlippedView *document = [[FlippedView alloc] init];
    document.translatesAutoresizingMaskIntoConstraints = NO;
    self.alertListStack = [[NSStackView alloc] init];
    self.alertListStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.alertListStack.alignment = NSLayoutAttributeLeading;
    self.alertListStack.spacing = 10;
    self.alertListStack.edgeInsets = NSEdgeInsetsMake(18, 18, 18, 18);
    self.alertListStack.translatesAutoresizingMaskIntoConstraints = NO;
    [document addSubview:self.alertListStack];
    scroll.documentView = document;
    self.alertListPanel.contentView = scroll;
    [NSLayoutConstraint activateConstraints:@[
        [document.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor],
        [self.alertListStack.leadingAnchor constraintEqualToAnchor:document.leadingAnchor],
        [self.alertListStack.trailingAnchor constraintEqualToAnchor:document.trailingAnchor],
        [self.alertListStack.topAnchor constraintEqualToAnchor:document.topAnchor],
        [self.alertListStack.bottomAnchor constraintEqualToAnchor:document.bottomAnchor]
    ]];
}

- (void)refreshAlertList {
    for (NSView *view in self.alertListStack.arrangedSubviews.copy) {
        [self.alertListStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }

    NSArray<NSDictionary *> *jobs = self.currentJobs ?: @[];
    NSMutableArray<NSString *> *groupOrder = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *groups = [NSMutableDictionary dictionary];
    for (NSDictionary *job in jobs) {
        NSString *company = [job[@"company"] isKindOfClass:NSString.class] ? job[@"company"] : @"未知公司";
        NSString *detected = [job[@"detected_at"] isKindOfClass:NSString.class] ? job[@"detected_at"] : @"未记录时间";
        NSString *key = [NSString stringWithFormat:@"%@|%@", detected, company];
        if (!groups[key]) { groups[key] = [NSMutableArray array]; [groupOrder addObject:key]; }
        [groups[key] addObject:job];
    }

    for (NSString *key in [groupOrder reverseObjectEnumerator]) {
        NSArray<NSDictionary *> *items = groups[key];
        NSDictionary *first = items.firstObject;
        NSString *company = first[@"company"] ?: @"未知公司";
        NSString *detected = first[@"detected_at"] ?: @"未记录时间";

        NSView *card = [[NSView alloc] init];
        card.wantsLayer = YES;
        card.layer.borderWidth = 1;
        card.layer.borderColor = [NSColor colorWithWhite:0.90 alpha:1.0].CGColor;
        card.layer.backgroundColor = [NSColor colorWithWhite:1.0 alpha:0.96].CGColor;
        card.layer.cornerRadius = 10;
        NSStackView *content = [[NSStackView alloc] init];
        content.orientation = NSUserInterfaceLayoutOrientationVertical;
        content.alignment = NSLayoutAttributeLeading;
        content.spacing = 7;
        content.edgeInsets = NSEdgeInsetsMake(12, 12, 12, 12);
        content.translatesAutoresizingMaskIntoConstraints = NO;
        [card addSubview:content];
        [NSLayoutConstraint activateConstraints:@[
            [content.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
            [content.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
            [content.topAnchor constraintEqualToAnchor:card.topAnchor],
            [content.bottomAnchor constraintEqualToAnchor:card.bottomAnchor]
        ]];

        NSTextField *summary = [self label:[NSString stringWithFormat:@"%@发布了 %lu 个相关岗位", company, items.count] size:13 color:NSColor.labelColor];
        summary.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
        [content addArrangedSubview:summary];

        NSMutableOrderedSet *publishedTimes = [NSMutableOrderedSet orderedSet];
        for (NSDictionary *item in items) if ([item[@"published_at"] isKindOfClass:NSString.class] && [item[@"published_at"] length]) [publishedTimes addObject:item[@"published_at"]];
        NSString *published = publishedTimes.count ? [[publishedTimes array] componentsJoinedByString:@"、"] : @"未提供";
        NSTextField *timeTags = [self label:[NSString stringWithFormat:@"提醒 %@   ·   发布 %@", detected, published] size:10 color:NSColor.secondaryLabelColor];
        [content addArrangedSubview:timeTags];

        for (NSDictionary *item in items) {
            NSStackView *row = [[NSStackView alloc] init];
            row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
            row.alignment = NSLayoutAttributeCenterY;
            row.spacing = 8;
            NSString *jobName = [item[@"job"] isKindOfClass:NSString.class] ? item[@"job"] : @"职位详情";
            NSTextField *name = [self label:jobName size:11 color:[NSColor colorWithWhite:0.25 alpha:1.0]];
            name.lineBreakMode = NSLineBreakByTruncatingTail;
            [name setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
            NSButton *open = [NSButton buttonWithTitle:@"查看  →" target:self action:@selector(openJobFromMenu:)];
            open.bezelStyle = NSBezelStyleInline;
            open.controlSize = NSControlSizeMini;
            open.font = [NSFont systemFontOfSize:10 weight:NSFontWeightSemibold];
            open.identifier = item[@"url"] ?: @"";
            [row addArrangedSubview:name];
            [row addArrangedSubview:[[NSView alloc] init]];
            [row addArrangedSubview:open];
            [content addArrangedSubview:row];
            [row.widthAnchor constraintEqualToAnchor:content.widthAnchor constant:-24].active = YES;
        }
        [self.alertListStack addArrangedSubview:card];
        [card.widthAnchor constraintEqualToAnchor:self.alertListStack.widthAnchor constant:-36].active = YES;
    }
}

- (void)refreshBubbleAlertList {
    for (NSView *view in self.bubbleAlertStack.arrangedSubviews.copy) {
        [self.bubbleAlertStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    NSMutableArray<NSDictionary *> *visibleJobs = [NSMutableArray array];
    for (NSDictionary *job in self.currentJobs) if (![job[@"archived"] boolValue]) [visibleJobs addObject:job];
    if (visibleJobs.count == 0) {
        NSData *lastRunData = [NSData dataWithContentsOfFile:LastRunPath];
        NSDictionary *lastRuns = lastRunData ? [NSJSONSerialization JSONObjectWithData:lastRunData options:0 error:nil] : nil;
        NSDate *latestScan = nil;
        if ([lastRuns isKindOfClass:NSDictionary.class]) {
            NSISO8601DateFormatter *iso = [[NSISO8601DateFormatter alloc] init];
            for (id value in lastRuns.allValues) {
                if (![value isKindOfClass:NSString.class]) continue;
                NSDate *date = [iso dateFromString:value];
                if (date && (!latestScan || [date compare:latestScan] == NSOrderedDescending)) latestScan = date;
            }
        }
        NSView *emptyCard = [[NSView alloc] init];
        emptyCard.wantsLayer = YES;
        emptyCard.layer.backgroundColor = [NSColor colorWithWhite:0.97 alpha:1.0].CGColor;
        emptyCard.layer.cornerRadius = 12;
        NSStackView *emptyStack = [[NSStackView alloc] init];
        emptyStack.orientation = NSUserInterfaceLayoutOrientationVertical;
        emptyStack.alignment = NSLayoutAttributeCenterX;
        emptyStack.spacing = 6;
        emptyStack.edgeInsets = NSEdgeInsetsMake(26, 12, 26, 12);
        emptyStack.translatesAutoresizingMaskIntoConstraints = NO;
        [emptyCard addSubview:emptyStack];
        NSImageView *icon = [[NSImageView alloc] init];
        icon.image = [NSImage imageWithSystemSymbolName:(latestScan ? @"checkmark.circle.fill" : @"bell.slash") accessibilityDescription:nil];
        icon.contentTintColor = latestScan ? [NSColor colorWithCalibratedRed:0.16 green:0.62 blue:0.36 alpha:1.0] : [NSColor colorWithWhite:0.65 alpha:1.0];
        [icon.widthAnchor constraintEqualToConstant:24].active = YES;
        [icon.heightAnchor constraintEqualToConstant:24].active = YES;
        NSTextField *emptyTitle = [self label:(latestScan ? @"本次检索完成" : @"还没有新岗位") size:12 color:NSColor.labelColor];
        emptyTitle.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
        [emptyStack addArrangedSubview:icon];
        [emptyStack addArrangedSubview:emptyTitle];
        NSString *detail = @"发现符合条件的实习岗位后，会在这里提醒你";
        if (latestScan) {
            NSDateFormatter *display = [[NSDateFormatter alloc] init];
            display.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
            display.dateFormat = @"MM月dd日 HH:mm";
            detail = [NSString stringWithFormat:@"%@ · 暂无新增匹配岗位", [display stringFromDate:latestScan]];
        }
        [emptyStack addArrangedSubview:[self label:detail size:9 color:NSColor.secondaryLabelColor]];
        [self.bubbleAlertStack addArrangedSubview:emptyCard];
        [emptyCard.widthAnchor constraintEqualToAnchor:self.bubbleAlertStack.widthAnchor constant:-4].active = YES;
        [NSLayoutConstraint activateConstraints:@[
            [emptyStack.leadingAnchor constraintEqualToAnchor:emptyCard.leadingAnchor],
            [emptyStack.trailingAnchor constraintEqualToAnchor:emptyCard.trailingAnchor],
            [emptyStack.topAnchor constraintEqualToAnchor:emptyCard.topAnchor],
            [emptyStack.bottomAnchor constraintEqualToAnchor:emptyCard.bottomAnchor]
        ]];
        return;
    }

    NSMutableArray<NSString *> *timeOrder = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *timeGroups = [NSMutableDictionary dictionary];
    for (NSDictionary *job in visibleJobs) {
        NSString *detected = [job[@"detected_at"] isKindOfClass:NSString.class] ? job[@"detected_at"] : @"未记录时间";
        if (!timeGroups[detected]) { timeGroups[detected] = [NSMutableArray array]; [timeOrder addObject:detected]; }
        [timeGroups[detected] addObject:job];
    }

    for (NSString *detected in [timeOrder reverseObjectEnumerator]) {
        NSStackView *section = [[NSStackView alloc] init];
        section.orientation = NSUserInterfaceLayoutOrientationVertical;
        section.alignment = NSLayoutAttributeLeading;
        section.spacing = 6;
        NSTextField *timeTitle = [self label:detected size:12 color:NSColor.labelColor];
        timeTitle.font = [NSFont systemFontOfSize:12 weight:NSFontWeightBold];
        [section addArrangedSubview:timeTitle];

        NSMutableArray<NSString *> *companyOrder = [NSMutableArray array];
        NSMutableDictionary<NSString *, NSMutableArray<NSDictionary *> *> *companyGroups = [NSMutableDictionary dictionary];
        for (NSDictionary *job in timeGroups[detected]) {
            NSString *company = [job[@"company"] isKindOfClass:NSString.class] ? job[@"company"] : @"未知公司";
            if (!companyGroups[company]) { companyGroups[company] = [NSMutableArray array]; [companyOrder addObject:company]; }
            [companyGroups[company] addObject:job];
        }

        for (NSString *company in companyOrder) {
            NSArray<NSDictionary *> *items = companyGroups[company];
            NSString *groupKey = [NSString stringWithFormat:@"%@|%@", detected, company];
            BOOL isRead = YES;
            for (NSDictionary *item in items) if (![item[@"read"] boolValue]) { isRead = NO; break; }
            NSView *card = [[NSView alloc] init];
            card.wantsLayer = YES;
            card.layer.backgroundColor = [NSColor colorWithWhite:isRead ? 0.975 : 0.945 alpha:1.0].CGColor;
            card.layer.cornerRadius = 9;
            NSStackView *row = [[NSStackView alloc] init];
            row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
            row.alignment = NSLayoutAttributeCenterY;
            row.spacing = 6;
            row.edgeInsets = NSEdgeInsetsMake(9, 10, 9, 10);
            row.translatesAutoresizingMaskIntoConstraints = NO;
            [card addSubview:row];
            [NSLayoutConstraint activateConstraints:@[
                [row.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
                [row.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
                [row.topAnchor constraintEqualToAnchor:card.topAnchor],
                [row.bottomAnchor constraintEqualToAnchor:card.bottomAnchor]
            ]];
            NSStackView *info = [[NSStackView alloc] init];
            info.orientation = NSUserInterfaceLayoutOrientationVertical;
            info.alignment = NSLayoutAttributeLeading;
            info.spacing = 4;
            NSView *statusDot = [[NSView alloc] init];
            statusDot.wantsLayer = YES;
            statusDot.layer.backgroundColor = (isRead ? [NSColor colorWithWhite:0.75 alpha:1.0] : [NSColor colorWithCalibratedRed:0.20 green:0.44 blue:1.0 alpha:1.0]).CGColor;
            statusDot.layer.cornerRadius = 3;
            [statusDot.widthAnchor constraintEqualToConstant:6].active = YES;
            [statusDot.heightAnchor constraintEqualToConstant:6].active = YES;
            NSTextField *summary = [self label:[NSString stringWithFormat:@"%@发布了 %lu 个相关岗位", company, items.count] size:11 color:isRead ? NSColor.secondaryLabelColor : NSColor.labelColor];
            summary.font = [NSFont systemFontOfSize:11 weight:NSFontWeightSemibold];
            NSMutableOrderedSet *times = [NSMutableOrderedSet orderedSet];
            for (NSDictionary *item in items) if ([item[@"published_at"] isKindOfClass:NSString.class] && [item[@"published_at"] length]) [times addObject:item[@"published_at"]];
            NSString *published = times.count ? [[times array] componentsJoinedByString:@"、"] : @"未提供";
            [info addArrangedSubview:summary];
            [info addArrangedSubview:[self label:[NSString stringWithFormat:@"发布时间  %@", published] size:9 color:NSColor.secondaryLabelColor]];
            [summary setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
            NSButton *view = [NSButton buttonWithTitle:(isRead ? @"已查看" : @"查看") target:self action:@selector(openJobGroup:)];
            view.bordered = NO;
            view.font = [NSFont systemFontOfSize:10 weight:NSFontWeightSemibold];
            view.contentTintColor = NSColor.whiteColor;
            view.wantsLayer = YES;
            view.layer.backgroundColor = [NSColor colorWithWhite:(isRead ? 0.78 : 0.25) alpha:1.0].CGColor;
            view.layer.cornerRadius = 6;
            view.identifier = groupKey;
            [view.widthAnchor constraintEqualToConstant:48].active = YES;
            [view.heightAnchor constraintEqualToConstant:24].active = YES;
            [row addArrangedSubview:statusDot];
            [row addArrangedSubview:info];
            [row addArrangedSubview:[[NSView alloc] init]];
            [row addArrangedSubview:view];
            [section addArrangedSubview:card];
            [card.widthAnchor constraintEqualToAnchor:section.widthAnchor].active = YES;
        }
        [self.bubbleAlertStack addArrangedSubview:section];
        [section.widthAnchor constraintEqualToAnchor:self.bubbleAlertStack.widthAnchor constant:-4].active = YES;
    }
}

- (void)buildSettings {
    NSRect frame = NSMakeRect(0, 0, 520, 500);
    // 现代 macOS 风格窗口
    self.settingsPanel = [[NSPanel alloc] initWithContentRect:frame styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskFullSizeContentView backing:NSBackingStoreBuffered defer:NO];
    self.settingsPanel.title = @""; // 标题写在正文中
    self.settingsPanel.titlebarAppearsTransparent = YES;
    self.settingsPanel.releasedWhenClosed = NO;
    self.settingsPanel.level = NSFloatingWindowLevel;
    
    NSView *bg = [[NSView alloc] initWithFrame:frame];
    bg.wantsLayer = YES;
    bg.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.969 green:0.976 blue:0.988 alpha:1.0].CGColor;
    self.settingsPanel.contentView = bg;

    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 11;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [bg addSubview:stack];
    
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:bg.leadingAnchor constant:36],
        [stack.trailingAnchor constraintEqualToAnchor:bg.trailingAnchor constant:-36],
        [stack.topAnchor constraintEqualToAnchor:bg.topAnchor constant:34]
    ]];

    // 头部
    NSTextField *heading = [self label:@"岗位监控配置" size:22 color:[NSColor colorWithCalibratedRed:0.10 green:0.12 blue:0.16 alpha:1.0]];
    heading.font = [NSFont systemFontOfSize:22 weight:NSFontWeightBold];
    [stack addArrangedSubview:heading];
    [stack addArrangedSubview:[self label:@"配置招聘网址和监控岗位。每天 09:30 与 18:30 自动检查。" size:12 color:[NSColor colorWithCalibratedRed:0.53 green:0.57 blue:0.62 alpha:1.0]]];
    
    [stack addArrangedSubview:[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 4)]]; // Spacer

    // 公司列表的增删改入口统一放在“监控公司”页面；这里仅保留隐藏选择器用于编辑数据定位。
    self.companySelector = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.companySelector.target = self;
    self.companySelector.action = @selector(loadSelectedCompany:);
    
    // 表单：先填招聘网址，自动识别公司名称
    [stack addArrangedSubview:[self label:@"官方招聘网址  *" size:13 color:NSColor.labelColor]];
    self.companyURLField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.companyURLField.placeholderString = @"https://careers.example.com/jobs";
    self.companyURLField.controlSize = NSControlSizeLarge;
    self.companyURLField.delegate = self;
    self.companyURLField.font = [NSFont systemFontOfSize:13];
    self.companyURLField.wantsLayer = YES;
    self.companyURLField.bezelStyle = NSTextFieldRoundedBezel;
    self.companyURLField.layer.cornerRadius = 8;
    [self.companyURLField.widthAnchor constraintEqualToConstant:448].active = YES;
    [self.companyURLField.heightAnchor constraintEqualToConstant:38].active = YES;
    [stack addArrangedSubview:self.companyURLField];
    self.companyURLError = [self label:@"" size:10 color:NSColor.systemRedColor];
    self.companyURLError.hidden = YES;
    [stack addArrangedSubview:self.companyURLError];

    [stack addArrangedSubview:[self label:@"公司名称  *" size:13 color:NSColor.labelColor]];
    self.companyNameField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.companyNameField.placeholderString = @"根据网址自动识别，也可手动修改";
    self.companyNameField.controlSize = NSControlSizeLarge;
    self.companyNameField.delegate = self;
    self.companyNameField.font = [NSFont systemFontOfSize:13];
    self.companyNameField.wantsLayer = YES;
    self.companyNameField.bezelStyle = NSTextFieldRoundedBezel;
    self.companyNameField.layer.cornerRadius = 8;
    [self.companyNameField.widthAnchor constraintEqualToConstant:448].active = YES;
    [self.companyNameField.heightAnchor constraintEqualToConstant:38].active = YES;
    [stack addArrangedSubview:self.companyNameField];
    self.companyNameError = [self label:@"" size:10 color:NSColor.systemRedColor];
    self.companyNameError.hidden = YES;
    [stack addArrangedSubview:self.companyNameError];

    NSTextField *roleTitle = [self label:@"岗位方向（可多选）" size:14 color:NSColor.labelColor];
    roleTitle.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
    [stack addArrangedSubview:roleTitle];
    
    self.roleTokenField = [[NSTokenField alloc] initWithFrame:NSZeroRect];
    self.roleTokenField.placeholderString = @"输入搜索并选择：Product、AI / 机器学习…";
    self.roleTokenField.tokenizingCharacterSet = [NSCharacterSet characterSetWithCharactersInString:@",，\n"];
    self.roleTokenField.completionDelay = 0;
    self.roleTokenField.delegate = self;
    self.roleTokenField.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    self.roleTokenField.tokenStyle = NSTokenStyleRounded;
    self.roleTokenField.bordered = NO;
    self.roleTokenField.drawsBackground = NO;
    self.roleTokenField.focusRingType = NSFocusRingTypeNone;
    self.roleTokenField.translatesAutoresizingMaskIntoConstraints = NO;
    NSButton *roleDisclosure = [NSButton buttonWithTitle:@"⌄" target:self action:@selector(showRolePicker:)];
    roleDisclosure.bordered = NO;
    roleDisclosure.font = [NSFont systemFontOfSize:16 weight:NSFontWeightMedium];
    roleDisclosure.contentTintColor = NSColor.secondaryLabelColor;
    roleDisclosure.toolTip = @"展开岗位方向";
    roleDisclosure.translatesAutoresizingMaskIntoConstraints = NO;
    NSView *roleInput = [[NSView alloc] initWithFrame:NSZeroRect];
    roleInput.wantsLayer = YES;
    roleInput.layer.backgroundColor = NSColor.controlBackgroundColor.CGColor;
    roleInput.layer.borderColor = [NSColor colorWithCalibratedRed:0.82 green:0.84 blue:0.88 alpha:1].CGColor;
    roleInput.layer.borderWidth = 1;
    roleInput.layer.cornerRadius = 9;
    [roleInput.widthAnchor constraintEqualToConstant:448].active = YES;
    [roleInput.heightAnchor constraintEqualToConstant:40].active = YES;
    [roleInput addSubview:self.roleTokenField];
    [roleInput addSubview:roleDisclosure];
    [NSLayoutConstraint activateConstraints:@[
        [self.roleTokenField.leadingAnchor constraintEqualToAnchor:roleInput.leadingAnchor constant:10],
        [self.roleTokenField.trailingAnchor constraintEqualToAnchor:roleDisclosure.leadingAnchor constant:-4],
        [self.roleTokenField.centerYAnchor constraintEqualToAnchor:roleInput.centerYAnchor],
        [self.roleTokenField.heightAnchor constraintEqualToConstant:30],
        [roleDisclosure.trailingAnchor constraintEqualToAnchor:roleInput.trailingAnchor constant:-4],
        [roleDisclosure.centerYAnchor constraintEqualToAnchor:roleInput.centerYAnchor],
        [roleDisclosure.widthAnchor constraintEqualToConstant:32],
        [roleDisclosure.heightAnchor constraintEqualToConstant:32]
    ]];
    [stack addArrangedSubview:roleInput];
    self.roleError = [self label:@"" size:10 color:NSColor.systemRedColor];
    self.roleError.hidden = YES;
    [stack addArrangedSubview:self.roleError];

    NSTextField *workTypeTitle = [self label:@"工作类型  *" size:14 color:NSColor.labelColor];
    workTypeTitle.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
    [stack addArrangedSubview:workTypeTitle];
    self.internshipRadio = [NSButton radioButtonWithTitle:@"Internship / 实习" target:nil action:nil];
    self.internshipRadio.state = NSControlStateValueOn;
    self.internshipRadio.contentTintColor = [NSColor colorWithCalibratedRed:0.086 green:0.365 blue:1.0 alpha:1.0];
    [stack addArrangedSubview:self.internshipRadio];

    [stack addArrangedSubview:[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10, 8)]]; // Spacer
    NSBox *sep2 = [[NSBox alloc] init]; sep2.boxType = NSBoxSeparator; [sep2.widthAnchor constraintEqualToConstant:448].active = YES; [stack addArrangedSubview:sep2];
    
    NSButton *save = [NSButton buttonWithTitle:@"保存配置" target:self action:@selector(saveSettings:)];
    save.bordered = NO;
    save.controlSize = NSControlSizeLarge;
    save.contentTintColor = NSColor.whiteColor;
    save.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    save.wantsLayer = YES;
    save.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.086 green:0.365 blue:1.0 alpha:1.0].CGColor;
    save.layer.cornerRadius = 6;
    [save.widthAnchor constraintEqualToConstant:104].active = YES;
    [save.heightAnchor constraintEqualToConstant:34].active = YES;
    save.keyEquivalent = @"\r";
    save.translatesAutoresizingMaskIntoConstraints = NO;
    [bg addSubview:save];
    [NSLayoutConstraint activateConstraints:@[
        [save.trailingAnchor constraintEqualToAnchor:bg.trailingAnchor constant:-36],
        [save.bottomAnchor constraintEqualToAnchor:bg.bottomAnchor constant:-24]
    ]];
}

- (NSArray<NSString *> *)roleDisplayChoices {
    return @[@"产品 / Product", @"AI / 机器学习", @"数据 / Data", @"软件 / Software",
             @"设计 / Design", @"运营 / Operations", @"市场 / Marketing", @"硬件 / Hardware",
             @"供应链 / Supply Chain", @"财务 / Finance", @"人力资源 / HR"];
}

- (NSDictionary<NSString *, NSString *> *)roleDisplayToValue {
    return @{@"产品 / Product": @"Product", @"AI / 机器学习": @"AI/ML",
             @"数据 / Data": @"Data", @"软件 / Software": @"Software", @"设计 / Design": @"Design",
             @"运营 / Operations": @"Operations", @"市场 / Marketing": @"Marketing", @"硬件 / Hardware": @"Hardware",
             @"供应链 / Supply Chain": @"Supply Chain", @"财务 / Finance": @"Finance", @"人力资源 / HR": @"HR"};
}

- (NSDictionary<NSString *, NSString *> *)roleValueToDisplay {
    return @{@"Product": @"产品 / Product", @"AI/ML": @"AI / 机器学习",
             @"Data": @"数据 / Data", @"Software": @"软件 / Software", @"Design": @"设计 / Design",
             @"Operations": @"运营 / Operations", @"Marketing": @"市场 / Marketing", @"Hardware": @"硬件 / Hardware",
             @"Supply Chain": @"供应链 / Supply Chain", @"Finance": @"财务 / Finance", @"HR": @"人力资源 / HR"};
}

- (void)showRolePicker:(NSButton *)sender {
    if (!self.rolePopover) {
        self.rolePopover = [[NSPopover alloc] init];
        self.rolePopover.behavior = NSPopoverBehaviorTransient;
        NSViewController *controller = [[NSViewController alloc] init];
        NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 320, 292)];
        content.wantsLayer = YES;
        content.layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.985 alpha:1].CGColor;
        controller.view = content;

        self.roleSearchField = [[NSSearchField alloc] initWithFrame:NSZeroRect];
        self.roleSearchField.placeholderString = @"搜索中文或英文岗位";
        self.roleSearchField.font = [NSFont systemFontOfSize:12];
        self.roleSearchField.delegate = self;
        self.roleSearchField.translatesAutoresizingMaskIntoConstraints = NO;
        [content addSubview:self.roleSearchField];

        self.roleOptionsScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
        self.roleOptionsScroll.translatesAutoresizingMaskIntoConstraints = NO;
        self.roleOptionsScroll.drawsBackground = NO;
        self.roleOptionsScroll.borderType = NSNoBorder;
        self.roleOptionsScroll.hasVerticalScroller = YES;
        self.roleOptionsScroll.autohidesScrollers = YES;
        self.roleOptionsDocument = [[FlippedView alloc] initWithFrame:NSMakeRect(0, 0, 292, 360)];
        self.roleOptionsScroll.documentView = self.roleOptionsDocument;
        [content addSubview:self.roleOptionsScroll];

        self.roleOptionsStack = [[NSStackView alloc] initWithFrame:NSZeroRect];
        self.roleOptionsStack.orientation = NSUserInterfaceLayoutOrientationVertical;
        self.roleOptionsStack.alignment = NSLayoutAttributeLeading;
        self.roleOptionsStack.spacing = 3;
        self.roleOptionsStack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.roleOptionsDocument addSubview:self.roleOptionsStack];
        [NSLayoutConstraint activateConstraints:@[
            [self.roleSearchField.topAnchor constraintEqualToAnchor:content.topAnchor constant:14],
            [self.roleSearchField.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],
            [self.roleSearchField.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-14],
            [self.roleOptionsScroll.topAnchor constraintEqualToAnchor:self.roleSearchField.bottomAnchor constant:10],
            [self.roleOptionsScroll.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],
            [self.roleOptionsScroll.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-10],
            [self.roleOptionsScroll.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-10],
            [self.roleOptionsStack.topAnchor constraintEqualToAnchor:self.roleOptionsDocument.topAnchor],
            [self.roleOptionsStack.leadingAnchor constraintEqualToAnchor:self.roleOptionsDocument.leadingAnchor],
            [self.roleOptionsStack.widthAnchor constraintEqualToConstant:288]
        ]];
        self.rolePopover.contentViewController = controller;
        self.rolePopover.contentSize = NSMakeSize(320, 292);
    }
    self.roleSearchField.stringValue = @"";
    [self rebuildRoleOptions];
    [self.rolePopover showRelativeToRect:sender.bounds ofView:sender preferredEdge:NSRectEdgeMaxY];
    [self.roleSearchField becomeFirstResponder];
}

- (void)rebuildRoleOptions {
    for (NSView *view in self.roleOptionsStack.arrangedSubviews.copy) {
        [self.roleOptionsStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    NSString *query = self.roleSearchField.stringValue ?: @"";
    NSArray *selected = [self tokensFromField:self.roleTokenField];
    NSUInteger index = 0;
    for (NSString *choice in self.roleDisplayChoices) {
        if (query.length && [choice rangeOfString:query options:NSCaseInsensitiveSearch].location == NSNotFound) { index++; continue; }
        BOOL isSelected = [selected containsObject:choice];
        NSString *title = [NSString stringWithFormat:@"%@   %@", isSelected ? @"✓" : @" ", choice];
        NSButton *option = [NSButton buttonWithTitle:title target:self action:@selector(toggleRoleOption:)];
        option.tag = index;
        option.state = isSelected ? NSControlStateValueOn : NSControlStateValueOff;
        option.bordered = NO;
        option.alignment = NSTextAlignmentLeft;
        option.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
        option.contentTintColor = isSelected
            ? [NSColor colorWithCalibratedRed:0.08 green:0.32 blue:0.83 alpha:1]
            : [NSColor colorWithCalibratedRed:0.16 green:0.18 blue:0.22 alpha:1];
        option.wantsLayer = YES;
        option.layer.backgroundColor = isSelected
            ? [NSColor colorWithCalibratedRed:0.91 green:0.95 blue:1 alpha:1].CGColor
            : NSColor.clearColor.CGColor;
        option.layer.cornerRadius = 6;
        [option.widthAnchor constraintEqualToConstant:288].active = YES;
        [option.heightAnchor constraintEqualToConstant:30].active = YES;
        [self.roleOptionsStack addArrangedSubview:option];
        index++;
    }
    if (!self.roleOptionsStack.arrangedSubviews.count) {
        NSTextField *empty = [self label:@"没有匹配的固定方向" size:12 color:NSColor.secondaryLabelColor];
        [self.roleOptionsStack addArrangedSubview:empty];
    }
    CGFloat documentHeight = MAX(214, self.roleOptionsStack.arrangedSubviews.count * 33);
    [self.roleOptionsDocument setFrameSize:NSMakeSize(292, documentHeight)];
    [self.roleOptionsDocument layoutSubtreeIfNeeded];
    [self.roleOptionsScroll.contentView scrollToPoint:NSMakePoint(0, 0)];
    [self.roleOptionsScroll reflectScrolledClipView:self.roleOptionsScroll.contentView];
}

- (void)toggleRoleOption:(NSButton *)sender {
    NSString *choice = self.roleDisplayChoices[sender.tag];
    NSMutableArray *selected = [[self tokensFromField:self.roleTokenField] mutableCopy];
    if ([selected containsObject:choice]) [selected removeObject:choice];
    else [selected addObject:choice];
    self.roleTokenField.objectValue = selected;
    self.roleError.hidden = YES;
    [self rebuildRoleOptions];
}

- (NSArray<NSString *> *)control:(NSControl *)control textView:(NSTextView *)textView
                     completions:(NSArray<NSString *> *)words
            forPartialWordRange:(NSRange)charRange
            indexOfSelectedItem:(NSInteger *)index {
    if (control != self.roleTokenField) return @[];
    NSString *partial = charRange.location != NSNotFound && NSMaxRange(charRange) <= textView.string.length
        ? [textView.string substringWithRange:charRange] : @"";
    NSMutableArray<NSString *> *matches = [NSMutableArray array];
    NSArray *selected = [self tokensFromField:self.roleTokenField];
    for (NSString *choice in self.roleDisplayChoices) {
        BOOL matchesSearch = partial.length == 0 || [choice rangeOfString:partial options:NSCaseInsensitiveSearch].location != NSNotFound;
        if (matchesSearch && ![selected containsObject:choice]) [matches addObject:choice];
    }
    if (index) *index = matches.count ? 0 : -1;
    return matches;
}

- (BOOL)isValidCompanyName:(NSString *)name {
    NSString *pattern = @"^[A-Za-z0-9\\p{Han}&.()' -]{2,60}$";
    return [name rangeOfString:pattern options:NSRegularExpressionSearch].location != NSNotFound;
}

- (BOOL)isValidCareerURL:(NSString *)value {
    NSString *pattern = @"^https?://([A-Za-z0-9-]+\\.)+[A-Za-z]{2,}(:[0-9]+)?(/[^\\s]*)?$";
    if ([value rangeOfString:pattern options:NSRegularExpressionSearch].location == NSNotFound) return NO;
    NSURLComponents *components = [NSURLComponents componentsWithString:value];
    return components.host.length > 0;
}

- (NSString *)companyNameFromURL:(NSString *)value {
    NSString *host = [NSURLComponents componentsWithString:value].host.lowercaseString;
    if (!host.length) return nil;
    NSDictionary *known = @{@"micron": @"Micron", @"bytedance": @"ByteDance", @"tiktok": @"TikTok",
        @"shopee": @"Shopee", @"sea.com": @"Sea", @"grab": @"Grab", @"amazon": @"Amazon",
        @"google": @"Google", @"meta": @"Meta", @"microsoft": @"Microsoft", @"apple": @"Apple",
        @"netflix": @"Netflix", @"nvidia": @"NVIDIA", @"tesla": @"Tesla", @"linkedin": @"LinkedIn",
        @"accenture": @"Accenture", @"jpmorgan": @"JPMorgan", @"dbs": @"DBS", @"govtech": @"GovTech"};
    for (NSString *key in known) if ([host containsString:key]) return known[key];
    NSArray *parts = [host componentsSeparatedByString:@"."];
    NSArray *ignored = @[@"www", @"jobs", @"careers", @"career", @"apply"];
    for (NSString *part in parts) if (part.length > 1 && ![ignored containsObject:part] && ![@[@"com", @"org", @"net", @"io", @"sg"] containsObject:part]) return part.capitalizedString;
    return nil;
}

- (void)updateCompanyNameFromURL {
    NSString *name = [self companyNameFromURL:self.companyURLField.stringValue];
    if (name.length && (self.companyNameField.stringValue.length == 0 || self.companyNameAutoFilled)) {
        self.companyNameAutoFilled = YES;
        self.companyNameField.stringValue = name;
        self.companyNameError.hidden = YES;
    }
}

- (void)controlTextDidChange:(NSNotification *)notification {
    NSTextField *field = notification.object;
    if (field == self.roleSearchField) {
        [self rebuildRoleOptions];
    } else if (field == self.companyNameField) {
        self.companyNameAutoFilled = NO;
        self.companyNameError.hidden = YES;
    } else if (field == self.companyURLField) {
        self.companyURLError.hidden = YES;
        [self updateCompanyNameFromURL];
    } else if (field == self.roleTokenField) {
        self.roleError.hidden = YES;
    }
}

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    if (notification.object == self.companyURLField) [self updateCompanyNameFromURL];
}

- (void)controlTextDidBeginEditing:(NSNotification *)notification {
    if (notification.object == self.companyNameField) self.companyNameError.hidden = YES;
    if (notification.object == self.companyURLField) self.companyURLError.hidden = YES;
    if (notification.object == self.roleTokenField) self.roleError.hidden = YES;
}

- (NSArray<NSString *> *)tokensFromField:(NSTokenField *)field {
    id value = field.objectValue;
    NSArray *raw = [value isKindOfClass:NSArray.class] ? value : (field.stringValue.length ? [field.stringValue componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@",，\n"]] : @[]);
    NSMutableOrderedSet<NSString *> *tokens = [NSMutableOrderedSet orderedSet];
    for (id entry in raw) {
        NSString *token = [[entry description] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (token.length) [tokens addObject:token];
    }
    return tokens.array;
}

- (NSDictionary *)defaultConfig {
    return @{@"monitors": @[]};
}

- (void)loadSettings {
    NSData *data = [NSData dataWithContentsOfFile:ConfigPath];
    NSDictionary *config = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![config isKindOfClass:NSDictionary.class]) config = self.defaultConfig;
    NSArray *items = config[@"monitors"];
    if (![items isKindOfClass:NSArray.class]) items = self.defaultConfig[@"monitors"];
    self.monitors = [NSMutableArray array];
    for (NSDictionary *item in items) [self.monitors addObject:[item mutableCopy]];
    [self refreshCompanySelector];
    if (self.monitors.count > 0) {
        [self.companySelector selectItemAtIndex:0];
        [self loadSelectedCompany:nil];
    } else [self newCompany:nil];
    if (!data || !config[@"monitors"]) [self writeConfig:@{@"monitors": self.monitors}];
}

- (void)refreshCompanySelector {
    [self.companySelector removeAllItems];
    for (NSDictionary *item in self.monitors) [self.companySelector addItemWithTitle:item[@"company"] ?: @"未命名公司"];
}

- (void)loadSelectedCompany:(id)sender {
    NSInteger index = self.companySelector.indexOfSelectedItem;
    if (index < 0 || index >= (NSInteger)self.monitors.count) return;
    self.editingIndex = index;
    NSDictionary *item = self.monitors[index];
    self.companyNameField.stringValue = item[@"company"] ?: @"";
    self.companyURLField.stringValue = item[@"url"] ?: @"";
    NSArray *roles = item[@"roles"] ?: @[];
    NSDictionary *displayNames = self.roleValueToDisplay;
    NSMutableArray *displayRoles = [NSMutableArray array];
    for (NSString *role in roles) if (displayNames[role]) [displayRoles addObject:displayNames[role]];
    self.roleTokenField.objectValue = displayRoles;
    self.internshipRadio.state = [item[@"internship_only"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    self.companyNameAutoFilled = NO;
}

- (void)newCompany:(id)sender {
    self.editingIndex = NSNotFound;
    [self.companySelector selectItem:nil];
    self.companyNameField.stringValue = @"";
    self.companyURLField.stringValue = @"";
    self.roleTokenField.objectValue = @[];
    self.internshipRadio.state = NSControlStateValueOn;
    self.companyNameError.hidden = self.companyURLError.hidden = self.roleError.hidden = YES;
    self.companyNameAutoFilled = NO;
    [self.companyURLField becomeFirstResponder];
}

- (void)deleteCompany:(id)sender {
    NSInteger index = self.companySelector.indexOfSelectedItem;
    if (index < 0 || index >= (NSInteger)self.monitors.count) return;
    [self.monitors removeObjectAtIndex:index];
    [self writeConfig:@{@"monitors": self.monitors}];
    [self refreshCompanySelector];
    if (self.monitors.count > 0) { [self.companySelector selectItemAtIndex:0]; [self loadSelectedCompany:nil]; }
    else [self newCompany:nil];
    [self refreshCompanyCards];
}

- (void)writeConfig:(NSDictionary *)config {
    NSData *data = [NSJSONSerialization dataWithJSONObject:config options:NSJSONWritingPrettyPrinted error:nil];
    [data writeToFile:ConfigPath atomically:YES];
}

- (void)saveSettings:(id)sender {
    NSString *company = [self.companyNameField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *url = [self.companyURLField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSArray<NSString *> *roleTokens = [self tokensFromField:self.roleTokenField];
    NSDictionary *roleMap = self.roleDisplayToValue;
    NSMutableArray *roles = [NSMutableArray array];
    BOOL validRoleTokens = YES;
    NSArray *canonicalRoles = @[@"Product", @"AI/ML", @"Data", @"Software", @"Design", @"Operations",
                                @"Marketing", @"Hardware", @"Supply Chain", @"Finance", @"HR"];
    for (NSString *token in roleTokens) {
        NSString *value = roleMap[token];
        if (!value && [canonicalRoles containsObject:token]) value = token;
        if (!value) { validRoleTokens = NO; break; }
        if (![roles containsObject:value]) [roles addObject:value];
    }
    BOOL validName = [self isValidCompanyName:company];
    BOOL validURL = [self isValidCareerURL:url];
    BOOL validRoles = validRoleTokens && roles.count > 0;
    BOOL validType = self.internshipRadio.state == NSControlStateValueOn;
    self.companyNameError.stringValue = company.length ? @"公司名称只能包含中英文、数字及 & . ( ) -" : @"请输入公司名称";
    self.companyURLError.stringValue = url.length ? @"请输入完整的 HTTP/HTTPS 官方招聘网址" : @"请输入官方招聘网址";
    self.roleError.stringValue = validRoleTokens ? @"请至少选择一个岗位方向" : @"岗位方向只能从下拉候选项中选择";
    self.companyNameError.hidden = validName;
    self.companyURLError.hidden = validURL;
    self.roleError.hidden = validRoles;
    if (!validName || !validURL || !validRoles || !validType) { NSBeep(); return; }
    NSMutableDictionary *item = [@{@"company": company, @"url": url,
                                   @"roles": roles} mutableCopy];
    item[@"internship_only"] = @(self.internshipRadio.state == NSControlStateValueOn);
    if (self.editingIndex == NSNotFound) { [self.monitors addObject:item]; self.editingIndex = self.monitors.count - 1; }
    else self.monitors[self.editingIndex] = item;
    [self writeConfig:@{@"monitors": self.monitors}];
    [self refreshCompanySelector];
    [self.companySelector selectItemAtIndex:self.editingIndex];
    self.companyLabel.stringValue = @"设置已更新";
    self.messageLabel.stringValue = [NSString stringWithFormat:@"已保存 %@ 的监控规则", company];
    self.metaLabel.stringValue = [NSString stringWithFormat:@"%lu 类岗位 · 09:30 / 18:30", roles.count];
    [self refreshCompanyCards];
    [self.settingsPanel orderOut:nil];
    [self.companyListPanel center];
    [self.companyListPanel makeKeyAndOrderFront:nil];
}

- (void)iconMoved:(NSNotification *)notification {
    if (self.bubbleVisible) [self positionBubbleNextToIcon];
}

- (void)showBubble {
    self.bubbleVisible = YES;
    [self positionBubbleNextToIcon];
    [self.iconPanel orderFront:nil];
    [self.bubblePanel makeKeyAndOrderFront:nil];
}

- (void)toggleBubble:(id)sender {
    if (self.bubbleVisible) {
        self.bubbleVisible = NO;
        [self.bubblePanel orderOut:nil];
    } else [self showBubble];
}

- (void)displayCompany:(NSString *)company job:(NSString *)job location:(NSString *)location category:(NSString *)category url:(NSString *)url {
    NSString *companyName = company.length ? company : @"新公司";
    self.companyLabel.stringValue = @"1 条更新";
    self.messageLabel.stringValue = [NSString stringWithFormat:@"%@ 发布了 1 个相关岗位", companyName];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    formatter.dateFormat = @"HH:mm";
    self.metaLabel.stringValue = [NSString stringWithFormat:@"提醒时间  今天 %@  ·  %@", [formatter stringFromDate:NSDate.date], location.length ? location : @"Singapore"];
    self.currentJobURL = url.length ? [NSURL URLWithString:url] : nil;
    self.currentJobs = self.currentJobURL ? @[@{@"company": company ?: @"", @"job": job ?: @"未命名职位", @"location": location ?: @"", @"category": category ?: @"", @"url": url}] : @[];
    self.openJobButton.enabled = (self.currentJobURL != nil);
    self.openJobButton.title = @"查看  →";
}

- (void)displayJobs:(NSArray<NSDictionary *> *)jobs {
    NSMutableArray<NSDictionary *> *validJobs = [NSMutableArray array];
    for (NSDictionary *job in jobs) {
        if (![job isKindOfClass:NSDictionary.class]) continue;
        NSString *url = [job[@"url"] isKindOfClass:NSString.class] ? job[@"url"] : @"";
        if (url.length > 0 && [NSURL URLWithString:url]) [validJobs addObject:job];
    }
    if (validJobs.count == 0) return;

    NSDictionary *first = validJobs.firstObject;
    NSString *company = [first[@"company"] isKindOfClass:NSString.class] ? first[@"company"] : @"新岗位";
    NSString *jobName = [first[@"job"] isKindOfClass:NSString.class] ? first[@"job"] : @"发现新的匹配岗位";
    NSString *location = [first[@"location"] isKindOfClass:NSString.class] ? first[@"location"] : @"Singapore";
    NSString *category = [first[@"category"] isKindOfClass:NSString.class] ? first[@"category"] : @"";
    [self displayCompany:company job:jobName location:location category:category url:first[@"url"]];
    self.currentJobs = validJobs;

    NSMutableOrderedSet<NSString *> *companies = [NSMutableOrderedSet orderedSet];
    for (NSDictionary *item in validJobs) {
        NSString *name = [item[@"company"] isKindOfClass:NSString.class] ? item[@"company"] : @"";
        if (name.length) [companies addObject:name];
    }
    NSString *publisher = companies.count == 1 ? companies.firstObject : [NSString stringWithFormat:@"%lu 家公司", companies.count];
    self.companyLabel.stringValue = [NSString stringWithFormat:@"%lu 条更新", validJobs.count];
    self.messageLabel.stringValue = [NSString stringWithFormat:@"%@发布了 %lu 个相关岗位", publisher, validJobs.count];
    self.openJobButton.title = @"查看  →";
    NSString *latestTime = [validJobs.lastObject[@"detected_at"] isKindOfClass:NSString.class] ? validJobs.lastObject[@"detected_at"] : nil;
    if (latestTime.length) self.metaLabel.stringValue = [NSString stringWithFormat:@"最近提醒  %@  ·  Singapore", latestTime];
    [self refreshBubbleAlertList];
    [self updateUnreadBadge];
}

- (NSArray<NSDictionary *> *)loadAlertHistory {
    NSData *data = [NSData dataWithContentsOfFile:AlertHistoryPath];
    NSDictionary *root = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    NSArray *jobs = [root[@"jobs"] isKindOfClass:NSArray.class] ? root[@"jobs"] : @[];
    NSDate *cutoff = [NSDate dateWithTimeIntervalSinceNow:-(14 * 24 * 60 * 60)];
    NSISO8601DateFormatter *iso = [[NSISO8601DateFormatter alloc] init];
    NSDateFormatter *legacy = [[NSDateFormatter alloc] init];
    legacy.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    legacy.dateFormat = @"yyyy年MM月dd日 HH:mm";
    NSInteger year = [NSCalendar.currentCalendar component:NSCalendarUnitYear fromDate:NSDate.date];
    NSMutableArray<NSDictionary *> *kept = [NSMutableArray array];
    for (NSDictionary *job in jobs) {
        NSDate *detectedDate = nil;
        if ([job[@"detected_at_iso"] isKindOfClass:NSString.class]) detectedDate = [iso dateFromString:job[@"detected_at_iso"]];
        if (!detectedDate && [job[@"detected_at"] isKindOfClass:NSString.class]) detectedDate = [legacy dateFromString:[NSString stringWithFormat:@"%ld年%@", year, job[@"detected_at"]]];
        if (!detectedDate || [detectedDate compare:cutoff] != NSOrderedAscending) [kept addObject:job];
    }
    if (kept.count != jobs.count) {
        NSData *cleaned = [NSJSONSerialization dataWithJSONObject:@{@"jobs": kept} options:NSJSONWritingPrettyPrinted error:nil];
        [cleaned writeToFile:AlertHistoryPath atomically:YES];
    }
    return kept;
}

- (NSArray<NSDictionary *> *)appendJobsToHistory:(NSArray<NSDictionary *> *)newJobs {
    NSMutableArray<NSDictionary *> *history = [[self loadAlertHistory] mutableCopy];
    NSMutableSet<NSString *> *knownURLs = [NSMutableSet set];
    for (NSDictionary *item in history) {
        NSString *url = [item[@"url"] isKindOfClass:NSString.class] ? item[@"url"] : @"";
        if (url.length) [knownURLs addObject:url];
    }

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    formatter.dateFormat = @"MM月dd日 HH:mm";
    NSString *detectedAt = [formatter stringFromDate:NSDate.date];
    NSString *detectedISO = [[[NSISO8601DateFormatter alloc] init] stringFromDate:NSDate.date];
    for (NSDictionary *item in newJobs) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        NSString *url = [item[@"url"] isKindOfClass:NSString.class] ? item[@"url"] : @"";
        if (url.length == 0 || [knownURLs containsObject:url]) continue;
        NSMutableDictionary *saved = [item mutableCopy];
        if (![saved[@"detected_at"] isKindOfClass:NSString.class] || [saved[@"detected_at"] length] == 0) saved[@"detected_at"] = detectedAt;
        if (![saved[@"detected_at_iso"] isKindOfClass:NSString.class] || [saved[@"detected_at_iso"] length] == 0) saved[@"detected_at_iso"] = detectedISO;
        [history addObject:saved];
        [knownURLs addObject:url];
    }
    if (history.count > 100) [history removeObjectsInRange:NSMakeRange(0, history.count - 100)];
    NSData *output = [NSJSONSerialization dataWithJSONObject:@{@"jobs": history} options:NSJSONWritingPrettyPrinted error:nil];
    [output writeToFile:AlertHistoryPath atomically:YES];
    return history;
}

- (void)openJobFromMenu:(id)item {
    NSURL *url = nil;
    if ([item respondsToSelector:@selector(representedObject)] && [[item representedObject] isKindOfClass:NSURL.class]) url = [item representedObject];
    else if ([item respondsToSelector:@selector(identifier)] && [[item identifier] isKindOfClass:NSString.class]) url = [NSURL URLWithString:[item identifier]];
    if (url) [NSWorkspace.sharedWorkspace openURL:url];
}

- (void)openJobGroup:(NSButton *)sender {
    NSArray<NSString *> *parts = [sender.identifier componentsSeparatedByString:@"|"];
    if (parts.count < 2) return;
    NSString *detected = parts.firstObject;
    NSString *company = [[parts subarrayWithRange:NSMakeRange(1, parts.count - 1)] componentsJoinedByString:@"|"];
    NSMutableArray<NSDictionary *> *updated = [NSMutableArray array];
    for (NSDictionary *job in self.currentJobs) {
        BOOL matches = [job[@"detected_at"] isEqualToString:detected] && [job[@"company"] isEqualToString:company];
        if (matches) {
            NSURL *url = [NSURL URLWithString:job[@"url"] ?: @""];
            if (url) [NSWorkspace.sharedWorkspace openURL:url];
            NSMutableDictionary *readJob = [job mutableCopy];
            readJob[@"read"] = @YES;
            [updated addObject:readJob];
        } else [updated addObject:job];
    }
    [self saveAlertHistoryJobs:updated];
}

- (void)saveAlertHistoryJobs:(NSArray<NSDictionary *> *)jobs {
    NSData *output = [NSJSONSerialization dataWithJSONObject:@{@"jobs": jobs ?: @[]} options:NSJSONWritingPrettyPrinted error:nil];
    [output writeToFile:AlertHistoryPath atomically:YES];
    self.currentJobs = jobs;
    [self refreshBubbleAlertList];
    [self updateUnreadBadge];
}

- (void)updateUnreadBadge {
    NSMutableSet<NSString *> *unreadGroups = [NSMutableSet set];
    for (NSDictionary *job in self.currentJobs) {
        if ([job[@"read"] boolValue]) continue;
        NSString *detected = [job[@"detected_at"] isKindOfClass:NSString.class] ? job[@"detected_at"] : @"";
        NSString *company = [job[@"company"] isKindOfClass:NSString.class] ? job[@"company"] : @"";
        [unreadGroups addObject:[NSString stringWithFormat:@"%@|%@", detected, company]];
    }
    NSUInteger count = unreadGroups.count;
    self.unreadBadge.hidden = (count == 0);
    self.unreadBadge.stringValue = count > 9 ? @"9+" : [NSString stringWithFormat:@"%lu", count];
}

- (void)openCurrentJob:(id)sender {
    [self refreshAlertList];
    [self.alertListPanel center];
    [self.alertListPanel makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)showCompanies:(id)sender {
    if (!self.monitors) [self loadSettings];
    [self refreshCompanyCards];
    [self.companyListPanel center];
    [self.companyListPanel makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    return;
    
    // 排版优化
    NSMutableParagraphStyle *titleStyle = [[NSMutableParagraphStyle alloc] init];
    titleStyle.paragraphSpacing = 4;
    
    NSMutableParagraphStyle *bodyStyle = [[NSMutableParagraphStyle alloc] init];
    bodyStyle.paragraphSpacing = 16;
    bodyStyle.lineSpacing = 4;

    NSMutableAttributedString *content = [[NSMutableAttributedString alloc] init];
    if (self.monitors.count == 0) {
        [content appendAttributedString:[[NSAttributedString alloc] initWithString:@"尚未添加公司监控规则。\n" attributes:@{NSForegroundColorAttributeName: NSColor.secondaryLabelColor, NSFontAttributeName: [NSFont systemFontOfSize:14]}]];
    }
    
    [self.monitors enumerateObjectsUsingBlock:^(NSDictionary *item, NSUInteger idx, BOOL *stop) {
        NSString *name = item[@"company"] ?: @"未命名公司";
        NSString *url = item[@"url"] ?: @"";
        NSString *roles = [item[@"roles"] componentsJoinedByString:@"、"] ?: @"";
        NSString *frequency = @"每天 09:30 与 18:30 检查";
        
        [content appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%lu. %@\n", idx + 1, name] attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:16 weight:NSFontWeightBold], NSForegroundColorAttributeName: NSColor.labelColor, NSParagraphStyleAttributeName: titleStyle}]];
        
        if (url.length > 0) {
            [content appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"网址：%@\n", url] attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:13], NSForegroundColorAttributeName: NSColor.systemBlueColor, NSLinkAttributeName: [NSURL URLWithString:url]}]];
        }
        
        [content appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"岗位：%@\n频率：%@\n", roles, frequency] attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:13], NSForegroundColorAttributeName: NSColor.secondaryLabelColor, NSParagraphStyleAttributeName: bodyStyle}]];
    }];
    
    [self.companyListText.textStorage setAttributedString:content];
    [self.companyListPanel center];
    [self.companyListPanel makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)showSettings:(id)sender {
    [self loadSettings];
    [self.settingsPanel center];
    [self.settingsPanel makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)startAlertWatcher {
    NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:AlertPath error:nil];
    self.lastAlertDate = attrs[NSFileModificationDate];
    NSDictionary *scanAttrs = [NSFileManager.defaultManager attributesOfItemAtPath:LastRunPath error:nil];
    self.lastScanDate = scanAttrs[NSFileModificationDate];
    NSArray *history = [self loadAlertHistory];
    if (history.count > 0) [self displayJobs:history];
    else [self refreshBubbleAlertList];
    self.alertTimer = [NSTimer scheduledTimerWithTimeInterval:15 target:self selector:@selector(checkForNewAlert:) userInfo:nil repeats:YES];
}

- (void)checkForNewAlert:(NSTimer *)timer {
    NSDictionary *scanAttrs = [NSFileManager.defaultManager attributesOfItemAtPath:LastRunPath error:nil];
    NSDate *scanModified = scanAttrs[NSFileModificationDate];
    NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:AlertPath error:nil];
    NSDate *modified = attrs[NSFileModificationDate];
    BOOL hasNewScan = scanModified && (!self.lastScanDate || [scanModified compare:self.lastScanDate] == NSOrderedDescending);
    BOOL hasNewAlert = modified && (!self.lastAlertDate || [modified compare:self.lastAlertDate] == NSOrderedDescending);
    if (!hasNewScan && !hasNewAlert) return;
    if (hasNewScan) self.lastScanDate = scanModified;
    if (!hasNewAlert) {
        [self refreshBubbleAlertList];
        [self showBubble];
        return;
    }
    self.lastAlertDate = modified;
    NSData *data = [NSData dataWithContentsOfFile:AlertPath];
    NSDictionary *alert = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![alert isKindOfClass:NSDictionary.class]) return;
    NSArray *jobs = [alert[@"jobs"] isKindOfClass:NSArray.class] ? alert[@"jobs"] : nil;
    if (jobs.count == 0 && [alert[@"url"] isKindOfClass:NSString.class]) jobs = @[alert];
    NSArray *history = [self appendJobsToHistory:jobs ?: @[]];
    if (history.count > 0) [self displayJobs:history];
    [self showBubble];
    [[NSSound soundNamed:@"Glass"] play];
}

- (void)buildStatusItem {
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.title = @"M";
    NSMenu *menu = [[NSMenu alloc] init];
    [menu addItemWithTitle:@"显示提醒" action:@selector(showBubble) keyEquivalent:@""];
    [menu addItemWithTitle:@"配置监控..." action:@selector(showSettings:) keyEquivalent:@""];
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItemWithTitle:@"退出" action:@selector(quit:) keyEquivalent:@"q"];
    self.statusItem.menu = menu;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    [self.iconPanel orderFront:nil];
    return YES;
}

- (void)quit:(id)sender { [NSApp terminate:nil]; }
@end

static AppDelegate *appDelegate;

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        appDelegate = [[AppDelegate alloc] init];
        app.delegate = appDelegate;
        [appDelegate applicationDidFinishLaunching:[NSNotification notificationWithName:NSApplicationDidFinishLaunchingNotification object:app]];
        [app run];
    }
    return 0;
}
