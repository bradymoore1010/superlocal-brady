#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@interface SuperlocalDelegate : NSObject <NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate>
@property NSWindow *window;
@property WKWebView *webView;
@property NSTask *server;
@property NSFileHandle *logHandle;
@property NSInteger attempts;
@end

@implementation SuperlocalDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSString *iconPath = [NSBundle.mainBundle pathForResource:@"SuperlocalIcon" ofType:@"icns"];
    if (iconPath) NSApp.applicationIconImage = [[NSImage alloc] initWithContentsOfFile:iconPath];

    WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
    configuration.websiteDataStore = WKWebsiteDataStore.defaultDataStore;
    self.webView = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:configuration];
    self.webView.navigationDelegate = self;
    self.webView.UIDelegate = self;

    NSRect frame = NSMakeRect(0, 0, 1440, 920);
    NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
        NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable | NSWindowStyleMaskFullSizeContentView;
    self.window = [[NSWindow alloc] initWithContentRect:frame styleMask:style backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"Superlocal";
    self.window.titlebarAppearsTransparent = YES;
    self.window.movableByWindowBackground = YES;
    self.window.contentView = self.webView;
    [self.window center];
    [self.window setFrameAutosaveName:@"SuperlocalMainWindow"];
    [self.window makeKeyAndOrderFront:nil];

    [self showStatus:@"Starting your local inbox…"];
    [self startServer];
    [self waitUntilReady];
    [NSApp activateIgnoringOtherApps:YES];
}

// Keep the inbox in its web view; ordinary web links belong in Chrome.
- (BOOL)isInboxURL:(NSURL *)url {
    return [url.scheme.lowercaseString isEqualToString:@"http"] &&
        ([@"localhost" isEqualToString:url.host.lowercaseString] || [@"127.0.0.1" isEqualToString:url.host]) &&
        url.port.integerValue == 5178;
}

- (void)openExternalURL:(NSURL *)url {
    NSString *scheme = url.scheme.lowercaseString;
    if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) {
        NSWorkspace *workspace = NSWorkspace.sharedWorkspace;
        NSURL *chrome = [workspace URLForApplicationWithBundleIdentifier:@"com.google.Chrome"];
        if (!chrome) {
            NSAlert *alert = [NSAlert new];
            alert.messageText = @"Google Chrome could not be found";
            alert.informativeText = @"Install Chrome to open web links from Superlocal.";
            [alert beginSheetModalForWindow:self.window completionHandler:nil];
            return;
        }
        NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
        configuration.activates = YES;
        [workspace openURLs:@[url] withApplicationAtURL:chrome configuration:configuration completionHandler:^(NSRunningApplication *application, NSError *error) {
            if (!error) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                NSAlert *alert = [NSAlert new];
                alert.messageText = @"Could not open the link in Chrome";
                alert.informativeText = error.localizedDescription;
                [alert beginSheetModalForWindow:self.window completionHandler:nil];
            });
        }];
    } else if ([scheme isEqualToString:@"mailto"] || [scheme isEqualToString:@"tel"]) {
        [NSWorkspace.sharedWorkspace openURL:url];
    }
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url = action.request.URL;
    NSString *scheme = url.scheme.lowercaseString;
    if ([self isInboxURL:url] || ![@[@"http", @"https", @"mailto", @"tel"] containsObject:scheme ?: @""]) {
        decisionHandler(WKNavigationActionPolicyAllow);
        return;
    }
    // srcdoc mail stays isolated. Only navigations, never image/resource loads,
    // arrive here; cancel before handing a link to another application.
    decisionHandler(WKNavigationActionPolicyCancel);
    if (action.navigationType == WKNavigationTypeLinkActivated || !action.targetFrame || action.targetFrame.isMainFrame) {
        [self openExternalURL:url];
    }
}

- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)action windowFeatures:(WKWindowFeatures *)windowFeatures {
    // Handles target=_blank and window.open if WebKit requests a new window.
    if (!action.targetFrame) [self openExternalURL:action.request.URL];
    return nil;
}

