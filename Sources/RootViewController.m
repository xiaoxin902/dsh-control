// SPDX-License-Identifier: MIT
#import "RootViewController.h"

#import "DSHService.h"
#import "DSHWebViewController.h"

@interface RootViewController ()

@property (nonatomic, strong) UILabel *statusValueLabel;
@property (nonatomic, strong) UILabel *statusDetailLabel;
@property (nonatomic, strong) UISwitch *autoStartSwitch;
@property (nonatomic, strong) UILabel *autoStartHintLabel;
@property (nonatomic, strong) UIButton *openButton;
@property (nonatomic, strong) UIButton *startButton;
@property (nonatomic, strong) UIButton *stopButton;

@property (nonatomic, strong) dispatch_queue_t ioQueue;
@property (nonatomic, strong) NSTimer *refreshTimer;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, assign, getter=isBusy) BOOL busy;
@property (nonatomic, copy, nullable) NSString *pendingCommand;
@property (nonatomic, assign) NSTimeInterval pendingSince;

@end

@implementation RootViewController

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"DSH";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.ioQueue = dispatch_queue_create("bc.8848.dshcontrol.io", DISPATCH_QUEUE_SERIAL);

    [self buildInterface];
    [self reloadAutoStart];

    [NSNotificationCenter.defaultCenter addObserver:self
                                          selector:@selector(applicationDidBecomeActive:)
                                              name:UIApplicationDidBecomeActiveNotification
                                            object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self
                                          selector:@selector(returnedFromHelper:)
                                              name:@"DSHReturnedFromHelperNotification"
                                            object:nil];
    [self refreshStatus];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self startRefreshTimer];
    [self refreshStatus];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self logLayout];
}

- (void)logLayout {
    UISwitch *toSwitch = self.autoStartSwitch;
    UIButton *toStart = self.startButton;
    UIButton *toStop = self.stopButton;
    UIButton *toOpen = self.openButton;
    CGRect switchRect = [toSwitch convertRect:toSwitch.bounds toView:nil];
    CGRect startRect = [toStart convertRect:toStart.bounds toView:nil];
    CGRect stopRect = [toStop convertRect:toStop.bounds toView:nil];
    CGRect openRect = [toOpen convertRect:toOpen.bounds toView:nil];
    UIScrollView *scrollView = (UIScrollView *)self.openButton.superview.superview;
    CGFloat offset = [scrollView isKindOfClass:UIScrollView.class] ? scrollView.contentOffset.y : 0;
    DSHLog(@"layout: window=%@ scrollY=%.1f switch=%@ start=%@ stop=%@ open=%@",
           NSStringFromCGRect(self.view.window.bounds),
           offset,
           NSStringFromCGRect(switchRect),
           NSStringFromCGRect(startRect),
           NSStringFromCGRect(stopRect),
           NSStringFromCGRect(openRect));
    DSHLog(@"state: running=%d autostart=%d", self.running, [DSHService autoStartEnabled]);
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stopRefreshTimer];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    [self startRefreshTimer];
    if (self.pendingCommand) {
        NSDictionary *result = [DSHService helperResultNewerThan:self.pendingSince];
        if (result) {
            [self finishHelperCommandWithResult:result];
            return;
        }
    }
    [self refreshStatus];
    [self logLayout];
}

- (void)startRefreshTimer {
    if (self.refreshTimer) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer *__unused timer) {
        [weakSelf refreshStatus];
    }];
}

- (void)stopRefreshTimer {
    [self.refreshTimer invalidate];
    self.refreshTimer = nil;
}

#pragma mark - Interface

