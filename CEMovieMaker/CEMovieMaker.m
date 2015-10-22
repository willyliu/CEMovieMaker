//
//  CEMovieMaker.m
//  CEMovieMaker
//
//  Created by Cameron Ehrlich on 9/17/14.
//  Copyright (c) 2014 Cameron Ehrlich. All rights reserved.
//

#import "CEMovieMaker.h"

@implementation CEMovieMaker

- (instancetype)initWithSettings:(NSDictionary *)videoSettings;
{
    self = [self init];
    if (self) {
        NSError *error;
        
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentsDirectory = [paths firstObject];
        NSString *tempPath = [documentsDirectory stringByAppendingFormat:@"/export.mov"];
        
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:tempPath]) {
            [[NSFileManager defaultManager] removeItemAtPath:tempPath error:&error];
            if (error) {
                NSLog(@"Error: %@", error.debugDescription);
            }
        }
        
        _videoFromImagesFileURL = [NSURL fileURLWithPath:tempPath];
        _assetWriter = [[AVAssetWriter alloc] initWithURL:self.videoFromImagesFileURL
                                                 fileType:AVFileTypeQuickTimeMovie error:&error];
        if (error) {
            NSLog(@"Error: %@", error.debugDescription);
        }
        NSParameterAssert(self.assetWriter);
        
        _videoSettings = videoSettings;
        _writerInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo
                                                          outputSettings:videoSettings];
        NSParameterAssert(self.writerInput);
        NSParameterAssert([self.assetWriter canAddInput:self.writerInput]);
        
        [self.assetWriter addInput:self.writerInput];
        
        NSDictionary *bufferAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                          [NSNumber numberWithInt:kCVPixelFormatType_32ARGB], kCVPixelBufferPixelFormatTypeKey, nil];
        
        _bufferAdapter = [[AVAssetWriterInputPixelBufferAdaptor alloc] initWithAssetWriterInput:self.writerInput sourcePixelBufferAttributes:bufferAttributes];
        _frameTime = CMTimeMake(1, 10);
    }
    return self;
}

- (void)createMovieFromPrefixMovieFileURL:(NSURL *)prefixMovieFileURL images:(NSArray *)images backgroundAudioFileURL:(NSURL *)backgroundAudioFileURL withCompletion:(CEMovieMakerCompletion)completion
{
    self.completionBlock = completion;
    
    [self.assetWriter startWriting];
    [self.assetWriter startSessionAtSourceTime:kCMTimeZero];
    
    dispatch_queue_t mediaInputQueue = dispatch_queue_create("mediaInputQueue", NULL);
    
    __block NSInteger i = 0;
    
    NSInteger frameNumber = [images count];
    
    [self.writerInput requestMediaDataWhenReadyOnQueue:mediaInputQueue usingBlock:^{
        while (YES){
            if (i >= frameNumber) {
                break;
            }
            if ([self.writerInput isReadyForMoreMediaData]) {
                
                CVPixelBufferRef sampleBuffer = [self newPixelBufferFromCGImage:[[images objectAtIndex:i] CGImage]];
                
                if (sampleBuffer) {
                    if (i == 0) {
                        [self.bufferAdapter appendPixelBuffer:sampleBuffer withPresentationTime:kCMTimeZero];
                    }else{
                        CMTime lastTime = CMTimeMake((i-1) * self.frameTime.timescale * 3, self.frameTime.timescale);
                        CMTime presentTime = CMTimeAdd(lastTime, self.frameTime);
                        [self.bufferAdapter appendPixelBuffer:sampleBuffer withPresentationTime:presentTime];
                    }
                    CFRelease(sampleBuffer);
                    i++;
                }
            }
        }
        
        [self.writerInput markAsFinished];
        [self.assetWriter finishWritingWithCompletionHandler:^{
			[self _compilePrefixVideoFileURL:prefixMovieFileURL videoFromImagesFileURL:self.videoFromImagesFileURL andAudioFileURL:backgroundAudioFileURL toMakeMovieWithCompletion:completion];
        }];
        
        CVPixelBufferPoolRelease(self.bufferAdapter.pixelBufferPool);
    }];
}

