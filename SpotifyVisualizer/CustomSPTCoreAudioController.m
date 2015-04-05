//
//  CustomSPTCoreAudioController.m
//  SpotifyVisualizer
//
//  Created by James Kong on 5/4/15.
//  Copyright (c) 2015 James Kong. All rights reserved.
//

#import "CustomSPTCoreAudioController.h"


static OSStatus renderCallback(void *inRefCon,
                               AudioUnitRenderActionFlags  *ioActionFlags,
                               const AudioTimeStamp        *inTimeStamp,
                               UInt32                      inBusNumber,
                               UInt32                      inNumberFrames,
                               AudioBufferList             *ioData)
{
    __unsafe_unretained CustomSPTCoreAudioController *contoller = (__bridge CustomSPTCoreAudioController *)inRefCon;
    OSStatus err = noErr;
    
    if( [contoller.outputDelegate respondsToSelector:@selector(controller:shouldFillAudioBufferList:withNumberOfFrames:)] )
    {
        [contoller.outputDelegate controller:contoller
                   shouldFillAudioBufferList:ioData
                          withNumberOfFrames:inNumberFrames];
    }
    
    return err;
    
}

@interface CustomSPTCoreAudioController()
{
    AudioUnit ioUnit;
}
@end
@implementation CustomSPTCoreAudioController
-(instancetype) initWithDelegate:(id<CustomSPTCoreAudioControllerDelegate>)outputDelegate
{
    
    self = [super init];
    self.outputDelegate = outputDelegate;
    return self;
    
}
-(BOOL)connectOutputBus:(UInt32)sourceOutputBusNumber ofNode:(AUNode)sourceNode toInputBus:(UInt32)destinationInputBusNumber ofNode:(AUNode)destinationNode inGraph:(AUGraph)graph error:(NSError **)error
{
    // Get the Audio Unit from the node so we can set bands directly later
    OSStatus status = AUGraphNodeInfo(graph, destinationNode, NULL, &ioUnit);
    if (status != noErr) {
        NSLog(@"[%@ %@]: %@", NSStringFromClass([self class]), NSStringFromSelector(_cmd), @"Couldn't get EQ unit");
        return NO;
    }
    
    AudioUnitAddRenderNotify(ioUnit, &renderCallback, (__bridge void*)self);
    
    return [super connectOutputBus:sourceOutputBusNumber ofNode:sourceNode toInputBus:destinationInputBusNumber ofNode:destinationNode inGraph:graph error:error];
}
-(NSInteger)attemptToDeliverAudioFrames:(const void *)audioFrames ofCount:(NSInteger)frameCount streamDescription:(AudioStreamBasicDescription)audioDescription
{
    //    DDLogDebug(@"%s will do implementation",__PRETTY_FUNCTION__);
    return [super attemptToDeliverAudioFrames:audioFrames ofCount:frameCount streamDescription:audioDescription];
}

@end
