//
//  CustomSPTCoreAudioController.h
//  SpotifyVisualizer
//
//  Created by James Kong on 5/4/15.
//  Copyright (c) 2015 James Kong. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AudioUnit/AudioUnit.h>
#import <Spotify/Spotify.h>
@class CustomSPTCoreAudioController;
@protocol CustomSPTCoreAudioControllerDelegate <NSObject>

@optional
-(void)             controller:(CustomSPTCoreAudioController *)controller
     shouldFillAudioBufferList:(AudioBufferList*)audioBufferList
            withNumberOfFrames:(UInt32)frames;
@end

@interface CustomSPTCoreAudioController : SPTCoreAudioController
-(instancetype) initWithDelegate:(id<CustomSPTCoreAudioControllerDelegate>)outputDelegate;
@property (nonatomic, weak) id<CustomSPTCoreAudioControllerDelegate>outputDelegate;
@end