-(void)_compilePrefixVideoFileURL:(NSURL *)inPrefixVideoFileURL  videoFromImagesFileURL:(NSURL *)inVideoFromImagesFileURL andAudioFileURL:(NSURL *)inAudioFileURL toMakeMovieWithCompletion:(CEMovieMakerCompletion)completion;
{
	AVMutableComposition *mixComposition = [AVMutableComposition composition];
	
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	NSString *documentsDirectory = [paths firstObject];
	NSString *outputFilePath = [documentsDirectory stringByAppendingFormat:@"/result.mov"];
	NSURL *outputFileUrl = [NSURL fileURLWithPath:outputFilePath];
	
	if ([[NSFileManager defaultManager] fileExistsAtPath:outputFilePath])
		[[NSFileManager defaultManager] removeItemAtPath:outputFilePath error:nil];
	
	CMTime nextClipStartTime = kCMTimeZero;
	
	NSMutableArray *instructions = [NSMutableArray new];
	
	// insert prefix video and audio
	AVURLAsset *prefixVideoAsset = [[AVURLAsset alloc]initWithURL:inPrefixVideoFileURL options:nil];
	CMTimeRange prefixVideoTimeRange = CMTimeRangeMake(kCMTimeZero, prefixVideoAsset.duration);
	AVMutableCompositionTrack *compositionPrefixVideoTrack = [mixComposition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
	[compositionPrefixVideoTrack insertTimeRange:prefixVideoTimeRange ofTrack:[[prefixVideoAsset tracksWithMediaType:AVMediaTypeVideo] objectAtIndex:0] atTime:nextClipStartTime error:nil];
	
	AVMutableCompositionTrack *compositionPrefixAudioTrack = [mixComposition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
	[compositionPrefixAudioTrack insertTimeRange:prefixVideoTimeRange ofTrack:[[prefixVideoAsset tracksWithMediaType:AVMediaTypeAudio] objectAtIndex:0] atTime:nextClipStartTime error:nil];
	
	AVMutableVideoCompositionInstruction *prefixVideoCompositionInstruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
	prefixVideoCompositionInstruction.timeRange = CMTimeRangeMake(kCMTimeZero, prefixVideoTimeRange.duration);
	prefixVideoCompositionInstruction.layerInstructions = @[[AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:compositionPrefixVideoTrack]];
	[instructions addObject:prefixVideoCompositionInstruction];
	
	nextClipStartTime = CMTimeAdd(nextClipStartTime, prefixVideoTimeRange.duration);
	
	// insert video from images and background audio, they must be the same duration
	// Problem: the volume of each audio asset is not normalized
	AVURLAsset *videoAsset = [[AVURLAsset alloc]initWithURL:inVideoFromImagesFileURL options:nil];
	AVURLAsset *audioAsset = [[AVURLAsset alloc]initWithURL:inAudioFileURL options:nil];
	CMTime minDuration = CMTimeMinimum(videoAsset.duration, audioAsset.duration);
	CMTimeRange videoTimeRange = CMTimeRangeMake(kCMTimeZero, minDuration);
	AVMutableCompositionTrack *compositionVideoFromImagesTrack = [mixComposition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
	NSError *insertVideoFromImagesError = nil;
	[compositionVideoFromImagesTrack insertTimeRange:videoTimeRange ofTrack:[[videoAsset tracksWithMediaType:AVMediaTypeVideo] objectAtIndex:0] atTime:nextClipStartTime error:&insertVideoFromImagesError];
	
	CMTimeRange audioTimeRange = CMTimeRangeMake(kCMTimeZero, minDuration);
	AVMutableCompositionTrack *compositionBackgroundAudioTrack = [mixComposition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
	NSError *insertBackgroundMusicError = nil;
	[compositionBackgroundAudioTrack insertTimeRange:audioTimeRange ofTrack:[[audioAsset tracksWithMediaType:AVMediaTypeAudio] objectAtIndex:0] atTime:nextClipStartTime error:&insertBackgroundMusicError];

	AVMutableVideoCompositionInstruction *videoCompositionInstruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
	videoCompositionInstruction.timeRange = CMTimeRangeMake(nextClipStartTime, minDuration);
	videoCompositionInstruction.layerInstructions = @[[AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:compositionVideoFromImagesTrack]];
	[instructions addObject:videoCompositionInstruction];

	AVMutableVideoComposition *mutableVideoComposition = [AVMutableVideoComposition videoComposition];
	mutableVideoComposition.instructions = instructions;
	
	// Set the frame duration to an appropriate value (i.e. 30 frames per second for video).
	mutableVideoComposition.frameDuration = CMTimeMake(1, 30);
	// Set the render size as the prefix video's size
	mutableVideoComposition.renderSize = compositionPrefixVideoTrack.naturalSize;
	
	AVAssetExportSession *_assetExport = [[AVAssetExportSession alloc] initWithAsset:mixComposition presetName:AVAssetExportPresetHighestQuality];
	_assetExport.outputFileType = @"com.apple.quicktime-movie";
	_assetExport.outputURL = outputFileUrl;
	_assetExport.videoComposition = mutableVideoComposition;
	
	[_assetExport exportAsynchronouslyWithCompletionHandler:
	 ^(void ) {
		 dispatch_async(dispatch_get_main_queue(), ^{
			 self.completionBlock(outputFileUrl);
		 });
	 }
	 ];
}

- (CVPixelBufferRef)newPixelBufferFromCGImage:(CGImageRef)image
{
    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
                             [NSNumber numberWithBool:YES], kCVPixelBufferCGImageCompatibilityKey,
                             [NSNumber numberWithBool:YES], kCVPixelBufferCGBitmapContextCompatibilityKey,
                             nil];
    
    CVPixelBufferRef pxbuffer = NULL;
    
    CGFloat frameWidth = [[self.videoSettings objectForKey:AVVideoWidthKey] floatValue];
    CGFloat frameHeight = [[self.videoSettings objectForKey:AVVideoHeightKey] floatValue];
    
    
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault,
                                          frameWidth,
                                          frameHeight,
                                          kCVPixelFormatType_32ARGB,
                                          (__bridge CFDictionaryRef) options,
                                          &pxbuffer);
    
    NSParameterAssert(status == kCVReturnSuccess && pxbuffer != NULL);
    
    CVPixelBufferLockBaseAddress(pxbuffer, 0);
    void *pxdata = CVPixelBufferGetBaseAddress(pxbuffer);
    NSParameterAssert(pxdata != NULL);
    
    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
    
    CGContextRef context = CGBitmapContextCreate(pxdata,
                                                 frameWidth,
                                                 frameHeight,
                                                 8,
                                                 4 * frameWidth,
                                                 rgbColorSpace,
                                                 (CGBitmapInfo)kCGImageAlphaNoneSkipFirst);
    NSParameterAssert(context);
    CGContextConcatCTM(context, CGAffineTransformIdentity);
    CGContextDrawImage(context, CGRectMake(0,
                                           0,
                                           CGImageGetWidth(image),
                                           CGImageGetHeight(image)),
                       image);
    CGColorSpaceRelease(rgbColorSpace);
    CGContextRelease(context);
    
    CVPixelBufferUnlockBaseAddress(pxbuffer, 0);
    
    return pxbuffer;
}

+ (NSDictionary *)videoSettingsWithCodec:(NSString *)codec withWidth:(CGFloat)width andHeight:(CGFloat)height
{
    
    if ((int)width % 16 != 0 ) {
        NSLog(@"Warning: video settings width must be divisible by 16.");
    }
    
    NSDictionary *videoSettings = @{AVVideoCodecKey : AVVideoCodecH264,
                                    AVVideoWidthKey : [NSNumber numberWithInt:(int)width],
                                    AVVideoHeightKey : [NSNumber numberWithInt:(int)height]};
    
    return videoSettings;
}

@end
