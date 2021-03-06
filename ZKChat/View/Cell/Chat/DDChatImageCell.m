//
//  DDChatImageCell.m
//  ZKChat
//
//  Created by 张阔 on 2017/4/5.
//  Copyright © 2017年 张阔. All rights reserved.
//

#import "DDChatImageCell.h"
#import "ZKChattingMainViewController.h"
#import "UIImageView+WebCache.h"
#import "NSDictionary+JSON.h"
#import "ZKUtil.h"
#import <Masonry.h>


@implementation DDChatImageCell
- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        // Initialization code
        self.msgImgView =[[UIImageView alloc] init];
        self.msgImgView.userInteractionEnabled=NO;
        [self.msgImgView setClipsToBounds:YES];
        [self.msgImgView.layer setCornerRadius:5];
        [self.msgImgView setContentMode:UIViewContentModeScaleAspectFill];
        [self.contentView addSubview:self.msgImgView];
        [self.bubbleImageView setClipsToBounds:YES];
        self.photos = [NSMutableArray new];
    }
    return self;
}
-(void)showPreview:(NSMutableArray *)photos index:(NSInteger)index
{
    [self.photos removeAllObjects];
    
    [photos enumerateObjectsUsingBlock:^(NSURL *obj, NSUInteger idx, BOOL *stop) {
        [self.photos addObject:[MWPhoto photoWithURL:obj]];
    }];
    
    MWPhotoBrowser *browser = [[MWPhotoBrowser alloc] initWithDelegate:self];
    browser.displayActionButton = NO;
    browser.displayNavArrows = NO;
    browser.zoomPhotosToFill = NO;
    [browser setCurrentPhotoIndex:index];
    [[ZKChattingMainViewController shareInstance] pushViewController:browser animated:YES];
    [browser.navigationController.navigationBar setHidden:YES];
}

- (void)setContent:(ZKMessageEntity*)content
{
    // 获取气泡设置
    [super setContent:content];
    //设置气泡位置
    UIImage* bubbleImage = nil;
    switch (self.location)
    {
        case DDBubbleLeft:
        {
            bubbleImage = [UIImage imageNamed:self.leftConfig.picBgImage];
            bubbleImage = [bubbleImage stretchableImageWithLeftCapWidth:self.leftConfig.imgStretchy.left topCapHeight:self.leftConfig.imgStretchy.top];
        }
            break;
        case DDBubbleRight:
        {
            bubbleImage = [UIImage imageNamed:self.rightConfig.picBgImage];
            bubbleImage = [bubbleImage stretchableImageWithLeftCapWidth:self.rightConfig.imgStretchy.left topCapHeight:self.rightConfig.imgStretchy.top];
        }
        default:
            break;
    }
    [self.bubbleImageView setImage:bubbleImage];
    if(content.msgContentType == DDMessageTypeImage)
    {
        NSDictionary* messageContent = [NSDictionary initWithJsonString:content.msgContent];
        if (!messageContent)
        {
            NSString* urlString = content.msgContent;
            urlString = [urlString stringByReplacingOccurrencesOfString:DD_MESSAGE_IMAGE_PREFIX withString:@""];
            urlString = [urlString stringByReplacingOccurrencesOfString:DD_MESSAGE_IMAGE_SUFFIX withString:@""];
            NSURL* url = [NSURL URLWithString:urlString];
            [self showSending];
            [self.msgImgView sd_setImageWithURL:url completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, NSURL *imageURL) {
                [self showSendSuccess];
            }];
            
            return;
        }
        if (messageContent[DD_IMAGE_LOCAL_KEY])
        {
            //加载本地图片
            NSString* localPath = messageContent[DD_IMAGE_LOCAL_KEY];
            NSData* data = [[ZKPhotosCache sharedPhotoCache] photoFromDiskCacheForKey:localPath];
            UIImage *image = [[UIImage alloc] initWithData:data];
            [self.msgImgView setImage:image];
        }
        else{
            //加载服务器上的图片
            NSString* url = messageContent[DD_IMAGE_URL_KEY];
            __weak DDChatImageCell* weakSelf = self;
            
            [self showSending];
            [self.msgImgView sd_setImageWithURL:[NSURL URLWithString:url] completed:^(UIImage *image, NSError *error, SDImageCacheType cacheType, NSURL *imageURL) {
                [weakSelf showSendSuccess];
                if (error) {
                    
                }
            }];
        }
        
    }
    
    
}
#pragma mark -MWPhotoBrowser
- (NSUInteger)numberOfPhotosInPhotoBrowser:(MWPhotoBrowser *)photoBrowser {
    return self.photos.count;
}

