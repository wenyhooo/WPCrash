//
//  SNKCrashCatch.m
//  CrashDemo
//
//  Created by wenyhooo on 2020/5/18.
//  Copyright © 2020 liwenhaopro. All rights reserved.
//

#import "SNKCrashCatch.h"
#import <sys/signal.h>
#include <execinfo.h>
#include <libkern/OSAtomic.h>
#import <UIKit/UIKit.h>

typedef void (*SignalHandler)(int signal, siginfo_t *info, void *context);

static NSUncaughtExceptionHandler *oldUncaughtExceptionHandler;
static SignalHandler oldSignalHandler;

volatile int32_t KSNKUncaughtExceptionCount = 0;
static NSInteger const kUncaughtExceptionHandlerSkipAddressCount = 4;
static NSInteger const UncaughtExceptionHandlerReportAddressCount = 5;
static NSString * const kSNKSignalType = @"kSNKSignalType";
static NSString * const kSNKCatchBacktrace = @"catchBacktrace";
static NSString * const kSNKSignalExceptionName = @"kSNKSignalExceptionName";

@implementation SNKCrashCatch


+ (void)CrashCatch
{
    //NSException
    oldUncaughtExceptionHandler = NSGetUncaughtExceptionHandler();
    NSSetUncaughtExceptionHandler(&uncaught_exception_handler);//
    
    //signal
    struct sigaction old_action;
    sigaction(SIGABRT, NULL, &old_action);
    if (old_action.sa_flags & SA_SIGINFO) {
        oldSignalHandler = old_action.sa_sigaction;
    }
    [self setUncaughtSignal];
}

+ (void)setUncaughtSignal
{
    //注册处理SIGSEGV信号
    SNKSignalRegister(SIGABRT);
    SNKSignalRegister(SIGHUP);
    SNKSignalRegister(SIGINT);
    SNKSignalRegister(SIGQUIT);
    SNKSignalRegister(SIGILL);
    SNKSignalRegister(SIGSEGV);
    SNKSignalRegister(SIGBUS);
    SNKSignalRegister(SIGPIPE);
}

static void uncaught_exception_handler(NSException *exception) {
    NSString *name = exception.name;
    NSString *reason = exception.reason;
    NSArray *callStack = exception.callStackSymbols;
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:[exception userInfo]];
    [userInfo setValue:callStack forKey:@"callStackSymbols"];
    [userInfo setValue:[SNKCrashCatch catchBacktrace] forKey:@"catchBacktrace"];
    [userInfo setValue:[NSThread callStackSymbols] forKey:@"threadCallStackSymbols"];
    [userInfo setValue:[SNKCrashCatch getAppinfo] forKey:@"appinfo"];
    NSException *newException = [NSException exceptionWithName:name reason:reason userInfo:userInfo];

    [[[SNKCrashCatch alloc] init] performSelectorOnMainThread:@selector(handleException:) withObject:newException waitUntilDone:YES];
    !oldUncaughtExceptionHandler? :oldUncaughtExceptionHandler(exception);
}

void mySNKSignalHandle(int signal, siginfo_t *info, void *context)
{
    int32_t exceptionCount = OSAtomicIncrement32(&KSNKUncaughtExceptionCount);//全局计数器,原子操作
    if (exceptionCount > 10){
        return;
    }
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:[NSNumber numberWithInt:signal] forKey:kSNKSignalType];
    [userInfo setObject:[SNKCrashCatch catchBacktrace] forKey:kSNKCatchBacktrace];
    [userInfo setValue:[NSThread callStackSymbols] forKey:@"threadCallStackSymbols"];
    [userInfo setObject:@"SigCrash" forKey:@"crash type"];
    [userInfo setObject:[SNKCrashCatch getAppinfo] forKey:@"appinfo"];
    [userInfo setObject:@(exceptionCount) forKey:@"exceptionCount"];
    
    NSException *newException = [NSException exceptionWithName:kSNKSignalExceptionName reason:[NSString stringWithFormat:@"Signal = %d",signal] userInfo:userInfo];
    [[[SNKCrashCatch alloc] init] performSelectorOnMainThread:@selector(handleException:) withObject:newException waitUntilDone:YES];
    !oldSignalHandler? :oldSignalHandler(signal,info,context);
}