- (void)buildInterface {
    UIScrollView *scrollView = [UIScrollView new];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:scrollView];

    UILabel *subtitleLabel = [self captionLabelWithText:[NSString stringWithFormat:@"DeepSeek Harness · 127.0.0.1:%u", (unsigned)DSHWebPort]];

    // Status card
    UILabel *statusTitleLabel = [UILabel new];
    statusTitleLabel.text = @"服务状态";
    statusTitleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    statusTitleLabel.adjustsFontForContentSizeCategory = YES;

    self.statusValueLabel = [UILabel new];
    self.statusValueLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    self.statusValueLabel.adjustsFontForContentSizeCategory = YES;
    self.statusValueLabel.textAlignment = NSTextAlignmentRight;
    self.statusValueLabel.text = @"检查中…";
    [self.statusValueLabel setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                           forAxis:UILayoutConstraintAxisHorizontal];

    self.statusDetailLabel = [self captionLabelWithText:@"正在检测端口 3080"];

    UIStackView *statusTextStack = [[UIStackView alloc] initWithArrangedSubviews:@[ statusTitleLabel, self.statusDetailLabel ]];
    statusTextStack.axis = UILayoutConstraintAxisVertical;
    statusTextStack.spacing = 2;

    UIStackView *statusRow = [[UIStackView alloc] initWithArrangedSubviews:@[ statusTextStack, self.statusValueLabel ]];
    statusRow.axis = UILayoutConstraintAxisHorizontal;
    statusRow.alignment = UIStackViewAlignmentCenter;
    statusRow.spacing = 12;

    UIView *statusCard = [self cardWithArrangedSubviews:@[ statusRow ]];

    // Auto-start card
    UILabel *autoStartTitleLabel = [UILabel new];
    autoStartTitleLabel.text = @"开机自启";
    autoStartTitleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    autoStartTitleLabel.adjustsFontForContentSizeCategory = YES;

    self.autoStartSwitch = [UISwitch new];
    self.autoStartSwitch.accessibilityLabel = @"开机自启";
    [self.autoStartSwitch addTarget:self action:@selector(autoStartSwitchChanged:) forControlEvents:UIControlEventValueChanged];

    UIStackView *autoStartRow = [[UIStackView alloc] initWithArrangedSubviews:@[ autoStartTitleLabel, self.autoStartSwitch ]];
    autoStartRow.axis = UILayoutConstraintAxisHorizontal;
    autoStartRow.alignment = UIStackViewAlignmentCenter;
    autoStartRow.spacing = 12;

    self.autoStartHintLabel = [self captionLabelWithText:@""];
    UIView *autoStartCard = [self cardWithArrangedSubviews:@[ autoStartRow, self.autoStartHintLabel ]];

    // Main action
    self.openButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.openButton setTitle:@"打开 DeepSeek Harness" forState:UIControlStateNormal];
    self.openButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    self.openButton.titleLabel.adjustsFontForContentSizeCategory = YES;
    [self.openButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.openButton.backgroundColor = UIColor.systemBlueColor;
    self.openButton.layer.cornerRadius = 14;
    self.openButton.layer.cornerCurve = kCACornerCurveContinuous;
    [self.openButton addTarget:self action:@selector(openTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.openButton.heightAnchor constraintEqualToConstant:56].active = YES;

    // Start / stop
    self.startButton = [self auxiliaryButtonWithTitle:@"启动" action:@selector(startTapped:)];
    self.stopButton = [self auxiliaryButtonWithTitle:@"停止" action:@selector(stopTapped:)];

    UIStackView *auxRow = [[UIStackView alloc] initWithArrangedSubviews:@[ self.startButton, self.stopButton ]];
    auxRow.axis = UILayoutConstraintAxisHorizontal;
    auxRow.distribution = UIStackViewDistributionFillEqually;
    auxRow.spacing = 12;

    UILabel *footerLabel = [self captionLabelWithText:[NSString stringWithFormat:@"版本 %s（%s）", APELIN_VERSION, APELIN_BUILD_ID]];
    footerLabel.textAlignment = NSTextAlignmentCenter;

    UIStackView *content = [[UIStackView alloc] initWithArrangedSubviews:@[
        subtitleLabel, statusCard, autoStartCard, self.openButton, auxRow, footerLabel
    ]];
    content.axis = UILayoutConstraintAxisVertical;
    content.spacing = 16;
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [content setCustomSpacing:24 afterView:autoStartCard];
    [content setCustomSpacing:24 afterView:auxRow];
    [scrollView addSubview:content];

    UILayoutGuide *contentGuide = scrollView.contentLayoutGuide;
    UILayoutGuide *frameGuide = scrollView.frameLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],

        [content.topAnchor constraintEqualToAnchor:contentGuide.topAnchor constant:8],
        [content.bottomAnchor constraintEqualToAnchor:contentGuide.bottomAnchor constant:-28],
        [content.leadingAnchor constraintEqualToAnchor:contentGuide.leadingAnchor constant:20],
        [content.trailingAnchor constraintEqualToAnchor:contentGuide.trailingAnchor constant:-20],
        [content.widthAnchor constraintEqualToAnchor:frameGuide.widthAnchor constant:-40],
    ]];

    [self applyRunning:NO pid:0];
}

