//
//  NetKit.m
//  POTEK
//
//  Created by Eason Zhao on 14-4-18.
//  Copyright (c) 2014年 TouchCloud Information Technology (Shanghai) Co.,Ltd. All rights reserved.
//

#import "NetKit.h"
#import "IPAddress.h"

#include <sys/socket.h> // Per msqr
#include <sys/sysctl.h>
#include <net/if.h>
#include <net/if_dl.h>

static NetKit *instance_ = nil;

#define GROUP_IP @"255.255.255.255"
#define GROUP_PORT  18890
#define CLIENT_PORT 18891
//long GROUP_ID=1;
//long CLIENT_ID=2;

@implementation NetKit
{
    AsyncUdpSocket *groupSocket_;       //广播用socket
    AsyncUdpSocket *clientSocket_;      //net直连socket
    NSData *mac_;                       //本机mac地址
    NSData *netMac_;
    NSMutableArray *ipAddressArr_;
    NSString *netIP_;
    
    id checkSearchCodeDelegate_;
    id addDeviceDelegate_;
    id delDeviceDelegate_;
    
    //id switchDeviceDelegate_;
    NSMutableArray *switchDeviceDelegates_;
}

@synthesize onOffDelegate;

- (void)dealloc
{
    [groupSocket_ release];
    [mac_ release];
    if (ipAddressArr_) {
        [ipAddressArr_ release];
    }
    if (netIP_) {
        [netIP_ release];
        [clientSocket_ release];
    }
    if (switchDeviceDelegates_) {
        [switchDeviceDelegates_ release];
    }
    [super dealloc];
}

- (id)init
{
    self = [super init];
    if (self) {
        //初始化广播socket
        groupSocket_ = [[AsyncUdpSocket alloc] initWithDelegate:self];
        //groupSocket_ = [[[AsyncUdpSocket alloc] initWithDelegate:self] autorelease];
        NSError *error = nil;
        
        [groupSocket_ bindToPort: 18000 error: &error];
        [groupSocket_ enableBroadcast:YES error:nil]; //发送广播
        [groupSocket_ receiveWithTimeout: -1 tag: 0];
        
        mac_ = [self macaddress];
    }
    return self;
}

+(NetKit*)instance
{
    if (instance_==nil) {
        instance_ = [[NetKit alloc] init];
    }
    return instance_;
}

- (NSData *) macaddress
{
    int                    mib[6];
    size_t                len;
    char                *buf;
    unsigned char        *ptr;
    struct if_msghdr    *ifm;
    struct sockaddr_dl    *sdl;
    
    mib[0] = CTL_NET;
    mib[1] = AF_ROUTE;
    mib[2] = 0;
    mib[3] = AF_LINK;
    mib[4] = NET_RT_IFLIST;
    
    if ((mib[5] = if_nametoindex("en0")) == 0) {
        printf("Error: if_nametoindex error/n");
        return NULL;
    }
    
    if (sysctl(mib, 6, NULL, &len, NULL, 0) < 0) {
        printf("Error: sysctl, take 1/n");
        return NULL;
    }
    
    if ((buf = malloc(len)) == NULL) {
        printf("Could not allocate memory. error!/n");
        return NULL;
    }
    
    if (sysctl(mib, 6, buf, &len, NULL, 0) < 0) {
        printf("Error: sysctl, take 2");
        return NULL;
    }
    
    ifm = (struct if_msghdr *)buf;
    sdl = (struct sockaddr_dl *)(ifm + 1);
    ptr = (unsigned char *)LLADDR(sdl);
    NSData *data = [[NSData alloc] initWithBytes:ptr length:6];
    free(buf);
    return data;
}

