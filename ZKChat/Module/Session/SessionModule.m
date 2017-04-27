//
//  SessionModule.m
//  ZKChat
//
//  Created by 张阔 on 2017/4/27.
//  Copyright © 2017年 张阔. All rights reserved.
//

#import "SessionModule.h"
#import "MsgReadACKAPI.h"
#import "NSDictionary+Safe.h"
#import "DDGroupModule.h"
#import "ZKDatabaseUtil.h"
#import "ZKChattingMainViewController.h"
#import "ZKUtil.h"

@interface SessionModule()
@property(strong)NSMutableDictionary *sessions;
@end

@implementation SessionModule
+ (instancetype)instance
{
    static SessionModule* module;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        module = [[SessionModule alloc] init];
        
    });
    return module;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.sessions = [NSMutableDictionary new];
        //
        ZKSessionEntity *session=[[ZKSessionEntity alloc]initWithSessionID:@"zk" type:SessionTypeSessionTypeSingle];
        [session setSessionName:@"zhangkuo"];
        [self addToSessionModel:session];
        
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(sentMessageSuccessfull:) name:@"SentMessageSuccessfull" object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(getMessageReadACK:) name:@"MessageReadACK" object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(n_receiveMessageNotification:)
                                                     name:DDNotificationReceiveMessage
                                                   object:nil];
        MsgReadNotify *msgReadNotify = [[MsgReadNotify alloc] init];
        [msgReadNotify registerAPIInAPIScheduleReceiveData:^(NSDictionary *object, NSError *error) {
            NSString *fromId= [object objectForKey:@"from_id"];
            NSInteger msgID = [[object objectForKey:@"msgId"] integerValue];
            SessionType type = [[object objectForKey:@"type"] intValue];
            [self cleanMessageFromNotifi:msgID SessionID:fromId Session:type];
        }];
    }
    return self;
}
-(ZKSessionEntity *)getSessionById:(NSString *)sessionID
{
    return [self.sessions safeObjectForKey:sessionID];
}
-(void)removeSessionById:(NSString *)sessionID
{
    [self.sessions removeObjectForKey:sessionID];
}
-(void)addToSessionModel:(ZKSessionEntity *)session
{
    [self.sessions safeSetObject:session forKey:session.sessionID];
}
-(NSUInteger)getAllUnreadMessageCount
{
    NSArray *allSession = [self getAllSessions];
    __block NSUInteger count = 0;
    [allSession enumerateObjectsUsingBlock:^(ZKSessionEntity *obj, NSUInteger idx, BOOL *stop) {
        NSInteger unReadMsgCount = obj.unReadMsgCount;
        if(obj.isGroup){
            ZKGroupEntity *group = [[DDGroupModule instance] getGroupByGId:obj.sessionID];
            if (group) {
                if(group.isShield){
                    if(obj.unReadMsgCount){
                        unReadMsgCount = 0;
                    }
                }
            }
        }
        count += unReadMsgCount;
    }];
    return count;
    //    return [[[self getAllSessions] valueForKeyPath:@"@sum.unReadMsgCount"] integerValue];
}
-(void)addSessionsToSessionModel:(NSArray *)sessionArray
{
    [sessionArray enumerateObjectsUsingBlock:^(ZKSessionEntity *session, NSUInteger idx, BOOL *stop) {
        [self.sessions safeSetObject:session forKey:session.sessionID];
    }];
}
-(void)getHadUnreadMessageSession:(void(^)(NSUInteger count))block
{
    GetUnreadMessagesAPI *getUnreadMessage = [GetUnreadMessagesAPI new];
    [getUnreadMessage requestWithObject:TheRuntime.user.objID Completion:^(NSDictionary *dic, NSError *error) {
        NSInteger m_total_cnt =[dic[@"m_total_cnt"] integerValue];
        NSArray *localsessions = dic[@"sessions"];
        [localsessions enumerateObjectsUsingBlock:^(ZKSessionEntity *obj, NSUInteger idx, BOOL *stop){
            
            if ([self getSessionById:obj.sessionID]) {
                
                ZKSessionEntity *session = [self getSessionById:obj.sessionID];
                NSInteger lostMsgCount =obj.lastMsgID-session.lastMsgID;
                obj.lastMsg = session.lastMsg;
                if ([[ChattingMainViewController shareInstance].module.MTTSessionEntity.sessionID isEqualToString:obj.sessionID]) {
                    [[NSNotificationCenter defaultCenter] postNotificationName:@"ChattingSessionUpdate" object:@{@"session":obj,@"count":@(lostMsgCount)}];
                }
                session=obj;
                [self addToSessionModel:obj];
            }
            if (self.delegate && [self.delegate respondsToSelector:@selector(sessionUpdate:Action:)]) {
                [self.delegate sessionUpdate:obj Action:ADD];
            }
            
            
        }];
        
        //[self addSessionsToSessionModel:sessions];
        block(m_total_cnt);
        //通知外层sessionmodel发生更新
    }];
}

-(NSUInteger )getMaxTime
{
    NSArray *array =[self getAllSessions];
    NSUInteger maxTime = [[array valueForKeyPath:@"@max.timeInterval"] integerValue];
    if (maxTime) {
        return maxTime;
    }
    return 0;
}
-(void)getRecentSession:(void(^)(NSUInteger count))block
{
    GetRecentSession *getRecentSession = [[GetRecentSession alloc] init];
    NSInteger localMaxTime = [self getMaxTime];
    [getRecentSession requestWithObject:@[@(localMaxTime)] Completion:^(NSArray *response, NSError *error) {
        
        NSMutableArray *array = [NSMutableArray arrayWithArray:response];
        
        [self addSessionsToSessionModel:array];
        
        [self getHadUnreadMessageSession:^(NSUInteger count) {}];
        
        [[ZKDatabaseUtil instance] updateRecentSessions:response completion:^(NSError *error) {}];
        
        block(0);
        
    }];
}