- (UILabel *)captionLabelWithText:(NSString *)text {
    UILabel *label = [UILabel new];
    label.text = text;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = UIColor.secondaryLabelColor;
    label.numberOfLines = 0;
    return label;
}

- (UIView *)cardWithArrangedSubviews:(NSArray<UIView *> *)views {
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:views];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 6;
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *card = [UIView new];
    card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    card.layer.cornerRadius = 14;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    [card addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:16],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
    ]];
    return card;
}

- (UIButton *)auxiliaryButtonWithTitle:(NSString *)title action:(SEL)action {
    UIButtonConfiguration *configuration = [UIButtonConfiguration tintedButtonConfiguration];
    configuration.title = title;
    configuration.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    configuration.contentInsets = NSDirectionalEdgeInsetsMake(12, 16, 12, 16);
    UIButton *button = [UIButton buttonWithConfiguration:configuration primaryAction:nil];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [button.heightAnchor constraintEqualToConstant:48].active = YES;
    return button;
}

#pragma mark - State

- (void)applyRunning:(BOOL)running pid:(NSInteger)pid {
    self.running = running;
    self.statusValueLabel.text = running ? @"运行中" : @"未运行";
    self.statusValueLabel.textColor = running ? UIColor.systemGreenColor : UIColor.secondaryLabelColor;
    self.statusDetailLabel.text = running
        ? [NSString stringWithFormat:@"端口 3080 已连通 · PID %ld", (long)pid]
        : @"端口 3080 没有响应";
    self.startButton.enabled = !running;
    self.stopButton.enabled = running;
    DSHLog(@"status applied: running=%d pid=%ld", running, (long)pid);
}

- (void)setBusy:(BOOL)busy {
    _busy = busy;
    if (busy) {
        self.statusValueLabel.text = @"处理中…";
        self.statusValueLabel.textColor = UIColor.secondaryLabelColor;
        self.statusDetailLabel.text = @"正在执行命令，请稍候";
        self.startButton.enabled = NO;
        self.stopButton.enabled = NO;
        self.openButton.enabled = NO;
    } else {
        self.openButton.enabled = YES;
    }
}

- (void)reloadAutoStart {
    BOOL enabled = [DSHService autoStartEnabled];
    [self.autoStartSwitch setOn:enabled animated:NO];
    self.autoStartHintLabel.text = enabled
        ? @"开启中：开机后 dsh 会自动启动。"
        : @"已关闭：开机后 dsh 不会自动启动（文件 autostart.off 存在）。";
}

- (void)refreshStatus {
    if (self.isBusy) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.ioQueue, ^{
        BOOL running = [DSHService isRunning];
        NSInteger pid = running ? [DSHService currentPID] : 0;
        dispatch_async(dispatch_get_main_queue(), ^{
            RootViewController *strongSelf = weakSelf;
            if (!strongSelf || strongSelf.isBusy) {
                return;
            }
            [strongSelf applyRunning:running pid:pid];
        });
    });
}

#pragma mark - Actions

- (void)autoStartSwitchChanged:(UISwitch *)sender {
    BOOL wanted = sender.isOn;
    NSError *error = nil;
    if (![DSHService setAutoStartEnabled:wanted error:&error]) {
        [sender setOn:!wanted animated:YES];
        DSHLog(@"autostart -> %d FAILED: %@", wanted, error.localizedDescription);
        [self showAlertWithTitle:@"设置开机自启失败" message:error.localizedDescription];
        return;
    }
    DSHLog(@"autostart -> %d ok, autostart.off exists=%d", wanted, !wanted);
    [self reloadAutoStart];
}

