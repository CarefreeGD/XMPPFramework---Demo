//
//  TalkTool.m
//  MattPhone
//
//  Created by guoduo on 16/3/15.
//  Copyright © 2016年 Matt. All rights reserved.
//

#import "XMPPManager.h"

#import <XMPP.h>
#import <XMPPAutoPing.h>
#import <XMPPReconnect.h>
#import <XMPPMessageArchiving.h>
#import <XMPPRosterCoreDataStorage.h>
#import <XMPPMessageArchivingCoreDataStorage.h>
#import <XMPPMessageArchiving_Contact_CoreDataObject.h> //最近联系人
#import <XMPPMessageArchiving_Message_CoreDataObject.h>

@interface XMPPManager () <NSFetchedResultsControllerDelegate,XMPPStreamDelegate>

@property (strong, nonatomic) XMPPStream                            *xmppStream;
@property (strong, nonatomic) NSManagedObjectContext                *xmppRosterManagedObjectContext;
@property (strong, nonatomic) NSFetchedResultsController            *fetchedResultsController;
@property (strong, nonatomic) XMPPAutoPing                          *xmppAutoPing;
@property (strong, nonatomic) XMPPMessageArchiving                  *xmppMessageArchiving;

@property (strong, nonatomic) XMPPReconnect                         *xmppReconnect;
@property (strong, nonatomic) NSManagedObjectContext                *xmppManagedObjectContext;
@property (strong, nonatomic) XMPPMessageArchivingCoreDataStorage   *messageStorage;
@property (strong, nonatomic) XMPPRosterCoreDataStorage             *xmppRosterStorage;
@property (strong, nonatomic) XMPPRoster                            *xmppRoster;// 模块

/**
 *  是否正在重新连接
 */
@property (nonatomic, assign) BOOL isReset;

/**
 *  是否正在重新认证
 */
@property (nonatomic, assign) BOOL isResetUser;

@end

@implementation XMPPManager

#pragma mark - 单例初始化

static XMPPManager *_manager;

+ (void)initialize
{
    _manager = [[XMPPManager alloc]init];
    [_manager autoPingProxyServer:@""];
    
}

+ (instancetype)allocWithZone:(struct _NSZone *)zone
{
    if (!_manager) {
        _manager = [super allocWithZone:zone];
    }
    return _manager;
}

+ (XMPPManager *)shardManager
{
    return _manager;
}
#pragma mark - xmpp初始化

- (XMPPStream *)xmppStream
{
    if (!_xmppStream) {
        [self xmppSetup];
    }
    return _xmppStream;
}
- (void)xmppSetup
{
    //创建xmppstream
    _xmppStream = [[XMPPStream alloc]init];
    
    [_xmppStream addDelegate:self delegateQueue:dispatch_get_main_queue()];
    
    //创建重写连接组件
    _xmppReconnect= [[XMPPReconnect alloc] init];
    //使组件生效
    [_xmppReconnect activate:_xmppStream];
    [_xmppReconnect setAutoReconnect:YES];
    
    //添加功能模块
    //1.autoPing 发送的时一个stream:ping 对方如果想表示自己是活跃的，应该返回一个pong
    _xmppAutoPing = [[XMPPAutoPing alloc] init];
    //所有的Module模块，都要激活active
    [_xmppAutoPing activate:_xmppStream];
    //autoPing由于它会定时发送ping,要求对方返回pong,因此这个时间我们需要设置
    [_xmppAutoPing setPingInterval:1000];
    //不仅仅是服务器来得响应;如果是普通的用户，一样会响应
    [_xmppAutoPing setRespondsToQueries:YES];
    //这个过程是C---->S  ;观察 S--->C(需要在服务器设置）
    
    
    //创建消息保存策略（规则，规定）
    _messageStorage = [XMPPMessageArchivingCoreDataStorage sharedInstance];
    //用消息保存策略创建消息保存组件
    _xmppMessageArchiving = [[XMPPMessageArchiving alloc]initWithMessageArchivingStorage:_messageStorage];
    //使组件生效
    [_xmppMessageArchiving activate:_xmppStream];
    //提取消息保存组件的coreData上下文
    _xmppManagedObjectContext = _messageStorage.mainThreadManagedObjectContext;
}


