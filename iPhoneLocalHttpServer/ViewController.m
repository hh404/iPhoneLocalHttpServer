//
//  ViewController.m
//  iPhoneLocalHttpServer
//
//  Created by huangjianwu on 16/5/29.
//  Copyright © 2016年 huangjianwu. All rights reserved.
//

#import "ViewController.h"
#import "HTTPServer.h"


@interface ViewController ()<UIWebViewDelegate,WebFileResourceDelegate>
{
    HTTPServer *httpServer;
    UIWebView *mWebView;//测试webview
    UILabel *urlLabel;//显示ip端口的
    NSMutableArray *fileList;
    
}
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    
    urlLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 20, [UIScreen mainScreen].bounds.size.width, 25)];
    [self.view addSubview:urlLabel];
    
    // set up the http server
    httpServer = [[HTTPServer alloc] init];
    [httpServer setType:@"_http._tcp."];
    [httpServer setPort:8088];
    [httpServer setName:@"iPhoneLocalHttpServer"];
    [httpServer setupBuiltInDocroot];
    httpServer.fileResourceDelegate = self;
    
    
    NSError *error = nil;
    BOOL serverIsRunning = [httpServer start:&error];
    if(!serverIsRunning)
    {
        NSLog(@"Error starting HTTP Server: %@", error);
    }
    [urlLabel setText:[NSString stringWithFormat:@"http://%@:%d", [httpServer hostName], [httpServer port]]];
    
    
    mWebView = [[UIWebView alloc] initWithFrame:CGRectMake(0, 64, urlLabel.frame.size.width, [UIScreen mainScreen].bounds.size.height - 64)];
    mWebView.delegate = self;
    mWebView.scalesPageToFit = YES;
    [self.view addSubview:mWebView];
    
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSURLRequest *request = [[NSURLRequest alloc] initWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"http://%@:%d", @"127.0.0.1", [httpServer port]]]];
        [mWebView loadRequest:request];
    });
}

// load file list
- (void)loadFileList
{
    [fileList removeAllObjects];
    NSString* docDir = [NSString stringWithFormat:@"%@/Documents", NSHomeDirectory()];
    NSDirectoryEnumerator *direnum = [[NSFileManager defaultManager]
                                      enumeratorAtPath:docDir];
    NSString *pname;
    while (pname = [direnum nextObject])
    {
        [fileList addObject:pname];
    }
}



- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark WebFileResourceDelegate
// number of the files
- (NSInteger)numberOfFiles
{
    return [fileList count];
}

// the file name by the index
- (NSString*)fileNameAtIndex:(NSInteger)index
{
    return [fileList objectAtIndex:index];
}

// provide full file path by given file name
- (NSString*)filePathForFileName:(NSString*)filename
{
    NSString* docDir = [NSString stringWithFormat:@"%@/Documents", NSHomeDirectory()];
    return [NSString stringWithFormat:@"%@/%@", docDir, filename];
}

// handle newly uploaded file. After uploading, the file is stored in
// the temparory directory, you need to implement this method to move
// it to proper location and update the file list.
- (void)newFileDidUpload:(NSString*)name inTempPath:(NSString*)tmpPath
{
    if (name == nil || tmpPath == nil)
        return;
    NSString* docDir = [NSString stringWithFormat:@"%@/Documents", NSHomeDirectory()];
    NSString *path = [NSString stringWithFormat:@"%@/%@", docDir, name];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error;
    if (![fm moveItemAtPath:tmpPath toPath:path error:&error])
    {
        NSLog(@"can not move %@ to %@ because: %@", tmpPath, path, error );
    }
    
    [self loadFileList];
    
}

// implement this method to delete requested file and update the file list
- (void)fileShouldDelete:(NSString*)fileName
{
    NSString *path = [self filePathForFileName:fileName];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error;
    if(![fm removeItemAtPath:path error:&error])
    {
        NSLog(@"%@ can not be removed because:%@", path, error);
    }
    [self loadFileList];
}



- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType;
{
    return YES;
}

- (void)webViewDidStartLoad:(UIWebView *)webView;
{
    
}

- (void)webViewDidFinishLoad:(UIWebView *)webView;
{
    
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:( NSError *)error;
{
    
}
@end