- (void)showStatus:(NSString *)message {
    NSString *escaped = [[message stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"]
        stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
    NSString *html = [NSString stringWithFormat:
        @"<!doctype html><meta charset='utf-8'><style>:root{color-scheme:light dark}body{margin:0;height:100vh;display:grid;place-items:center;background:#f5f5f3;color:#1d1d1f;font:15px -apple-system,BlinkMacSystemFont,sans-serif}.status{opacity:.7}@media(prefers-color-scheme:dark){body{background:#171717;color:#f5f5f7}}</style><div class='status'>%@</div>", escaped];
    [self.webView loadHTMLString:html baseURL:nil];
}

- (void)startServer {
    NSURL *resources = NSBundle.mainBundle.resourceURL;
    NSURL *source = [resources URLByAppendingPathComponent:@"superlocal" isDirectory:YES];
    NSFileManager *files = NSFileManager.defaultManager;
    NSURL *support = [[[files URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] firstObject]
        URLByAppendingPathComponent:@"Superlocal" isDirectory:YES];
    NSURL *data = [support URLByAppendingPathComponent:@"data" isDirectory:YES];
    NSURL *config = [support URLByAppendingPathComponent:@"superlocal.local.json"];
    NSURL *logs = [[[[files URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask] firstObject]
        URLByAppendingPathComponent:@"Logs" isDirectory:YES] URLByAppendingPathComponent:@"Superlocal" isDirectory:YES];
    NSError *error = nil;
    [files createDirectoryAtURL:data withIntermediateDirectories:YES attributes:nil error:&error];
    [files createDirectoryAtURL:logs withIntermediateDirectories:YES attributes:nil error:&error];
    if (error) { [self showStatus:[NSString stringWithFormat:@"Superlocal could not prepare storage: %@", error.localizedDescription]]; return; }

    NSURL *logURL = [logs URLByAppendingPathComponent:@"superlocal.log"];
    if (![files fileExistsAtPath:logURL.path]) [files createFileAtPath:logURL.path contents:nil attributes:nil];
    self.logHandle = [NSFileHandle fileHandleForWritingAtPath:logURL.path];
    [self.logHandle seekToEndOfFile];

    self.server = [NSTask new];
    self.server.executableURL = [NSURL fileURLWithPath:@"/opt/homebrew/bin/bun"];
    self.server.arguments = @[@"--no-env-file", @"run", @"dev"];
    self.server.currentDirectoryURL = source;
    NSMutableDictionary *environment = [NSProcessInfo.processInfo.environment mutableCopy];
    environment[@"SUPERLOCAL_CONFIG"] = config.path;
    environment[@"SUPERLOCAL_DATA_DIR"] = data.path;
    self.server.environment = environment;
    self.server.standardOutput = self.logHandle;
    self.server.standardError = self.logHandle;
    if (![self.server launchAndReturnError:&error]) {
        [self showStatus:[NSString stringWithFormat:@"Superlocal could not start: %@", error.localizedDescription]];
    }
}

- (void)waitUntilReady {
    self.attempts += 1;
    NSURL *url = [NSURL URLWithString:@"http://localhost:5178/"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 0.5;
    __weak typeof(self) weakSelf = self;
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            NSInteger status = [(NSHTTPURLResponse *)response statusCode];
            if (status >= 200 && status < 500) {
                [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
            } else if (self.attempts < 120) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self waitUntilReady]; });
            } else {
                [self showStatus:@"Superlocal timed out while starting. See ~/Library/Logs/Superlocal/superlocal.log"];
            }
        });
    }] resume];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return YES; }

- (void)applicationWillTerminate:(NSNotification *)notification {
    if (self.server.running) {
        [self.server terminate];
        [self.server waitUntilExit];
    }
    [self.logHandle closeFile];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self showStatus:@"The local inbox disconnected. Reopen Superlocal to restart it."];
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        app.activationPolicy = NSApplicationActivationPolicyRegular;
        SuperlocalDelegate *delegate = [SuperlocalDelegate new];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
