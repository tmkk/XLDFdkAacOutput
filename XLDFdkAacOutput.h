//
//  XLDFdkAacOutput.h
//  XLDFdkAacOutput
//
//  Created by tmkk on 12/07/20.
//  Copyright 2012 tmkk. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "XLDOutput.h"

@interface XLDFdkAacOutput : NSObject <XLDOutput> {
	IBOutlet id o_prefPane;
	IBOutlet id o_encoderMode;
	IBOutlet id o_complexity;
	IBOutlet id o_bitrate;
	IBOutlet id o_vbrQuality;
	IBOutlet id o_summary;
	IBOutlet id o_text1;
	IBOutlet id o_text2;
	IBOutlet id o_text3;
	IBOutlet id o_text4;
	IBOutlet id o_text5;
}

+ (NSString *)pluginName;
+ (BOOL)canLoadThisBundle;
- (NSView *)prefPane;
- (void)savePrefs;
- (void)loadPrefs;
- (id)createTaskForOutput;
- (id)createTaskForOutputWithConfigurations:(NSDictionary *)cfg;
- (NSMutableDictionary *)configurations;
- (void)loadConfigurations:(id)cfg;

- (IBAction)modeChanged:(id)sender;

@end
