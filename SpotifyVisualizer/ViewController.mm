/*
 Copyright 2015 Spotify AB
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

#import "Config.h"
#import "ViewController.h"
#import <Spotify/SPTDiskCache.h>
#import "CustomSPTCoreAudioController.h"
#import "EZAudio.h"
#import "BufferManager.h"
#import "GKBarGraph.h"
#ifndef CLAMP
#define CLAMP(min,x,max) (x < min ? min : (x > max ? max : x))
#endif

typedef enum aurioTouchDisplayMode {
    aurioTouchDisplayModeOscilloscopeWaveform,
    aurioTouchDisplayModeOscilloscopeFFT,
    aurioTouchDisplayModeSpectrum
} aurioTouchDisplayMode;

@interface ViewController () <SPTAudioStreamingDelegate,CustomSPTCoreAudioControllerDelegate>
{
    BufferManager *_bufferManager;
    Float32 *outFFTData;
}
@property (weak, nonatomic) IBOutlet UILabel *titleLabel;
@property (weak, nonatomic) IBOutlet UILabel *albumLabel;
@property (weak, nonatomic) IBOutlet UILabel *artistLabel;
@property (weak, nonatomic) IBOutlet UIImageView *coverView;
@property (weak, nonatomic) IBOutlet UIImageView *coverView2;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *spinner;
@property (weak, nonatomic) IBOutlet EZAudioPlotGL *audioPlot;

@property (nonatomic, strong) SPTAudioStreamingController *player;
@property (weak, nonatomic) IBOutlet GKBarGraph *graphView;

@end

@implementation ViewController
@synthesize audioPlot;
-(void)viewDidLoad {
    [super viewDidLoad];
    self.titleLabel.text = @"Nothing Playing";
    self.albumLabel.text = @"";
    self.artistLabel.text = @"";
    
    self.audioPlot.backgroundColor = [UIColor colorWithRed: 0.569 green: 0.82 blue: 0.478 alpha: 0];
    // Waveform color
    self.audioPlot.color           = [UIColor colorWithRed:1.0 green:1.0 blue:1.0 alpha:1.0];
    // Plot type
    self.audioPlot.plotType        = EZPlotTypeBuffer;
    UInt32 maxFramesPerSlice = 4096;
    _bufferManager = new BufferManager(maxFramesPerSlice);
    _bufferManager->SetDisplayMode(aurioTouchDisplayModeOscilloscopeFFT);
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

#pragma mark - Actions

-(IBAction)rewind:(id)sender {
    [self.player skipPrevious:nil];
}

-(IBAction)playPause:(id)sender {
    [self.player setIsPlaying:!self.player.isPlaying callback:nil];
}

-(IBAction)fastForward:(id)sender {
    [self.player skipNext:nil];
}

- (IBAction)logoutClicked:(id)sender {
    SPTAuth *auth = [SPTAuth defaultInstance];
    if (self.player) {
        [self.player logout:^(NSError *error) {
            auth.session = nil;
            [self.navigationController popViewControllerAnimated:YES];
        }];
    } else {
        [self.navigationController popViewControllerAnimated:YES];
    }
}

#pragma mark - Logic


- (UIImage *)applyBlurOnImage: (UIImage *)imageToBlur
                   withRadius: (CGFloat)blurRadius {
    
    CIImage *originalImage = [CIImage imageWithCGImage: imageToBlur.CGImage];
    CIFilter *filter = [CIFilter filterWithName: @"CIGaussianBlur"
                                  keysAndValues: kCIInputImageKey, originalImage,
                        @"inputRadius", @(blurRadius), nil];
    
    CIImage *outputImage = filter.outputImage;
    CIContext *context = [CIContext contextWithOptions:nil];
    
    CGImageRef outImage = [context createCGImage: outputImage
                                        fromRect: [outputImage extent]];
    
    UIImage *ret = [UIImage imageWithCGImage: outImage];
    
    CGImageRelease(outImage);
    
    return ret;
}

-(void)updateUI {
    SPTAuth *auth = [SPTAuth defaultInstance];
    
    if (self.player.currentTrackMetadata == nil) {
        self.coverView.image = nil;
        self.coverView2.image = nil;
        return;
    }
    
    [self.spinner startAnimating];
    
    [SPTTrack trackWithURI:[NSURL URLWithString:[self.player.currentTrackMetadata valueForKey:SPTAudioStreamingMetadataTrackURI]]
                   session:auth.session
                  callback:^(NSError *error, SPTTrack *track) {
                      
                      self.titleLabel.text = track.name;
                      self.albumLabel.text = track.album.name;
                      
                      SPTPartialArtist *artist = [track.artists objectAtIndex:0];
                      self.artistLabel.text = artist.name;
                      
                      NSURL *imageURL = track.album.largestCover.imageURL;
                      if (imageURL == nil) {
                          NSLog(@"Album %@ doesn't have any images!", track.album);
                          self.coverView.image = nil;
                          self.coverView2.image = nil;
                          return;
                      }
                      
                      // Pop over to a background queue to load the image over the network.
                      dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                          NSError *error = nil;
                          UIImage *image = nil;
                          NSData *imageData = [NSData dataWithContentsOfURL:imageURL options:0 error:&error];
                          
                          if (imageData != nil) {
                              image = [UIImage imageWithData:imageData];
                          }
                          
                          
                          // …and back to the main queue to display the image.
                          dispatch_async(dispatch_get_main_queue(), ^{
                              [self.spinner stopAnimating];
                              self.coverView.image = image;
                              if (image == nil) {
                                  NSLog(@"Couldn't load cover image with error: %@", error);
                                  return;
                              }
                          });
                          
                          // Also generate a blurry version for the background
                          UIImage *blurred = [self applyBlurOnImage:image withRadius:10.0f];
                          dispatch_async(dispatch_get_main_queue(), ^{
                              self.coverView2.image = blurred;
                          });
                      });
                      
                  }];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self handleNewSession];
}

-(void)handleNewSession {
    SPTAuth *auth = [SPTAuth defaultInstance];
    
    if (self.player == nil) {
        self.player = [[SPTAudioStreamingController alloc] initWithClientId:auth.clientID audioController:[[CustomSPTCoreAudioController alloc] initWithDelegate:self]];
        self.player.playbackDelegate = self;
        self.player.diskCache = [[SPTDiskCache alloc] initWithCapacity:1024 * 1024 * 64];
    }
    
    [self.player loginWithSession:auth.session callback:^(NSError *error) {
        
        if (error != nil) {
            NSLog(@"*** Enabling playback got error: %@", error);
            return;
        }
        
        [self updateUI];
        
        [SPTRequest requestItemAtURI:[NSURL URLWithString:@"spotify:user:cariboutheband:playlist:4Dg0J0ICj9kKTGDyFu0Cv4"]
                         withSession:auth.session
                            callback:^(NSError *error, id object) {
                                
                                if (error != nil) {
                                    NSLog(@"*** Album lookup got error %@", error);
                                    return;
                                }
                                
                                [self.player playTrackProvider:(id <SPTTrackProvider>)object callback:nil];
                                
                            }];
    }];
}

#pragma mark - Track Player Delegates

- (void)audioStreaming:(SPTAudioStreamingController *)audioStreaming didReceiveMessage:(NSString *)message {
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Message from Spotify"
                                                        message:message
                                                       delegate:nil
                                              cancelButtonTitle:@"OK"
                                              otherButtonTitles:nil];
    [alertView show];
}

- (void)audioStreaming:(SPTAudioStreamingController *)audioStreaming didFailToPlayTrack:(NSURL *)trackUri {
    NSLog(@"failed to play track: %@", trackUri);
}

- (void) audioStreaming:(SPTAudioStreamingController *)audioStreaming didChangeToTrack:(NSDictionary *)trackMetadata {
    NSLog(@"track changed = %@", [trackMetadata valueForKey:SPTAudioStreamingMetadataTrackURI]);
    [self updateUI];
}

- (void)audioStreaming:(SPTAudioStreamingController *)audioStreaming didChangePlaybackStatus:(BOOL)isPlaying {
    NSLog(@"is playing = %d", isPlaying);
}

#pragma mark - CustomSPTCoreAudioControllerDelegate
-(void)controller:(CustomSPTCoreAudioController *)controller shouldFillAudioBufferList:(AudioBufferList*)audioBufferList withNumberOfFrames:(UInt32)frames
{
    float *dataPoints =  (Float32 *)audioBufferList->mBuffers[0].mData;
    if(_bufferManager != NULL && dataPoints!=NULL)
    {
        _bufferManager->CopyAudioDataToFFTInputBuffer(dataPoints, frames);
        //    UInt32 bufferSize = audioBufferList->mBuffers[0].mDataByteSize/sizeof(float);
        if(_bufferManager->NeedsNewFFTData())
        {
            if(_bufferManager->HasNewFFTData())
            {
                UInt32 bufferLength = _bufferManager->GetFFTOutputBufferLength();
                if(!outFFTData)
                {
                    outFFTData = (Float32*) calloc(_bufferManager->GetFFTOutputBufferLength(), sizeof(Float32));
                }
                _bufferManager->GetFFTOutput(outFFTData);
                // Calculate sum of squares
                int y, maxY;
                maxY = _bufferManager->GetCurrentDrawBufferLength();
                int fftLength = _bufferManager->GetFFTOutputBufferLength();
                Float32** drawBuffers = _bufferManager->GetDrawBuffers();
                for (y=0; y<maxY; y++)
                {
                    CGFloat yFract = (CGFloat)y / (CGFloat)(maxY - 1);
                    CGFloat fftIdx = yFract * ((CGFloat)fftLength - 1);
                    
                    double fftIdx_i, fftIdx_f;
                    fftIdx_f = modf(fftIdx, &fftIdx_i);
                    
                    CGFloat fft_l_fl, fft_r_fl;
                    CGFloat interpVal;
                    
                    int lowerIndex = (int) fftIdx_i;
                    int upperIndex = (int) fftIdx_i + 1;
                    upperIndex = (upperIndex == fftLength) ? fftLength - 1 : upperIndex;
                    
                    fft_l_fl = (CGFloat)(outFFTData[lowerIndex] + 80) / 64.;
                    fft_r_fl = (CGFloat)(outFFTData[upperIndex] + 80) / 64.;
                    interpVal = fft_l_fl * (1. - fftIdx_f) + fft_r_fl * fftIdx_f;
                    
                    drawBuffers[0][y] = CLAMP(0., interpVal, 1.);
                }
                
                dispatch_async(dispatch_get_main_queue(),^{
                    // All the audio plot needs is the buffer data (float*) and the size. Internally the audio plot will handle all the drawing related code, history management, and freeing its own resources. Hence, one badass line of code gets you a pretty plot :)
                    if(outFFTData!=NULL)
                    {
                        [self.audioPlot updateBuffer:drawBuffers[0] withBufferSize:frames];
                    }
                    else{
                        [self.audioPlot updateBuffer:(float*)audioBufferList->mBuffers[0].mData withBufferSize:frames];
                    }
                    
                    
                });
            }
        }
    }
    
}
@end
