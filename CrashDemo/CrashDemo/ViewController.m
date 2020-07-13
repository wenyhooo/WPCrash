//
//  ViewController.m
//  CrashDemo
//
//  Created by liwenhao on 2020/4/13.
//  Copyright © 2020 liwenhaopro. All rights reserved.
//

#import "ViewController.h"
#import "SNKCrashCatch.h"
#import <mach/exception_types.h>

@interface ViewController ()
@property(nonatomic, assign) NSMutableArray *testList;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

}

#pragma mark - action
- (IBAction)beyondBoundsCrashAction:(UIButton *)sender {
    //SIGABRT
    //    crash前执行这个pro hand -p true -s false SIGABRT,可抛出signal代替NSException
    NSMutableArray *arr = [NSMutableArray new];
    [arr removeObjectAtIndex:5];
}

- (IBAction)crashAndUpload:(UIButton *)sender
{
    [self test2];
}

- (IBAction)signalAction:(id)sender {
    //    SIGSEGV
    //此信号,debug时,无法捕获.需断开xcode链接
    self.testList = [NSMutableArray new];
    [self.testList addObject:@""];
    
}
- (IBAction)appActiveAction:(id)sender {
    self.view.backgroundColor = ([self.view.backgroundColor isEqual: [UIColor lightGrayColor]])?[UIColor greenColor]:[UIColor lightGrayColor];
}


- (void)test1
{
    testBlock();
}

- (void)test2
{
//    testBlock();
    dispatch_async(dispatch_get_global_queue(0, 0), testBlock);
}

void (^testBlock)(void) = ^() {
    NSMutableArray *testArr = [NSMutableArray new];
    [testArr removeObjectAtIndex:5];
};
@end
