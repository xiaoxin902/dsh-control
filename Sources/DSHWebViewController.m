// SPDX-License-Identifier: MIT
#import "DSHWebViewController.h"

#import <WebKit/WebKit.h>

#import "DSHService.h"

/// APIs dsh's front end calls that WebKit only gained in iOS 17.4 (and
/// Promise.withResolvers in 17.4, AbortSignal.timeout in 16.4). On an older
/// system they are undefined and the page throws before it can start, so a
/// minimal implementation goes in before any page script runs.
static NSString *const DSHShimSource =
    @"(function() {"
     "  try {"
     "    if (typeof AbortSignal !== 'undefined' && !AbortSignal.any) {"
     "      AbortSignal.any = function(signals) {"
     "        var controller = new AbortController();"
     "        var list = Array.prototype.slice.call(signals);"
     "        for (var i = 0; i < list.length; i++) {"
     "          if (list[i].aborted) { controller.abort(list[i].reason); return controller.signal; }"
     "        }"
     "        list.forEach(function(signal) {"
     "          signal.addEventListener('abort', function() { controller.abort(signal.reason); }, { once: true });"
     "        });"
     "        return controller.signal;"
     "      };"
     "    }"
     "    if (typeof AbortSignal !== 'undefined' && !AbortSignal.timeout) {"
     "      AbortSignal.timeout = function(ms) {"
     "        var controller = new AbortController();"
     "        setTimeout(function() {"
     "          var reason = new Error('TimeoutError');"
     "          reason.name = 'TimeoutError';"
     "          controller.abort(reason);"
     "        }, ms);"
     "        return controller.signal;"
     "      };"
     "    }"
     "    if (typeof Promise !== 'undefined' && !Promise.withResolvers) {"
     "      Promise.withResolvers = function() {"
     "        var resolve, reject;"
     "        var promise = new Promise(function(res, rej) { resolve = res; reject = rej; });"
     "        return { promise: promise, resolve: resolve, reject: reject };"
     "      };"
     "    }"
     "    if (typeof Object.groupBy !== 'function') {"
     "      Object.groupBy = function(items, callback) {"
     "        var result = Object.create(null);"
     "        var index = 0;"
     "        for (var item of items) {"
     "          var key = callback(item, index++);"
     "          (result[key] = result[key] || []).push(item);"
     "        }"
     "        return result;"
     "      };"
     "    }"
     "  } catch (error) {"
     "    console.error('DSH shim failed', error);"
     "  }"
     "})();";

@interface DSHWebViewController () <WKNavigationDelegate>
@property (nonatomic, strong) NSURL *url;
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation DSHWebViewController

- (instancetype)initWithURL:(NSURL *)url {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _url = url;
        self.modalPresentationStyle = UIModalPresentationFullScreen;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
    configuration.allowsInlineMediaPlayback = YES;
    configuration.websiteDataStore = WKWebsiteDataStore.defaultDataStore;
    WKUserScript *shim = [[WKUserScript alloc] initWithSource:DSHShimSource
                                               injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                            forMainFrameOnly:NO];
    [configuration.userContentController addUserScript:shim];

    WKWebView *webView = [[WKWebView alloc] initWithFrame:self.view.bounds configuration:configuration];
    webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    webView.navigationDelegate = self;
    webView.allowsBackForwardNavigationGestures = YES;
    if (@available(iOS 16.4, *)) {
        webView.inspectable = NO;
    }
    [self.view addSubview:webView];
    self.webView = webView;

    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    spinner.hidesWhenStopped = YES;
    spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:spinner];
    self.spinner = spinner;

    // A bar of its own above the page: the dsh UI has controls of its own in
    // the top corners (a sidebar button, the stop button), and a button
    // floating over them made those unreachable.
    UIVisualEffectView *bar = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial]];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:bar];

    UILabel *barTitle = [UILabel new];
    barTitle.text = self.url.host.length > 0 ? self.url.host : @"DSH";
    barTitle.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    barTitle.textColor = UIColor.secondaryLabelColor;
    barTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [bar.contentView addSubview:barTitle];

    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [closeButton setTitle:@"关闭" forState:UIControlStateNormal];
    closeButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    [closeButton addTarget:self action:@selector(closeTapped:) forControlEvents:UIControlEventTouchUpInside];
    closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    closeButton.accessibilityLabel = @"关闭";
    [bar.contentView addSubview:closeButton];

    UILayoutGuide *safeArea = self.view.safeAreaLayoutGuide;
    webView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],

        [bar.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [bar.bottomAnchor constraintEqualToAnchor:safeArea.topAnchor constant:44],

        [barTitle.centerXAnchor constraintEqualToAnchor:bar.contentView.centerXAnchor],
        [barTitle.centerYAnchor constraintEqualToAnchor:bar.contentView.centerYAnchor],

        [closeButton.centerYAnchor constraintEqualToAnchor:bar.contentView.centerYAnchor],
        [closeButton.trailingAnchor constraintEqualToAnchor:bar.contentView.trailingAnchor constant:-16],

        [webView.topAnchor constraintEqualToAnchor:bar.bottomAnchor],
        [webView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [webView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [webView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    [spinner startAnimating];
    DSHLog(@"web: loading %@", self.url.absoluteString);
    [webView loadRequest:[NSURLRequest requestWithURL:self.url]];
}

- (void)closeTapped:(UIButton *)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    DSHLog(@"web: started %@", webView.URL.absoluteString);
}

- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation {
    DSHLog(@"web: committed %@", webView.URL.absoluteString);
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    [self.spinner stopAnimating];
    DSHLog(@"web: finished %@ title=%@", webView.URL.absoluteString, webView.title);
    // Ask the page whether the shim is in place, so a broken shim is visible
    // in the log instead of only in the page.
    [webView evaluateJavaScript:@"typeof AbortSignal.any + ':' + typeof Promise.withResolvers"
              completionHandler:^(id result, NSError *error) {
        DSHLog(@"web: shim check %@ %@", result, error.localizedDescription ?: @"");
    }];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self.spinner stopAnimating];
    // A cancelled load is what a redirect shows; only report real trouble.
    if ([error.domain isEqualToString:NSURLErrorDomain] && error.code == NSURLErrorCancelled) {
        return;
    }
    DSHLog(@"web: failed %@", error.localizedDescription);
    [self reportFailure:error];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self.spinner stopAnimating];
    [self reportFailure:error];
}

- (void)reportFailure:(NSError *)error {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"打开失败"
                                                                  message:error.localizedDescription
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:^(UIAlertAction *__unused action) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
