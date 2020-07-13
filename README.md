
* [前言：](#前言)
 * [crash 分三大类](#crash-分三大类)
    * [1.Mach 异常](#1mach-异常)
       * [先来了解几个概念：](#先来了解几个概念)
	  * [Darwin是什么？](#darwin是什么)
	  * [XNU是什么？](#xnu是什么)
	  * [Mach是什么？](#mach是什么)
	  * [Mach 异常是什么？](#mach-异常是什么)
	  * [它又是如何与 Unix 信号建立联系的？](#它又是如何与-unix-信号建立联系的)
    * [2.Signal 信号](#2signal-信号)
    * [3.NSException](#3nsexception)
 * [怎么捕获crash信息](#怎么捕获crash信息)
    * [Signal信号捕获](#signal信号捕获)
       * [先检查第三方有没有注册过signal，存下来处理完后要传递下去，不然会影响信号传递，影响第三方crash统计](#先检查第三方有没有注册过signal存下来处理完后要传递下去不然会影响信号传递影响第三方crash统计)
       * [注册自己的信号捕获函数](#注册自己的信号捕获函数)
       * [处理接收到的Signal信号](#处理接收到的signal信号)
       * [处理完后，不忘记将Signal信号继续传递下去](#处理完后不忘记将signal信号继续传递下去)
       * [如何验证调试Signal信号？](#如何验证调试signal信号)
	  * [第一种：Debug时主动触发Xcode抛出Signal：](#第一种debug时主动触发xcode抛出signal)
	  * [第二种方法，先模拟一个野指针的Signal:](#第二种方法先模拟一个野指针的signal)
       * [导致崩溃的最常见的两个信号：](#导致崩溃的最常见的两个信号)
       * [大部分Signal信号说明：](#大部分signal信号说明)
    * [NSException异常捕获](#nsexception异常捕获)
       * [先检查第三方有没有注册过NSSetUncaughtExceptionHandler，存下来处理完后要传递下去，不然会影响exception传递，影响第三方crash统计](#先检查第三方有没有注册过nssetuncaughtexceptionhandler存下来处理完后要传递下去不然会影响exception传递影响第三方crash统计)
       * [注册我们自己的exception捕获函数](#注册我们自己的exception捕获函数)
       * [处理系统抛出的exception异常](#处理系统抛出的exception异常)
 * [捕获到Crash info时，如何阻止App闪退，做到保活实时上传?](#捕获到crash-info时如何阻止app闪退做到保活实时上传)
    * [看一下崩溃时的系统堆栈流程的源码](#看一下崩溃时的系统堆栈流程的源码)
       * [1.CFRunLoopRunSpecific:](#1cfrunlooprunspecific)
       * [2.异常抛出objc_exception_throw：](#2异常抛出objc_exception_throw)
       * [3.objc_exception_rethrow：](#3objc_exception_rethrow)
       * [4._objc_terminate：](#4_objc_terminate)
       * [5.__pthread_kill：](#5__pthread_kill)
    * [如何阻止程序立即crash，给我们上传到server争取时间?](#如何阻止程序立即crash给我们上传到server争取时间)
       * [1.就在crash的异常捕获函数里，先写个while循环试试把](#1就在crash的异常捕获函数里先写个while循环试试把)
       * [2.Crash时调用下CFRunLoopRun](#2crash时调用下cfrunlooprun)
       * [3.Crash时调用下CFRunLoopRunInMode()](#3crash时调用下cfrunloopruninmode)


## 前言：

大多开发者都会接入firebase、bugly等第三方Crash统计，一些大型应用DSYM文件会比较大，像我们的DSYM就达到了250M，特别是每次测试打包时，会在编译完成时上传DSYM到firebase，这个过程非常慢甚至经常失败，或者崩溃时手机网络本身就不好，大家应该都遇到过Crash丢失的问题，所以我们更好的去了解程序崩溃的捕获机制，甚至自己制作一个Crash捕获作为兜底，更有助于我们解决问题。

崩溃（或更准确地说：意外终止）不能处理的信号到达了应用程序。



### crash 分三大类

#### 1.Mach 异常

##### 先来了解几个概念： 

###### Darwin是什么？

Darwin是Mac OS和iOS的操作系统的内核系统

可在MAC用命令查看版本详情：

```
  Darwin  system_profiler SPSoftwareDataType  	
```

```
  Software:
    System Software Overview:
      System Version: macOS 10.15.4 (19E287)
      Kernel Version: Darwin 19.4.0
```

###### XNU是什么？

> 维基百科：XNU是混合内核，兼具宏内核和微内核的特性。它是[Darwin](https://zh.wikipedia.org/wiki/Darwin_(操作系统))操作系统的一部分，跟随着Darwin一同作为自由及开放源代码软件被发布。它还是[iOS](https://zh.wikipedia.org/wiki/IOS)、[tvOS](https://zh.wikipedia.org/wiki/TvOS)和[watchOS](https://zh.wikipedia.org/wiki/WatchOS)操作系统的内核。XNU是**X is Not Unix**的缩写

###### Mach是什么？

> Mach即为XNU微内核核心

###### Mach 异常是什么？

> 它为系统最底层的内核级异常，被定义在`<mach/exception_types.h>`，当错误发生时，先在最底层产生Mach异常.

###### 它又是如何与 Unix 信号建立联系的？

> Mach异常在host层被`ux_exception`转换成相应的Unix信号，通过`threadsignal`将信号投递出来也就是Signal信号。在OC层如果有对应的`NSException`，会优先转换成OC异常抛出并在最后发送`abort Signal`信号来终止程序，否则就会通过Unix的signal机制来处理。

#### 2.Signal 信号

它是一种软中断信号，一般是由硬中断发生时通知unix系统产生。OC层异常NSException如果不能处理，就会通过signal信号，抛出错误。

#### 3.NSException

OC应用层崩溃，就会通过这个对象抛出异常信息，程序处理完成后，最终还会发出一个abort signal信号，来强制终止应用，也就是崩溃。

### 怎么捕获crash信息

优选Mach异常最好，因为Mach异常最先发生，如果在Mach异常的处理逻辑让程序exit，那么Unix信号就永远到达不了此进程。

业界多数开源项目都选用的是Mach 异常 +Unix 信号方式，因为内核发送`EXC_CRASH` mach异常来表示SIGABRT终止。在这种情况下，在进程中捕获Mach异常会导致进程死锁，所以还要依靠SIGABRT的BSD 
我们先学习一下 Signal和NSException，来完成Crash统计。

#### Signal信号捕获

##### 先检查第三方有没有注册过signal，存下来处理完后要传递下去，不然会影响信号传递，影响第三方crash统计

```objective-c
    struct sigaction old_action;
    sigaction(SIGABRT, NULL, &old_action);
    if (old_action.sa_flags & SA_SIGINFO) {
        oldSignalHandler = old_action.sa_sigaction;
    }
```

##### 注册自己的信号捕获函数

```objective-c
//注册处理SIGSEGV信号
    SNKSignalRegister(SIGABRT);
    SNKSignalRegister(SIGHUP);
    SNKSignalRegister(SIGINT);
    SNKSignalRegister(SIGQUIT);
    SNKSignalRegister(SIGILL);
    SNKSignalRegister(SIGSEGV);
    SNKSignalRegister(SIGBUS);
    SNKSignalRegister(SIGPIPE);
    
static void SNKSignalRegister(int signal) {
    struct sigaction action;
    action.sa_sigaction = mySNKSignalHandle;
    action.sa_flags = SA_NODEFER | SA_SIGINFO;
    sigemptyset(&action.sa_mask);
    sigaction(signal, &action, 0);
}
```

##### 处理接收到的Signal信号

```objective-c
void mySNKSignalHandle(int signal, siginfo_t *info, void *context)
{
    int32_t exceptionCount = OSAtomicIncrement32(&KSNKUncaughtExceptionCount);//全局计数器,原子操作
    if (exceptionCount > 10){
        return;
    }
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:[NSNumber numberWithInt:signal] forKey:kSNKSignalType];
    [userInfo setObject:[SNKCrashCatch catchBacktrace] forKey:kSNKCatchBacktrace];
    [userInfo setObject:@"SigCrash" forKey:@"crash type"];
    [userInfo setObject:[SNKCrashCatch getAppinfo] forKey:@"appinfo"];
    [userInfo setObject:@(exceptionCount) forKey:@"exceptionCount"];
    
    NSException *newException = [NSException exceptionWithName:kSNKSignalExceptionName reason:[NSString stringWithFormat:@"Signal = %d",signal] userInfo:userInfo];
    [[[SNKCrashCatch alloc] init] performSelectorOnMainThread:@selector(handleException:) withObject:newException waitUntilDone:YES];
    !oldSignalHandler? :oldSignalHandler(signal,info,context);
}
```

##### 处理完后，不忘记将Signal信号继续传递下去

```objective-c
    !oldSignalHandler? :oldSignalHandler(signal,info,context);
```

##### 如何验证调试Signal信号？

###### 第一种：Debug时主动触发Xcode抛出Signal：

<img src="https://tva1.sinaimg.cn/large/007S8ZIlgy1gez2j9qcg2j30l4152nkz.jpg" alt="image-20200520175239544" style="zoom:15%;" />

大多`NSException`异常（比如上图的数组越界），我们看到系统的堆栈最终调用到了`abort_message>abort`, 这个`abort`就是`signal`信号，只是在链接`Run Xcode Debug`时，LLDB插入了异常处理程序，该异常处理程序在EXC_BAD_ACCESS阶段进行了处理，防止信号到达程序。

解决办法：将指定的`Signal`处理抛给开发层处理，在`Crash`的方法前面打上断点，然后在`LLDB`调试器内执行如下命令：

```objective-c
pro hand -p true -s false SIGABRT
```

```objective-c
命令解读:
pro hand：process handle缩写
-p:PASS
-S:STOP
SIGABRT:信号名
```

###### 第二种方法，先模拟一个野指针的`Signal`: 

这个野指针的`Crash`不能用上面的命令，在`Xcode`里重现， 只能断开`Xcode`，然后去沙盒里看日志

```objective-c
@property(nonatomic, assign) NSMutableArray *testList;
self.testList = [NSMutableArray new];
[self.testList addObject:@""];

```

去沙盒看我们的`Signal`捕获到的 log文件

> Signal = 11，11对应 `SIGSEGV` （试图访问未分配给自己的内存, 或试图往没有写权限的内存地址写数据）

我们再看下`Xcode-Window-Devices And Simulators-View Devices Logs` 里面的crash log

```objective-c
Exception Type:  EXC_BAD_ACCESS (SIGSEGV)
Exception Subtype: KERN_INVALID_ADDRESS at 0x0000000e8a6fc020
VM Region Info: 0xe8a6fc020 is not in any region.  Bytes after previous region: 51177832481  
      REGION TYPE                      START - END             [ VSIZE] PRT/MAX SHRMOD  REGION DETAIL
      MALLOC_NANO            0000000280000000-00000002a0000000 [512.0M] rw-/rwx SM=PRV  
--->  
      UNUSED SPACE AT END

Termination Signal: Segmentation fault: 11
Termination Reason: Namespace SIGNAL, Code 0xb
Terminating Process: exc handler [5496]
Triggered by Thread:  0

Thread 0 name:  Dispatch queue: com.apple.main-thread
Thread 0 Crashed:
0   libobjc.A.dylib               	0x00000001bf816240 objc_retain + 16
1   CrashDemo                     	0x00000001006db474 -[ViewController signalAction:] + 29812 (ViewController.m:43)
2   libobjc.A.dylib               	0x00000001bf7f7d5c -[NSObject performSelector:withObject:withObject:] + 76
3   UIKitCore                     	0x00000001c3b4a27c -[UIApplication sendAction:to:from:forEvent:] + 100
4   UIKitCore                     	0x00000001c3571588 -[UIControl sendAction:to:forEvent:] + 208
```

可以确认野指针的Signal的信号就是 11 `SIGSEGV`

##### 导致崩溃的最常见的两个信号：

`EXC_BAD_ACCESS`：是您尝试访问未映射到应用程序的内存时内核发送给应用程序的`Mach`异常。如果在`Mach`没有被处理，将被包装成一个`SIGBUS`或`SIGSEGVBSD`信号。
`SIGABRT`是当未捕获到`NSException`或`obj_exception_throw`时，应用程序向自身发送的BSD信号

##### 大部分Signal信号说明：

> ```objective-c
> SIGHUP：本信号在用户终端连接(正常或非正常)结束时发出, 通常是在终端的控制进程结束时, 通知同一session内的各个作业, 这时它们与控制终端不再关联。
> SIGINT：程序终止(interrupt)信号, 在用户键入INTR字符(通常是Ctrl-C)时发出，用于通知前台进程组终止进程。
> SIGQUIT：和SIGINT类似, 但由QUIT字符(通常是Ctrl-)来控制. 进程在因收到SIGQUIT退出时会产生core文件, 在这个意义上类似于一个程序错误信号。
> SIGILL：执行了非法指令. 通常是因为可执行文件本身出现错误, 或者试图执行数据段. 堆栈溢出时也有可能产生这个信号。
> SIGTRAP：由断点指令或其它trap指令产生. 由debugger使用。
> SIGABRT：调用abort函数生成的信号。
> SIGBUS：非法地址, 包括内存地址对齐(alignment)出错。比如访问一个四个字长的整数, 但其地址不是4的倍数。它与SIGSEGV的区别在于后者是由于对合法存储地址的非法访问触发的(如访问不属于自己存储空间或只读存储空间)。
> SIGFPE：在发生致命的算术运算错误时发出. 不仅包括浮点运算错误, 还包括溢出及除数为0等其它所有的算术的错误。
> SIGKILL：用来立即结束程序的运行. 本信号不能被阻塞、处理和忽略。如果管理员发现某个进程终止不了，可尝试发送这个信号。
> SIGUSR1：留给用户使用
> SIGSEGV：试图访问未分配给自己的内存, 或试图往没有写权限的内存地址写数据.
> SIGUSR2：留给用户使用
> SIGPIPE：管道破裂。这个信号通常在进程间通信产生，比如采用FIFO(管道)通信的两个进程，读管道没打开或者意外终止就往管道写，写进程会收到SIGPIPE信号。此外用Socket通信的两个进程，写进程在写Socket的时候，读进程已经终止。
> SIGALRM：时钟定时信号, 计算的是实际的时间或时钟时间. alarm函数使用该信号.
> SIGTERM：程序结束(terminate)信号, 与SIGKILL不同的是该信号可以被阻塞和处理。通常用来要求程序自己正常退出，shell命令kill缺省产生这个信号。如果进程终止不了，我们才会尝试SIGKILL。
> SIGCHLD：子进程结束时, 父进程会收到这个信号。
> 如果父进程没有处理这个信号，也没有等待(wait)子进程，子进程虽然终止，但是还会在内核进程表中占有表项，这时的子进程称为僵尸进程。这种情 况我们应该避免(父进程或者忽略SIGCHILD信号，或者捕捉它，或者wait它派生的子进程，或者父进程先终止，这时子进程的终止自动由init进程 来接管)。
> SIGCONT：让一个停止(stopped)的进程继续执行. 本信号不能被阻塞. 可以用一个handler来让程序在由stopped状态变为继续执行时完成特定的工作. 例如, 重新显示提示符
> SIGSTOP：停止(stopped)进程的执行. 注意它和terminate以及interrupt的区别:该进程还未结束, 只是暂停执行. 本信号不能被阻塞, 处理或忽略.
> SIGTSTP：停止进程的运行, 但该信号可以被处理和忽略. 用户键入SUSP字符时(通常是Ctrl-Z)发出这个信号
> SIGTTIN：当后台作业要从用户终端读数据时, 该作业中的所有进程会收到SIGTTIN信号. 缺省时这些进程会停止执行.
> SIGTTOU：类似于SIGTTIN, 但在写终端(或修改终端模式)时收到.
> SIGURG：有”紧急”数据或out-of-band数据到达socket时产生.
> SIGXCPU：超过CPU时间资源限制. 这个限制可以由getrlimit/setrlimit来读取/改变。
> SIGXFSZ：当进程企图扩大文件以至于超过文件大小资源限制。
> SIGVTALRM：虚拟时钟信号. 类似于SIGALRM, 但是计算的是该进程占用的CPU时间.
> SIGPROF：类似于SIGALRM/SIGVTALRM, 但包括该进程用的CPU时间以及系统调用的时间.
> SIGWINCH：窗口大小改变时发出.
> SIGIO：文件描述符准备就绪, 可以开始进行输入/输出操作.
> SIGPWR：Power failure
> SIGSYS：非法的系统调用
> ```

####  NSException异常捕获

和Signal的流程大同小异

##### 先检查第三方有没有注册过NSSetUncaughtExceptionHandler，存下来处理完后要传递下去，不然会影响exception传递，影响第三方crash统计

```objective-c
oldUncaughtExceptionHandler = NSGetUncaughtExceptionHandler();
```

##### 注册我们自己的exception捕获函数

```objective-c
NSSetUncaughtExceptionHandler(&uncaught_exception_handler);
```

##### 处理系统抛出的exception异常

```objective-c
static void uncaught_exception_handler(NSException *exception) {
    NSString *name = exception.name;
    NSString *reason = exception.reason;
    NSArray *callStack = exception.callStackSymbols;
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:[exception userInfo]];
    [userInfo setValue:callStack forKey:@"callStackSymbols"];
    [userInfo setValue:[SNKCrashCatch catchBacktrace] forKey:@"catchBacktrace"];
    [userInfo setValue:[SNKCrashCatch getAppinfo] forKey:@"appinfo"];
    NSException *newException = [NSException exceptionWithName:name reason:reason userInfo:userInfo];
    
    [[[SNKCrashCatch alloc] init] performSelectorOnMainThread:@selector(handleException:) withObject:newException waitUntilDone:YES];
}
```

处理完后，不忘记将exception继续传递下去

```objective-c
!oldUncaughtExceptionHandler? :oldUncaughtExceptionHandler(exception);
```

### 捕获到Crash info时，如何阻止App闪退，做到保活实时上传?

<img src="https://tva1.sinaimg.cn/large/007S8ZIlgy1ggpnd0l4u5j30kw1j8e31.jpg" alt="image-20200713210504275" style="zoom:10%;" />

#### 看一下崩溃时的系统堆栈流程的源码

##### 1.CFRunLoopRunSpecific:

 https://opensource.apple.com/source/CF/CF-1153.18/CFRunLoop.c.auto.html

```objective-c
SInt32 CFRunLoopRunSpecific(CFRunLoopRef rl, CFStringRef modeName, CFTimeInterval seconds, Boolean returnAfterSourceHandled) {     
    CHECK_FOR_FORK();
    if (__CFRunLoopIsDeallocating(rl)) return kCFRunLoopRunFinished;
    __CFRunLoopLock(rl);
    CFRunLoopModeRef currentMode = __CFRunLoopFindMode(rl, modeName, false);
    if (NULL == currentMode || __CFRunLoopModeIsEmpty(rl, currentMode, rl->_currentMode)) {
	Boolean did = false;
	if (currentMode) __CFRunLoopModeUnlock(currentMode);
	__CFRunLoopUnlock(rl);
	return did ? kCFRunLoopRunHandledSource : kCFRunLoopRunFinished;
    }
    volatile _per_run_data *previousPerRun = __CFRunLoopPushPerRunData(rl);
    CFRunLoopModeRef previousMode = rl->_currentMode;
    rl->_currentMode = currentMode;
    int32_t result = kCFRunLoopRunFinished;

	if (currentMode->_observerMask & kCFRunLoopEntry ) __CFRunLoopDoObservers(rl, currentMode, kCFRunLoopEntry);
	result = __CFRunLoopRun(rl, currentMode, seconds, returnAfterSourceHandled, previousMode);
	if (currentMode->_observerMask & kCFRunLoopExit ) __CFRunLoopDoObservers(rl, currentMode, kCFRunLoopExit);

        __CFRunLoopModeUnlock(currentMode);
        __CFRunLoopPopPerRunData(rl, previousPerRun);
	rl->_currentMode = previousMode;
    __CFRunLoopUnlock(rl);
    return result;
}

void CFRunLoopRun(void) {	/* DOES CALLOUT */
    int32_t result;
    do {
        result = CFRunLoopRunSpecific(CFRunLoopGetCurrent(), kCFRunLoopDefaultMode, 1.0e10, false);
        CHECK_FOR_FORK();
    } while (kCFRunLoopRunStopped != result && kCFRunLoopRunFinished != result);
}

SInt32 CFRunLoopRunInMode(CFStringRef modeName, CFTimeInterval seconds, Boolean returnAfterSourceHandled) {   
    CHECK_FOR_FORK();
    return CFRunLoopRunSpecific(CFRunLoopGetCurrent(), modeName, seconds, returnAfterSourceHandled);
}
```

真正的__CFRunLoopRun有320行源码，就不往上贴了,就贴一下框架逻辑。



##### 2.异常抛出objc_exception_throw：

https://opensource.apple.com/source/objc4/objc4-781/runtime/objc-exception.mm.auto.html

```objective-c
void objc_exception_throw(id obj)
{
    struct objc_exception *exc = (struct objc_exception *)
        __cxa_allocate_exception(sizeof(struct objc_exception));

    obj = (*exception_preprocessor)(obj);

    // Retain the exception object during unwinding
    // because otherwise an autorelease pool pop can cause a crash
    [obj retain];

    exc-&gt;obj = obj;
    exc-&gt;tinfo.vtable = objc_ehtype_vtable+2;
    exc-&gt;tinfo.name = object_getClassName(obj);
    exc-&gt;tinfo.cls_unremapped = obj ? obj-&gt;getIsa() : Nil;

    if (PrintExceptions) {
        _objc_inform(&quot;EXCEPTIONS: throwing %p (object %p, a %s)&quot;, 
                     exc, (void*)obj, object_getClassName(obj));
    }

    if (PrintExceptionThrow) {
        if (!PrintExceptions)
            _objc_inform(&quot;EXCEPTIONS: throwing %p (object %p, a %s)&quot;, 
                         exc, (void*)obj, object_getClassName(obj));
        void* callstack[500];
        int frameCount = backtrace(callstack, 500);
        backtrace_symbols_fd(callstack, frameCount, fileno(stderr));
    }
    
    OBJC_RUNTIME_OBJC_EXCEPTION_THROW(obj);  // dtrace probe to log throw activity
    __cxa_throw(exc, &amp;exc-&gt;tinfo, &amp;_objc_exception_destructor);
    __builtin_trap();
}


```



##### 3.objc_exception_rethrow：

https://opensource.apple.com/source/objc4/objc4-781/runtime/objc-exception.mm.auto.html

```objective-c
void objc_exception_rethrow(void)
{
    // exception_preprocessor doesn't get another bite of the apple
    if (PrintExceptions) {
        _objc_inform(&quot;EXCEPTIONS: rethrowing current exception&quot;);
    }
    OBJC_RUNTIME_OBJC_EXCEPTION_RETHROW(); // dtrace probe to log throw activity.
    __cxa_rethrow();
    __builtin_trap();
}
```

##### 4._objc_terminate：

 https://opensource.apple.com/source/objc4/objc4-781/runtime/objc-exception.mm.auto.html

```objective-c
* _objc_terminate
* Custom std::terminate handler.
*
* The uncaught exception callback is implemented as a std::terminate handler. 
* 1. Check if there's an active exception
* 2. If so, check if it's an Objective-C exception
* 3. If so, call our registered callback with the object.
* 4. Finally, call the previous terminate handler.
**********************************************************************/
static void (*old_terminate)(void) = nil;
static void _objc_terminate(void)
{
    if (PrintExceptions) {
        _objc_inform(&quot;EXCEPTIONS: terminating&quot;);
    }

    if (! __cxa_current_exception_type()) {
        // No current exception.
        (*old_terminate)();
    }
    else {
        // There is a current exception. Check if it's an objc exception.
        @try {
            __cxa_rethrow();
        } @catch (id e) {
            // It's an objc object. Call Foundation's handler, if any.
            (*uncaught_handler)((id)e);
            (*old_terminate)();
        } @catch (...) {
            // It's not an objc object. Continue to C++ terminate.
            (*old_terminate)();
        }
    }
}
```



##### 5.__pthread_kill：

https://opensource.apple.com/source/xnu/xnu-6153.81.5/bsd/kern/kern_sig.c.auto.html

```objective-c
__pthread_kill(__unused proc_t p, struct __pthread_kill_args *uap,
    __unused int32_t *retval)
{
	thread_t target_act;
	int error = 0;
	int signum = uap->sig;
	struct uthread *uth;

	target_act = (thread_t)port_name_to_thread(uap->thread_port,
	    PORT_TO_THREAD_NONE);

	if (target_act == THREAD_NULL) {
		return ESRCH;
	}
	if ((u_int)signum >= NSIG) {
		error = EINVAL;
		goto out;
	}

	uth = (struct uthread *)get_bsdthread_info(target_act);

	if (uth->uu_flag & UT_NO_SIGMASK) {
		error = ESRCH;
		goto out;
	}

	if ((thread_get_tag(target_act) & THREAD_TAG_WORKQUEUE) && !uth->uu_workq_pthread_kill_allowed) {
		error = ENOTSUP;
		goto out;
	}

	if (signum) {
		psignal_uthread(target_act, signum);
	}
out:
	thread_deallocate(target_act);
	return error;
}
```

我们看到系统崩溃涉及到各个系统库，比较难拿到完整的堆栈调用链，最好是能够调试系统整个源码，在__pthread_kill打个断点看一下。

#### 如何阻止程序立即crash，给我们上传到server争取时间?

从`CFRunLoopRunSpecific`上，可以看到`CFRunLoopRun`的核心是在一个`do while `循环不停的调用`CFRunLoopRunSpecific`。

循环条件为`kCFRunLoopRunStopped != result && kCFRunLoopRunFinished != result`，可以猜测这个条件最终会不被满足，跳出循环后，线程不被保活，最终`thread_deallocate`

那我们就可以有一个思路保活 ` runloop`。

既然系统在不停的调用 `CFRunLoopRunSpecific`，那我们也写个while试试?,可惜`CFRunLoopRunSpecific`并没有暴露在`runloop.h`

按照猜想的大方向

##### 1.就在crash的异常捕获函数里，先写个`while`循环试试把

```objective-c
- (void)handleException:(NSException *)exception
{
__block BOOL success = NO;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
       [self saveException:exception];
     //upload exception ....
        success = YES;
    });
  while (!success) {
  }
 // success为上传成功后再赋值为YES
}
```

  测试结果可行！在`success=YES `之前App不会闪退，只是主线程被`while`占用，也不能响应其他事件。但可以起动一个子线程去做上传的操作，跑一会手机非常烫😆。



我们再去看看`runloop.h`，可以看到有启动`runloop`的系统函数，一个是` CFRunLoopRun`，一个是 `CFRunLoopRunInMode`

##### 2.Crash时调用下`CFRunLoopRun`

```
 - (void)handleException:(NSException *)exception{
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
       [self saveException:exception];
     //upload ....
        CFRunLoopStop(CFRunLoopGetCurrent());
    });
    CFRunLoopRun();
 }
```

测试也可以用，如果不调用CFRunLoopStop的话，甚至程序都不会Crash了，runloop还能响应程序的UI触摸交互。

注意点：在这里，我们有主动`CFRunLoopStop`的操作，要确认是否会影响crash信号传递后的第三方的处理！

我们可以自己多注册几个`NSSetUncaughtExceptionHandler（）`来模拟一下多个第三方Crash统计 场景。

##### 3.Crash时调用下`CFRunLoopRunInMode()`

```objective-c
 - (void)handleException:(NSException *)exception{
         //当接收到异常处理消息时，让程序开始runloop，防止程序收到signal abrt
        CFRunLoopRef runLoop = CFRunLoopGetCurrent();
        CFArrayRef allModes = CFRunLoopCopyAllModes(runLoop);//得到当前线程runloop对象定义的mode
        while (!success) {
            for (NSString *mode in (__bridge NSArray *)allModes){
                CFRunLoopRunInMode((CFStringRef)mode, 0.001, false);//激活runloop
                CFRunLoopModeRef
            }
        }
        CFRelease(allModes);
 }
```

这个效果和上面2一样，但是这个要放心许多，没有去主动去stop runloop