#pragma mark - 服务器链接
/**
 *  链接服务器
 *
 *  @param user 用户名
 */
- (void)xmppConnect:(NSString *)user
{
    
    if (self.xmppStream.isConnected) {
        [self.xmppStream disconnect];
    }else{
        id delegate = [UIApplication sharedApplication].delegate;
        _xmppStream = [delegate xmppStream];
        [_xmppStream addDelegate:self delegateQueue:dispatch_get_main_queue()];
        [self connect];
    }
}

- (void)connect
{
    //1.创建JID
    XMPPJID *jidTest = [XMPPJID jidWithString:[[[NSUserDefaults standardUserDefaults] objectForKey:@"openfire用户名"] stringByAppendingFormat:@"@%@",@"服务器域名"]];
    //设置用户
    [_xmppStream setMyJID:jidTest];
    //设置服务器
    [_xmppStream setHostName:@"服务器域名"];
    [_xmppStream setHostPort:5222];
    //连接服务器
    NSError *error = nil;
    [_xmppStream connectWithTimeout:10 error:&error];
    if (error) {
        NSLog(@"连接出错：%@",[error localizedDescription]);
    }
}

- (void)xmppStreamDidDisconnect:(XMPPStream *)sender withError:(NSError *)error
{
    [self connect];
}


//连接后的回调
-(void)xmppStreamDidConnect:(XMPPStream *)sender
{
    //连接成功后认证用户名和密码
    NSError *error = nil;
    self.isResetUser = NO;
    [_xmppStream authenticateWithPassword:@"密码" error:&error];
    if (error) {
        NSLog(@"认证错误：%@",[error localizedDescription]);
    }
}
//认证失败的回调
-(void)xmppStream:sender didNotAuthenticate:(DDXMLElement *)error
{
    NSLog(@"认证失败%@",error);
}


//认证成功后的回调
-(void)xmppStreamDidAuthenticate:(XMPPStream *)sender
{
    NSLog(@"认证成功");
    //设置在线状态
    XMPPPresence * pre = [XMPPPresence presence];
    [_xmppStream sendElement:pre];
}
//初始化并启动ping
-(void)autoPingProxyServer:(NSString*)strProxyServer
{
    [self.xmppAutoPing addDelegate:self delegateQueue:  dispatch_get_main_queue()];
    if (nil != strProxyServer)
    {
        _xmppAutoPing.targetJID = [XMPPJID jidWithString:strProxyServer];//设置ping目标服务器，如果为nil,则监听socketstream当前连接上的那个服务器
    }
}

//ping XMPPAutoPingDelegate的委托方法:
- (void)xmppAutoPingDidSendPing:(XMPPAutoPing *)sender
{
    NSLog(@"send:ping");
}
- (void)xmppAutoPingDidReceivePong:(XMPPAutoPing *)sender
{
    NSLog(@"receive:pang");
}

- (void)xmppAutoPingDidTimeout:(XMPPAutoPing *)sender
{
    NSLog(@"ping not pang");
    XMPPPresence * pre = [XMPPPresence presence];
    [_xmppStream sendElement:pre];
}
//ssl验证
- (void)xmppStream:(XMPPStream *)sender willSecureWithSettings:(NSMutableDictionary *)settings
{
    /*
     * Properly secure your connection by setting kCFStreamSSLPeerName
     * to your server domain name
     */
    [settings setObject:_xmppStream.myJID.domain forKey:(NSString *)kCFStreamSSLPeerName];
}

