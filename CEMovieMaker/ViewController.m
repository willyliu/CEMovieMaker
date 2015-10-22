//
//  ViewController.m
//  CEMovieMaker
//
//  Created by Cameron Ehrlich on 9/17/14.
//  Copyright (c) 2014 Cameron Ehrlich. All rights reserved.
//

#import "ViewController.h"
#import "CEMovieMaker.h"
#import "UIImage+Resize.h"
@import MediaPlayer;

@interface ViewController ()

@property (nonatomic, strong) CEMovieMaker *movieMaker;

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setImage:[UIImage imageNamed:@"icon2"] forState:UIControlStateNormal];
    [button setFrame:CGRectMake(0, 0, self.view.bounds.size.width, 100)];
    [button.imageView setContentMode:UIViewContentModeScaleAspectFit];
    [button addTarget:self action:@selector(process:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:button];
}

- (void)process:(id)sender
{
    NSMutableArray *frames = [[NSMutableArray alloc] init];
    
    UIImage *icon1 = [[UIImage imageNamed:@"icon1"] resizedImage:CGSizeMake(512.0, 512.0) interpolationQuality:kCGInterpolationHigh];
    UIImage *icon2 = [[UIImage imageNamed:@"icon2"] resizedImage:CGSizeMake(512.0, 512.0) interpolationQuality:kCGInterpolationHigh];
    UIImage *icon3 = [[UIImage imageNamed:@"icon3"] resizedImage:CGSizeMake(512.0, 512.0) interpolationQuality:kCGInterpolationHigh];
    
    NSDictionary *settings = [CEMovieMaker videoSettingsWithCodec:AVVideoCodecH264 withWidth:icon1.size.width andHeight:icon1.size.height];
    self.movieMaker = [[CEMovieMaker alloc] initWithSettings:settings];
    for (NSInteger i = 0; i < 2; i++) {
        [frames addObject:icon1];
        [frames addObject:icon2];
        [frames addObject:icon3];
    }

	NSURL *backgroundAudioFileURL = [[NSBundle mainBundle] URLForResource:@"backgroundMusic" withExtension:@"mov"];
	NSURL *prefixMovieFileURL = [[NSBundle mainBundle] URLForResource:@"prefixMovie" withExtension:@"mp4"];
    [self.movieMaker createMovieFromPrefixMovieFileURL:prefixMovieFileURL images:[frames copy] backgroundAudioFileURL:backgroundAudioFileURL withCompletion:^(NSURL *fileURL){
		[self saveToCameraRoll:fileURL];
        [self viewMovieAtUrl:fileURL];
    }];
}

- (void)viewMovieAtUrl:(NSURL *)fileURL
{
    MPMoviePlayerViewController *playerController = [[MPMoviePlayerViewController alloc] initWithContentURL:fileURL];
    [playerController.view setFrame:self.view.bounds];
    [self presentMoviePlayerViewControllerAnimated:playerController];
    [playerController.moviePlayer prepareToPlay];
    [playerController.moviePlayer play];
    [self.view addSubview:playerController.view];
}

- (void)saveToCameraRoll:(NSURL *)srcURL
{
	NSLog(@"srcURL: %@", srcURL);
	
	ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
	ALAssetsLibraryWriteVideoCompletionBlock videoWriteCompletionBlock =
	^(NSURL *newURL, NSError *error) {
		if (error) {
			NSLog( @"Error writing image with metadata to Photo Library: %@", error );
		} else {
			NSLog( @"Wrote image with metadata to Photo Library %@", newURL.absoluteString);
		}
	};
	
	if ([library videoAtPathIsCompatibleWithSavedPhotosAlbum:srcURL])
	{
		[library writeVideoAtPathToSavedPhotosAlbum:srcURL
									completionBlock:videoWriteCompletionBlock];
	}
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