- (BOOL)onUdpSocket:(AsyncUdpSocket *)sock didReceiveData:(NSData *)data withTag:(long)tag fromHost:(NSString *)host port:(UInt16)port
{
    if (sock==groupSocket_) {
        //如果是本机ip，不做处理
        if (!ipAddressArr_) {
            ipAddressArr_ = [[NSMutableArray alloc] init];
            InitAddresses();
            GetIPAddresses();
            GetHWAddresses();
            for (int i=0; i<MAXADDRS; i++) {
                if (ip_addrs[i]==0) {
                    break;
                }
                NSString *str = [[NSString alloc] initWithUTF8String:ip_names[i]];
                [ipAddressArr_ addObject:str];
            }
        }
        for (NSString *str in ipAddressArr_) {
            NSRange fundObj = [host rangeOfString:str options:NSCaseInsensitiveSearch];
            if (fundObj.length>0) {
                return NO;
            }
            
            if (!data) {
                return FALSE;
            }
            Byte *pData = (Byte*)[data bytes];
            if (pData[0]!=0x41 || pData[1]!=0x54) {
                return FALSE;
            }
        }
        netMac_ = [[NSData alloc]initWithBytes:[data bytes]+3 length:6];
        //netMac_ = [netMac_ subdataWithRange:NSMakeRange(3, 6)];
        netIP_ = [[NSString alloc] initWithString:host];
    
        //创建socket
        if (clientSocket_==nil) {
            clientSocket_ = [[AsyncUdpSocket alloc] initWithDelegate:self];
            NSError *error = nil;
            [clientSocket_ bindToPort: 18001 error: &error];
            [clientSocket_ receiveWithTimeout: -1 tag: 0];
        }
    
        Byte *pData = (Byte*)[data bytes];
        Byte *pos = pData+24;
        NSMutableArray *arr = [[NSMutableArray alloc] init];
        while (*pos!=0xfe) {
            NSData *tmp = [[NSData alloc] initWithBytes:pos length:3];
            AAdapter *ada = [[AAdapter alloc] initWithData: tmp];
            [arr addObject:ada];
            pos += 3;
        }
        [checkSearchCodeDelegate_ checkSearchCodeHandler:YES Devs:arr];
        
    } else if (sock==clientSocket_) {
        //如何判断这包数据是开关量的
        Byte* pData = (Byte*)[data bytes];
        //验证数据头
        if (pData[0]!=0x6f || pData[1]!=0x6b) {
            return FALSE;
        }
        //判断协议类型
        int devID = pData[22];
        Byte type = pData[23];
        switch (type) {
            case 0xa1:
                for (id tmp in switchDeviceDelegates_) {
                    [tmp switchDeviceHandler:pData[23]==0x01 ? YES : NO
                                       devID:devID];
                }
                return YES;
                break;
            case 0xa5:
            {
                [addDeviceDelegate_ addDeviceHandler:YES];
                return YES;
                break;
            }
            case 0xa7:
                [delDeviceDelegate_ delDeviceHandler:YES devID:pData[21]];
                return YES;
                break;
            case 0x05:
                [self.onOffDelegate allOnOffHandler];
                break;
            default:
                break;
        }
        
        
    }
    return YES;
}

- (void)checkSearchCode:(id)delegate
{
    Byte* macByte = (Byte*)[mac_ bytes];
    Byte cmd[] = {
        0x41, 0x54,
        0x00,
        0x31, 0x32, 0x33, 0x34, 0x35, 0x36,
        macByte[0], macByte[1], macByte[2], macByte[3], macByte[4], macByte[5],
        0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6,
        0x01, 0x01, 0xa3,
        0xfe
    };
    cmd[2] = sizeof(cmd)-2;
    NSData* data = [[NSData alloc] initWithBytes:cmd length:sizeof(cmd)];
    checkSearchCodeDelegate_ = delegate;
    [self sendData: data socket:groupSocket_];
}

- (void)switchDevice:(BOOL)isOn devID:(Byte)devID delegate:(id)delegate
{
    if (!switchDeviceDelegates_) {
        switchDeviceDelegates_ = [[NSMutableArray alloc] init];
    }
    if (![switchDeviceDelegates_ containsObject:delegate])
    {
        [switchDeviceDelegates_ addObject:delegate];
    }
    
    Byte* macByte = (Byte*)[netMac_ bytes];
    Byte* macByte1 = (Byte*)[mac_ bytes];
    Byte cmd[] =
    {
        0x41, 0x54,
        0x00,   //数据长度
        //net的mac地址
        macByte[0], macByte[1], macByte[2], macByte[3], macByte[4], macByte[5],
        //本机的mac地址
        macByte1[0], macByte1[1], macByte1[2], macByte1[3], macByte1[4], macByte1[5],
        0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6,             //数据秘钥
        0x01,           //设备类型
        devID,           //设备编号(22)
        0x01,            //控制类型 0x01代表开关量控制
        0x00,           //开关量(24)
        0xfe
    };
    cmd[2] = sizeof(cmd)-2;
    if (isOn) {
        cmd[24] = 0x01;
    }
    [self sendData:[NSData dataWithBytes:cmd length:sizeof(cmd)] socket:clientSocket_];

}

-(void)sendData:(NSData*)data socket:(AsyncUdpSocket*)sock
{
    BOOL res = FALSE;
    if (sock==groupSocket_) {
        res = [sock sendData: data
                      toHost: GROUP_IP
                        port: GROUP_PORT
                 withTimeout: -1
                         tag: 0];
    } else if (sock==clientSocket_) {
        res = [sock sendData: data
                      toHost: netIP_
                        port: GROUP_PORT
                 withTimeout: -1
                         tag: 0];
    }
    [sock receiveWithTimeout:-1 tag:0];
    
    //开始发送
	if (!res)
    {
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle: @"UDP"
														message: @"发送失败"
													   delegate: self
											  cancelButtonTitle: @"取消"
											  otherButtonTitles: nil];
		[alert show];
		[alert release];
	}
}

