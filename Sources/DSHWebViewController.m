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

/// Forwards what the page logs, and every fetch it makes, into the app's log.
@interface DSHPageBridge : NSObject <WKScriptMessageHandler>
@end

@implementation DSHPageBridge

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    NSString *text = [message.body isKindOfClass:NSString.class] ? message.body : [message.body description];
    DSHLog(@"page: %@", text);
}

@end

/// Runs before any page script: reports console errors, uncaught errors and
/// each fetch (method, URL, status) to the app, which writes them to
/// /tmp/dsh-control.log.
static NSString *const DSHPageProbeSource =
    @"(function() {"
     "  const send = (kind, parts) => {"
     "    try {"
     "      const text = parts.map((part) => {"
     "        try { return typeof part === 'object' ? JSON.stringify(part).slice(0, 300) : String(part); }"
     "        catch (error) { return String(part); }"
     "      }).join(' ');"
     "      window.webkit.messageHandlers.dsh.postMessage(kind + ' ' + text.slice(0, 600));"
     "    } catch (error) {}"
     "  };"
     "  const consoleError = console.error;"
     "  console.error = function() { send('console.error', Array.prototype.slice.call(arguments)); consoleError.apply(console, arguments); };"
     "  const consoleWarn = console.warn;"
     "  console.warn = function() { send('console.warn', Array.prototype.slice.call(arguments)); consoleWarn.apply(console, arguments); };"
     "  window.addEventListener('error', (event) => send('window.error', [event.message, (event.filename || '') + ':' + event.lineno]));"
     "  window.addEventListener('unhandledrejection', (event) => {"
     "    const reason = event.reason;"
     "    send('unhandledrejection', [String(reason && (reason.stack || reason.message || reason))]);"
     "  });"
     "  const originalFetch = window.fetch;"
     "  window.fetch = function(input, init) {"
     "    const url = typeof input === 'string' ? input : (input && input.url) || '';"
     "    const method = (init && init.method) || (input && input.method) || 'GET';"
     "    const started = Date.now();"
     "    const isApi = url.indexOf('api/') >= 0;"
     "    if (isApi && init && typeof init.body === 'string') send('api.request', [method, url, init.body.slice(0, 200)]);"
     "    return originalFetch.apply(this, arguments).then((response) => {"
     "      send('fetch', [method, url, response.status, (Date.now() - started) + 'ms']);"
     "      const type = response.headers.get('content-type') || '';"
     "      if (isApi && type.indexOf('json') >= 0) {"
     "        response.clone().text().then((text) => send('api.response', [method, url, response.status, text.slice(0, 300)])).catch(() => {});"
     "      }"
     "      return response;"
     "    }, (error) => {"
     "      send('fetch.error', [method, url, String((error && error.message) || error), (Date.now() - started) + 'ms']);"
     "      throw error;"
     "    });"
     "  };"
     "  if (window.WebSocket) {"
     "    const OriginalWebSocket = window.WebSocket;"
     "    window.WebSocket = new Proxy(OriginalWebSocket, {"
     "      construct(target, args) {"
     "        const socket = new target(...args);"
     "        send('ws.create', [String(args[0])]);"
     "        socket.addEventListener('open', () => send('ws.open', [String(args[0])]));"
     "        socket.addEventListener('close', (event) => send('ws.close', [String(args[0]), event.code, event.reason]));"
     "        socket.addEventListener('error', () => send('ws.error', [String(args[0])]));"
     "        return socket;"
     "      }"
     "    });"
     "  }"
     "  if (window.EventSource) {"
     "    const OriginalEventSource = window.EventSource;"
     "    window.EventSource = new Proxy(OriginalEventSource, {"
     "      construct(target, args) {"
     "        const source = new target(...args);"
     "        send('es.create', [String(args[0])]);"
     "        source.addEventListener('error', () => send('es.error', [String(args[0]), source.readyState]));"
     "        return source;"
     "      }"
     "    });"
     "  }"
     "})();";

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
    WKUserScript *probe = [[WKUserScript alloc] initWithSource:DSHPageProbeSource
                                                   injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                                                forMainFrameOnly:YES];
    [configuration.userContentController addUserScript:probe];
    [configuration.userContentController addScriptMessageHandler:[DSHPageBridge new] name:@"dsh"];

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