static void SNKSignalRegister(int signal) {
    struct sigaction action;
    action.sa_sigaction = mySNKSignalHandle;
    action.sa_flags = SA_NODEFER | SA_SIGINFO;
    sigemptyset(&action.sa_mask);
    sigaction(signal, &action, 0);
}

#pragma mark - pravite
- (void)handleException:(NSException *)exception
{
    
    int a = 2;
    
   __block BOOL success = NO;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
       [self saveException:exception];
     //upload ....
        success = YES;
//        CFRunLoopStop(CFRunLoopGetCurrent());
    });
    
    //保活处理
    
    if (a == 1) {
        //第一种方法
        CFRunLoopRun();
    }
    else if (a == 2){
        //第2种方法
        //当接收到异常处理消息时，让程序开始runloop，防止程序收到signal abrt
        CFRunLoopRef runLoop = CFRunLoopGetCurrent();
        CFArrayRef allModes = CFRunLoopCopyAllModes(runLoop);//得到当前线程runloop对象定义的mode
        while (!success) {
            for (NSString *mode in (__bridge NSArray *)allModes){
                CFRunLoopRunInMode((CFStringRef)mode, 0.001, false);//激活runloop
            }
        }
        CFRelease(allModes);
    }
    else if (a == 3){
        //第3种方法
        //或者走这里也可以  不断唤醒  卡主线程
        while (!success) {
        }
    }
}

- (BOOL)saveException:(NSException *)exception
{
    NSString *baseDir = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    NSString *directoryPath = [NSString stringWithFormat:@"%@/AAACrash",baseDir];
    BOOL dirSuccess = [[NSFileManager defaultManager] createDirectoryAtPath:directoryPath withIntermediateDirectories:YES attributes:nil error:nil];
    NSLog(@"dirSuccess=%d",dirSuccess);
    
    NSString *filePath = [NSString stringWithFormat:@"%@/%@-%@.text",directoryPath,[self.class currentDateStr],exception.name];
    NSString *exceptionInfo = [NSString stringWithFormat:@"Exception reason：%@\nException name：%@\nException userInfo：%@",exception.name, exception.reason, exception.userInfo];
    NSLog(@"exceptioninfo=%@",exceptionInfo);
    NSError *error = nil;
    BOOL success = [exceptionInfo writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:&error];
    NSLog(@"%s,success = %d,error = %@",__func__,success,error);
    return success;
}

+ (NSArray *)catchBacktrace
{
    void* callstack[128];
    int frames = backtrace(callstack, 128);//用于获取当前线程的函数调用堆栈，返回实际获取的指针个数
    char **strs = backtrace_symbols(callstack, frames);//从backtrace函数获取的信息转化为一个字符串数组
    int i;
    NSMutableArray *backtrace = [NSMutableArray arrayWithCapacity:frames];
    for (i = kUncaughtExceptionHandlerSkipAddressCount; i < kUncaughtExceptionHandlerSkipAddressCount + UncaughtExceptionHandlerReportAddressCount; i++)
    {
        [backtrace addObject:[NSString stringWithUTF8String:strs[i]]];
    }
    free(strs);
    return backtrace;
}

+ (NSString *)getAppinfo
{
    NSString *appInfo = [NSString stringWithFormat:@"App : %@ %@(%@)\nDevice : %@\nOS Version : %@ %@\n",
                         [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"],
                         [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"],
                         [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"],
                         [UIDevice currentDevice].model,
                         [UIDevice currentDevice].systemName,
                         [UIDevice currentDevice].systemVersion];
    //                         [UIDevice currentDevice].uniqueIdentifier];
    NSLog(@"Crash!!!! %@", appInfo);
    return appInfo;
}

+ (NSString *)currentDateStr
{
    NSDate *currentDate = [NSDate date];
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"YYYY.MM.dd - hh.mm.ss.SSSS"];
    NSString *dateString = [dateFormatter stringFromDate:currentDate];
    return dateString;
}
@end