-(void)addDevice:(id)delegate
{
    addDeviceDelegate_ = delegate;
    Byte* macByte = (Byte*)[netMac_ bytes];
    Byte* macByte1 = (Byte*)[mac_ bytes];
    Byte tmp[6] = {0};
    if (macByte==nil) {
        macByte = tmp;
    }
    Byte cmd[] =
    {
        0x41, 0x54,
        0x00,   //数据长度
        //net的mac地址
        macByte[0], macByte[1], macByte[2], macByte[3], macByte[4], macByte[5],
        //本机的mac地址
        macByte1[0], macByte1[1], macByte1[2], macByte1[3], macByte1[4], macByte1[5],
        0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6,             //数据秘钥
        0x01, 0x01,
        0xa5,
        0xfe
    };
    cmd[2] = sizeof(cmd)-2;
    NSData* data = [[NSData alloc] initWithBytes:cmd length:sizeof(cmd)];
    [self sendData: data socket:clientSocket_];
}

- (void)delDevice:(Byte)devID delegate:(id)delegate
{
    delDeviceDelegate_ = delegate;
    Byte* macByte = (Byte*)[netMac_ bytes];
    Byte* macByte1 = (Byte*)[mac_ bytes];
    Byte tmp[6] = {0};
    if (macByte==nil) {
        macByte = tmp;
    }
    Byte cmd[] =
    {
        0x41, 0x54,
        0x00,   //数据长度
        //net的mac地址
        macByte[0], macByte[1], macByte[2], macByte[3], macByte[4], macByte[5],
        //本机的mac地址
        macByte1[0], macByte1[1], macByte1[2], macByte1[3], macByte1[4], macByte1[5],
        0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6,             //数据秘钥
        devID, 0x01,
        0xa7,
        0xfe
    };
    cmd[2] = sizeof(cmd)-2;
    NSData* data = [[NSData alloc] initWithBytes:cmd length:sizeof(cmd)];
    [self sendData: data socket:clientSocket_];
}

- (void)countDown:(Byte)devID isOn:(BOOL)isOn hours:(int)hours
              min:(int)min sec:(int)sec enable:(BOOL)enable delegate:(id)delegate
{
    Byte* macByte = (Byte*)[netMac_ bytes];
    Byte* macByte1 = (Byte*)[mac_ bytes];
    Byte tmp[6] = {0};
    if (macByte==nil) {
        macByte = tmp;
    }
    Byte cmd[] =
    {
        0x41, 0x54,
        0x00,   //数据长度
        //net的mac地址
        macByte[0], macByte[1], macByte[2], macByte[3], macByte[4], macByte[5],
        //本机的mac地址
        macByte1[0], macByte1[1], macByte1[2], macByte1[3], macByte1[4], macByte1[5],
        0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6,             //数据秘钥
        devID, 0x03,
        isOn?0x00:0x01,       //开关
        hours, min, sec,           //时分秒
        0xfe
    };
    if (enable) {
        cmd[25] = cmd[25]|0x80;
    } else {
        cmd[25] = cmd[25]&0x7f;
    }
    cmd[2] = sizeof(cmd)-2;
    NSData* data = [[NSData alloc] initWithBytes:cmd length:sizeof(cmd)];
    [self sendData: data socket:clientSocket_];
}

- (void)allOn
{
    Byte* macByte = (Byte*)[netMac_ bytes];
    Byte* macByte1 = (Byte*)[mac_ bytes];
    Byte cmd[] =
    {
        0x41, 0x54,
        0x00,   //数据长度
        //net的mac地址
        macByte[0], macByte[1], macByte[2], macByte[3], macByte[4], macByte[5],
        //本机的mac地址
        macByte1[0], macByte1[1], macByte1[2], macByte1[3], macByte1[4], macByte1[5],
        0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6,             //数据秘钥
        0x01,           //设备类型
        0x00,           //设备编号(22)
        0x05,            //控制类型 0x01代表开关量控制
        0xff,           //开关量(24)
        0xfe
    };
    cmd[2] = sizeof(cmd)-2;
    [self sendData:[NSData dataWithBytes:cmd length:sizeof(cmd)] socket:clientSocket_];
}

- (void)allOff
{
    Byte* macByte = (Byte*)[netMac_ bytes];
    Byte* macByte1 = (Byte*)[mac_ bytes];
    Byte cmd[] =
    {
        0x41, 0x54,
        0x00,   //数据长度
        //net的mac地址
        macByte[0], macByte[1], macByte[2], macByte[3], macByte[4], macByte[5],
        //本机的mac地址
        macByte1[0], macByte1[1], macByte1[2], macByte1[3], macByte1[4], macByte1[5],
        0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6,             //数据秘钥
        0x01,           //设备类型
        0x00,           //设备编号(22)
        0x05,            //控制类型 0x01代表开关量控制
        0xf1,           //开关量(24)
        0xfe
    };
    cmd[2] = sizeof(cmd)-2;
    [self sendData:[NSData dataWithBytes:cmd length:sizeof(cmd)] socket:clientSocket_];
}
@end