- (id <MWPhoto>)photoBrowser:(MWPhotoBrowser *)photoBrowser photoAtIndex:(NSUInteger)index {
    if (index < self.photos.count) {
        return [self.photos objectAtIndex:index];
    }
    return nil;
}
#pragma mark DDChatCellProtocol Protocol
- (CGSize)sizeForContent:(ZKMessageEntity*)content
{
    float height = 150;
    float width = 100;
    NSString* urlString = content.msgContent;
    urlString = [urlString stringByReplacingOccurrencesOfString:DD_MESSAGE_IMAGE_PREFIX withString:@""];
    urlString = [urlString stringByReplacingOccurrencesOfString:DD_MESSAGE_IMAGE_SUFFIX withString:@""];
    NSURL* url = [NSURL URLWithString:urlString];
    SDWebImageManager *manager = [SDWebImageManager sharedManager];
    if( [manager cachedImageExistsForURL:url]){
        NSString *key = [manager cacheKeyForURL:url];
        UIImage *curImg = [[SDImageCache sharedImageCache] imageFromDiskCacheForKey:key];
        height = curImg.size.height>40?curImg.size.height:40;
        width = curImg.size.width>40?curImg.size.width:40;
        return [ZKUtil sizeTrans:CGSizeMake(width, height)];
    }
    return CGSizeMake(width, height);
}

- (float)contentUpGapWithBubble
{
    return 1;
}

- (float)contentDownGapWithBubble
{
    return 1;
}

- (float)contentLeftGapWithBubble
{
    switch (self.location)
    {
        case DDBubbleRight:
            return 1;
        case DDBubbleLeft:
            return 6.5;
    }
    return 0;
}

- (float)contentRightGapWithBubble
{
    switch (self.location)
    {
        case DDBubbleRight:
            return 6.5;
            break;
        case DDBubbleLeft:
            return 1;
            break;
    }
    return 0;
}

- (void)layoutContentView:(ZKMessageEntity*)content
{
    CGSize size = [self sizeForContent:content];
    [self.msgImgView mas_remakeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(self.bubbleImageView.mas_left).offset([self contentLeftGapWithBubble]+1);
        make.top.equalTo(self.bubbleImageView.mas_top).offset([self contentUpGapWithBubble]+1);
        make.size.mas_equalTo(CGSizeMake(size.width-2, size.height-2));
    }];
}

- (float)cellHeightForMessage:(ZKMessageEntity*)message
{
    return 27 + dd_bubbleUpDown;
}
- (void)dealloc
{
    self.photos = nil;
}

#pragma mark -
#pragma mark DDMenuImageView Delegate
- (void)clickTheSendAgain:(MenuImageView*)imageView
{
    //子类去继承
    if (self.sendAgain)
    {
        self.sendAgain();
    }
}
- (void)sendImageAgain:(ZKMessageEntity*)message
{
    //子类去继承
    [self showSending];
    NSDictionary* dic = [NSDictionary initWithJsonString:message.msgContent];
    NSString* locaPath = dic[DD_IMAGE_LOCAL_KEY];
    __block UIImage* image = [[SDImageCache sharedImageCache] imageFromDiskCacheForKey:locaPath];
    if (!image)
    {
        NSData* data = [[ZKPhotosCache sharedPhotoCache] photoFromDiskCacheForKey:locaPath];
        image = [[UIImage alloc] initWithData:data];
        if (!image) {
            [self showSendFailure];
            return ;
        }
    }
//    [[DDSendPhotoMessageAPI sharedPhotoCache] uploadImage:locaPath success:^(NSString *imageURL) {
//        NSDictionary* tempMessageContent = [NSDictionary initWithJsonString:message.msgContent];
//        NSMutableDictionary* mutalMessageContent = [[NSMutableDictionary alloc] initWithDictionary:tempMessageContent];
//        [mutalMessageContent setValue:imageURL forKey:DD_IMAGE_URL_KEY];
//        NSString* messageContent = [mutalMessageContent jsonString];
//        message.msgContent = messageContent;
//        image = nil;
//        [[DDMessageSendManager instance] sendMessage:message isGroup:[message isGroupMessage] Session:[[SessionModule instance] getSessionById:message.sessionId] completion:^(MTTMessageEntity* theMessage,NSError *error) {
//            if (error)
//            {
//                DDLog(@"发送消息失败");
//                message.state = DDMessageSendFailure;
//                //刷新DB
////                [[MTTDatabaseUtil instance] updateMessageForMessage:message completion:^(BOOL result) {
////                    if (result)
////                    {
////                        [self showSendFailure];
////                    }
////                }];
//            }
//            else
//            {
//                //刷新DB
//                message.state = DDmessageSendSuccess;
//                //刷新DB
////                [[MTTDatabaseUtil instance] updateMessageForMessage:message completion:^(BOOL result) {
////                    if (result)
////                    {
////                        [self showSendSuccess];
////                    }
////                }];
//            }
//        } Error:^(NSError *error) {
////            [[MTTDatabaseUtil instance] updateMessageForMessage:message completion:^(BOOL result) {
////                if (result)
////                {
////                    [self showSendFailure];
////                }
////            }];
//        }];
//        
//    } failure:^(id error) {
//        message.state = DDMessageSendFailure;
//        //刷新DB
////        [[MTTDatabaseUtil instance] updateMessageForMessage:message completion:^(BOOL result) {
////            if (result)
////            {
////                [self showSendFailure];
////            }
////        }];
//    }];
    
}
- (void)clickThePreview:(MenuImageView *)imageView
{
    //子类去继承
    if (self.preview)
    {
        self.preview();
    }
}

@end
