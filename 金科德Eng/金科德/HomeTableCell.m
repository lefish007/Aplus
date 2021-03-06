//
//  HomeTableCell.m
//  金科德
//
//  Created by Yangliu on 13-9-6.
//  Copyright (c) 2013年 TouchCloud Information Technology (Shanghai) Co.,Ltd. All rights reserved.
//

#import "HomeTableCell.h"
#import "NetKit.h"

@implementation HomeTableCell
{
    NSTimer *timer_;        
}
@synthesize delegate;
@synthesize isON;
@synthesize indexLbl;
@synthesize statusImgV;
@synthesize statusLbl;
@synthesize nameLbl;
@synthesize button;
@synthesize devID;

- (void)dealloc
{
    [statusImgV release];
    [indexLbl release];
    [statusLbl release];
    [super dealloc];
}

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code
    }
    return self;
}

- (void)timeoutHandle
{
    [self.button setEnabled:TRUE];
}

-(void)sendSwitchCmd:(BOOL)isNo
{
    [[NetKit instance] switchDevice:isNo devID:self.devID delegate:self];
    //[self.socket switchDevice:isNo devID:devID];
    [self.button setEnabled:FALSE];
    //启动定时器
    timer_ = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(timeoutHandle) userInfo:nil repeats:NO];
}

- (IBAction)switchBtn:(UIButton *)sender {
    if ([self.statusLbl.text isEqualToString:@"OFF"]) {
        [self sendSwitchCmd:YES];
    } else if ([self.statusLbl.text isEqualToString:@"ON"]) {
        [self sendSwitchCmd:NO];
    }
}

- (void)switchDeviceHandler:(BOOL)success devID:(Byte)devID
{
    if (!success) {
        return;
    }
    if (devID==self.devID) {
        if ([self.statusLbl.text isEqualToString:@"OFF"]) {
            self.statusLbl.text = @"ON";
        } else if ([self.statusLbl.text isEqualToString:@"ON"]) {
            self.statusLbl.text = @"OFF";
        }
        [self.button setEnabled:YES];
    }
}

/*
// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect
{
    // Drawing code
}
*/

@end
