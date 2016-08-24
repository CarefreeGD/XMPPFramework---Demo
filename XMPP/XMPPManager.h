//
//  TalkTool.h
//  MattPhone
//
//  Created by guoduo on 16/3/15.
//  Copyright © 2016年 Matt. All rights reserved.
//

#import <UIKit/UIKit.h>

@class DDXMLElement;

@interface XMPPManager : NSObject

/* 初始化并启动ping */
-(void)autoPingProxyServer:(NSString*)strProxyServer;

/**
 *  链接服务器
 *
 *  @param user 用户名
 */
- (void)xmppConnect:(NSString *)user;


/**
 *  单例
 */
+ (XMPPManager *)shardManager;

/** 查询聊天记录 */
+ (NSMutableArray *)getChatHistory;

/**
 *  获得链接状态
 */
- (BOOL)getStates;

/**
 *  获得是否正在链接
 */
- (BOOL)getAuthenticating;

/**
 *  saveThreshold
 */
+ (void)saveThreshold;



@end