- (void)openTapped:(UIButton *)sender {
    NSString *urlString = [DSHService currentTokenURL];
    NSURL *url = urlString.length > 0 ? [NSURL URLWithString:urlString] : nil;
    if (!url) {
        DSHLog(@"open: no token URL in /tmp/dsh-web.log");
        [self showAlertWithTitle:@"没有找到访问地址"
                         message:@"日志 /tmp/dsh-web.log 里还没有 dsh 的访问地址。\n请先点「启动」，等状态变成「运行中」再打开。"];
        return;
    }
    DSHLog(@"open: presenting %@", url.absoluteString);
    DSHWebViewController *browser = [[DSHWebViewController alloc] initWithURL:url];
    [self presentViewController:browser animated:YES completion:nil];
}

#pragma mark - Helper app

/// The sandboxed app cannot run the launcher or signal dsh, so the work
/// happens in the bundled helper app: open its URL, then read the answer it
/// leaves in /tmp/dsh-helper.json.
- (void)runHelperCommand:(NSString *)command {
    if (self.isBusy) {
        return;
    }
    [self setBusy:YES];

    [DSHService removeHelperResult];
    self.pendingCommand = command;
    self.pendingSince = NSDate.date.timeIntervalSince1970 - 0.5;
    NSTimeInterval since = self.pendingSince;

    NSURL *url = [NSURL URLWithString:[@"dshhelper://" stringByAppendingString:command]];
    __weak typeof(self) weakSelf = self;
    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:^(BOOL success) {
        DSHLog(@"helper: open %@ -> %d", url.absoluteString, success);
        if (!success) {
            dispatch_async(dispatch_get_main_queue(), ^{
                RootViewController *strongSelf = weakSelf;
                if (!strongSelf) {
                    return;
                }
                [strongSelf finishHelperCommandWithResult:@{ @"ok": @NO,
                                                             @"message": @"无法启动辅助应用（DSH 助手）。" }];
            });
        }
    }];

    dispatch_async(self.ioQueue, ^{
        NSDictionary *result = nil;
        for (int i = 0; i < 60; i++) {
            result = [DSHService helperResultNewerThan:since];
            if (result) {
                break;
            }
            usleep(500 * 1000);
        }
        NSDictionary *finalResult = result ?: @{ @"ok": @NO, @"message": @"辅助应用没有回应（超时）。" };
        dispatch_async(dispatch_get_main_queue(), ^{
            RootViewController *strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }
            [strongSelf finishHelperCommandWithResult:finalResult];
        });
    });
}

- (void)finishHelperCommandWithResult:(NSDictionary *)result {
    if (!self.pendingCommand) {
        [self refreshStatus];
        return;
    }
    NSString *command = self.pendingCommand;
    self.pendingCommand = nil;

    BOOL ok = [result[@"ok"] boolValue];
    NSString *message = result[@"message"];
    DSHLog(@"helper: %@ -> ok=%d %@", command, ok, message ?: @"");

    [self setBusy:NO];
    [self refreshStatus];
    if (!ok) {
        [self showAlertWithTitle:[command isEqualToString:@"stop"] ? @"停止未完成" : @"启动未完成"
                         message:message ?: @"未知错误"];
    }
}

/// dshcontrol://helper-done — the helper handing the user back.
- (void)returnedFromHelper:(NSNotification *)notification {
    if (self.pendingCommand) {
        NSDictionary *result = [DSHService helperResultNewerThan:self.pendingSince];
        if (result) {
            [self finishHelperCommandWithResult:result];
            return;
        }
    }
    [self refreshStatus];
}

- (void)startTapped:(UIButton *)sender {
    [self runHelperCommand:@"start"];
}

- (void)stopTapped:(UIButton *)sender {
    [self runHelperCommand:@"stop"];
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