//ssl回复
- (void)xmppStream:(XMPPStream *)sender didReceiveTrust:(SecTrustRef)trust completionHandler:(void (^)(BOOL shouldTrustPeer))completionHandler
{
    /* Custom validation for your certificate on server should be performed */
    
    completionHandler(YES); // After this line, SSL connection will be established
}
- (void)xmppStream:(XMPPStream *)sender didReceivePresence:(XMPPPresence *)presence {
    NSString *presenceType     = [presence type];
    NSString *presenceFromUser = [[presence from] user];
    if (![presenceFromUser isEqualToString:[[sender myJID] user]]) {
        if ([presenceType isEqualToString:@"available"]) {
            //上线
        }else if ([presenceType isEqualToString:@"away"]) {
            //离开
        }else if ([presenceType isEqualToString:@"do not disturb"]) {
            //忙碌
        }else if ([presenceType isEqualToString:@"unavailable"]) {
            //下线
        }
    }
}
#pragma mark - xmpp 代理

//收到消息
- (void)xmppStream:(XMPPStream *)sender didReceiveMessage:(XMPPMessage *)message
{
    
}


#pragma mark - 消息发送

/**
 *  发送消息
 */
- (void)sendMessageWithText:(NSString *)string chatID:(NSString *)chatID date:(NSDate *)date element:(DDXMLElement *)element
{
    
    DDXMLElement         *xmlNode = [DDXMLElement elementWithName:@""];
    [xmlNode setStringValue:@""];
    [element addChild:xmlNode];
    
    [self element:element addAttribute:@"text" chatID:chatID date:date];
}

- (XMPPMessage *)element:(DDXMLElement *)element addAttribute:(NSString *)messageType chatID:(NSString *)chatID date:(NSDate *)date
{
    
    //消息类型
    [element addAttributeWithName:@"type"                stringValue:@"chat"];
    [element addAttributeWithName:@"发送类型(定义常量)"           boolValue:YES];
    //发送给谁
    [element addAttributeWithName:@"MessageAttributeSender" stringValue:[chatID stringByAppendingFormat:@"@%@",@""]];
    //由谁发送
    [element addAttributeWithName:@"MessageAttributeFrom"   stringValue:[[NSUserDefaults standardUserDefaults] objectForKey:@""]];
    
    //发送
    [_xmppStream sendElement:element];
    XMPPMessage *message = [XMPPMessage messageFromElement:element];
    
    return message;
}

#pragma mark - 消息记录


/** 查询聊天记录 */
+ (NSArray *)getChatHistory
{
    XMPPMessageArchivingCoreDataStorage *messageStorage = [XMPPManager shardManager].messageStorage;
    //获取coredata上下文
    NSFetchRequest                      *fetchRequest   = [[NSFetchRequest alloc] init];
    NSEntityDescription                 *entity         = [NSEntityDescription entityForName:messageStorage.messageEntityName inManagedObjectContext:
                                                          messageStorage.mainThreadManagedObjectContext];
    NSString                            *user           = [[NSUserDefaults standardUserDefaults] objectForKey:@"用户名"];
    NSString                            *jidStr         = [XMPPJID jidWithString:[user stringByAppendingFormat:@"@%@",@"域名"]].bare;//与前面保持一致
    NSPredicate                         *predicate      = [NSPredicate predicateWithFormat:@"streamBareJidStr = %@",jidStr];
    NSSortDescriptor                    *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"timestamp" ascending:YES];
    NSError                             *error          = nil;
    
    //设置过滤及排序条件
    [fetchRequest setEntity:entity];
    [fetchRequest setPredicate:predicate];
    [fetchRequest setSortDescriptors:[NSArray arrayWithObjects:sortDescriptor, nil]];
    NSArray *fetchedObjects = [messageStorage.mainThreadManagedObjectContext executeFetchRequest:fetchRequest error:&error];
    
    return fetchedObjects;
}

- (BOOL)getStates
{
    return self.xmppStream.isAuthenticated;
}

- (BOOL)getAuthenticating
{
    return self.xmppStream.isAuthenticating;
}

//保存修改
+ (void)saveThreshold{
    XMPPMessageArchivingCoreDataStorage *messageStorage = [XMPPManager shardManager].messageStorage;
    [messageStorage.mainThreadManagedObjectContext save:nil];
}



@end
