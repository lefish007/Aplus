//
//  AddDeviceViewController.h
//  金科德
//
//  Created by Yangliu on 13-9-9.
//  Copyright (c) 2013年 TouchCloud Information Technology (Shanghai) Co.,Ltd. All rights reserved.
//

#import "BaseViewController.h"
#import "AsyncUdpSocket.h"

@interface AddDeviceViewController : BaseViewController
{
    
}

@property(nonatomic,retain)AsyncUdpSocket *udpSocket;

@end