-(NSArray *)getAllSessions
{
    NSArray *sessions = [self.sessions allValues];
    [sessions enumerateObjectsUsingBlock:^(ZKSessionEntity *obj, NSUInteger idx, BOOL *stop) {
        if([ZKUtil checkFixedTop:obj.sessionID]){
            obj.isFixedTop = YES;
        }
    }];
    return [self.sessions allValues];
}
-(void)removeSessionByServer:(ZKSessionEntity *)session
{
    [self.sessions removeObjectForKey:session.sessionID];
    [[ZKDatabaseUtil instance] removeSession:session.sessionID];
    RemoveSessionAPI *removeSession = [RemoveSessionAPI new];
    SessionType sessionType = session.sessionType;
    [removeSession requestWithObject:@[session.sessionID,@(sessionType)] Completion:^(id response, NSError *error) {
        
    }];
}

-(void)clearSession{
    [self.sessions removeAllObjects];
}

-(void)getMessageReadACK:(NSNotification *)notification
{
    ZKMessageEntity* message = [notification object];
    if ([[self.sessions allKeys] containsObject:message.sessionId]) {
        ZKSessionEntity *session = [self.sessions objectForKey:message.sessionId];
        session.unReadMsgCount=session.unReadMsgCount-1;
        
    }
}
- (void)n_receiveMessageNotification:(NSNotification*)notification
{
    ZKMessageEntity* message = [notification object];
    
    SessionType sessionType;
    ZKSessionEntity *session;
    if ([message isGroupMessage]) {
        sessionType = SessionTypeSessionTypeGroup;
    } else{
        sessionType = SessionTypeSessionTypeSingle;
    }
    
    if ([[self.sessions allKeys] containsObject:message.sessionId]) {
        session = [self.sessions objectForKey:message.sessionId];
        session.lastMsg=message.msgContent;
        session.lastMsgID = message.msgID;
        session.timeInterval = message.msgTime;
        if (![message.sessionId isEqualToString:[ZKChattingMainViewController shareInstance].module.ZKSessionEntity.sessionID]) {
            if (![message.senderId isEqualToString:TheRuntime.user.objID]) {
                session.unReadMsgCount=session.unReadMsgCount+1;
            }
        }
        
    }else{
        session = [[ZKSessionEntity alloc] initWithSessionID:message.sessionId type:sessionType];
        session.lastMsg=message.msgContent;
        session.lastMsgID = message.msgID;
        session.timeInterval = message.msgTime;
        if (![message.sessionId isEqualToString:[ChattingMainViewController shareInstance].module.ZKSessionEntity.sessionID]) {
            if (![message.senderId isEqualToString:TheRuntime.user.objID]) {
                session.unReadMsgCount=session.unReadMsgCount+1;
            }
            
        }
        [self addSessionsToSessionModel:@[session]];
    }
    [self updateToDatabase:session];
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(sessionUpdate:Action:)]) {
        [self.delegate sessionUpdate:session Action:ADD];
    }
    
}
-(void)updateToDatabase:(ZKSessionEntity *)session{
    [[ZKDatabaseUtil instance] updateRecentSession:session completion:^(NSError *error) {
        
    }];
}
-(void)sentMessageSuccessfull:(NSNotification*)notification
{
    ZKSessionEntity* session = [notification object];
    [self addSessionsToSessionModel:@[session]];
    if (self.delegate && [self.delegate respondsToSelector:@selector(sessionUpdate:Action:)]) {
        [self.delegate sessionUpdate:session Action:ADD];
    }
    [self updateToDatabase:session];
}
-(void)loadLocalSession:(void(^)(bool isok))block
{
    [[ZKDatabaseUtil instance] loadSessionsCompletion:^(NSArray *session, NSError *error) {
        
        [self addSessionsToSessionModel:session];
        
        block(YES);
        
    }];
    
}
-(void)cleanMessageFromNotifi:(NSUInteger)messageID  SessionID:(NSString *)sessionid Session:(SessionType)type
{
    if(![sessionid isEqualToString:TheRuntime.user.objID]){
        ZKSessionEntity *session = [self getSessionById:sessionid];
        if (session) {
            NSInteger readCount =messageID-session.lastMsgID;
            if (readCount == 0) {
                session.unReadMsgCount =0;
                if (self.delegate && [self.delegate respondsToSelector:@selector(sessionUpdate:Action:)]) {
                    [self.delegate sessionUpdate:session Action:ADD];
                }
                [self updateToDatabase:session];
                
            }else if(readCount > 0){
                session.unReadMsgCount =readCount;
                if (self.delegate && [self.delegate respondsToSelector:@selector(sessionUpdate:Action:)]) {
                    [self.delegate sessionUpdate:session Action:ADD];
                }
                [self updateToDatabase:session];
            }
            MsgReadACKAPI* readACK = [[MsgReadACKAPI alloc] init];
            [readACK requestWithObject:@[sessionid,@(messageID),@(type)] Completion:nil];
        }
        
    }
}


@end
