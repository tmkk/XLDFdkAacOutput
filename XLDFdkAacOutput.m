//
//  XLDFdkAacOutput.m
//  XLDFdkAacOutput
//
//  Created by tmkk on 12/07/20.
//  Copyright 2012 tmkk. All rights reserved.
//

#import "XLDFdkAacOutput.h"
#import "XLDFdkAacOutputTask.h"

@implementation XLDFdkAacOutput

+ (NSString *)pluginName
{
	return @"MPEG-4 AAC (FDK)";
}

+ (BOOL)canLoadThisBundle
{
	return YES;
}

- (id)init
{
	[super init];
	[NSBundle loadNibNamed:@"XLDFdkAacOutput" owner:self];
	[self modeChanged:nil];
	return self;
}

- (NSView *)prefPane
{
	return o_prefPane;
}

- (void)savePrefs
{
	NSUserDefaults *pref = [NSUserDefaults standardUserDefaults];
	[pref setInteger:[o_encoderMode indexOfSelectedItem] forKey:@"XLDFdkAacOutput_Mode"];
	[pref setInteger:[o_bitrate intValue] forKey:@"XLDFdkAacOutput_Bitrate"];
	[pref setInteger:[o_vbrQuality intValue] forKey:@"XLDFdkAacOutput_VBRQuality"];
	[pref setInteger:[[o_complexity selectedCell] tag] forKey:@"XLDFdkAacOutput_Complexity"];
	[pref setInteger:[o_manualLPF state] forKey:@"XLDFdkAacOutput_ManualLPF"];
	[pref setInteger:[o_LPFFreq intValue] forKey:@"XLDFdkAacOutput_LPFFreq"];
	[pref synchronize];
}

- (void)loadPrefs
{
	NSUserDefaults *pref = [NSUserDefaults standardUserDefaults];
	[self loadConfigurations:pref];
}

- (id)createTaskForOutput
{
	return [[XLDFdkAacOutputTask alloc] initWithConfigurations:[self configurations]];
}

- (id)createTaskForOutputWithConfigurations:(NSDictionary *)cfg
{
	return [[XLDFdkAacOutputTask alloc] initWithConfigurations:cfg];
}

- (unsigned int)LPFFreq
{
	if([o_manualLPF state] == NSOffState) return 0;
	return [o_LPFFreq intValue];
}

- (NSMutableDictionary *)configurations
{
	NSMutableDictionary *cfg = [[NSMutableDictionary alloc] init];
	/* for GUI */
	[cfg setObject:[NSNumber numberWithInt:[o_encoderMode indexOfSelectedItem]] forKey:@"XLDFdkAacOutput_Mode"];
	[cfg setObject:[NSNumber numberWithInt:[o_bitrate intValue]] forKey:@"XLDFdkAacOutput_Bitrate"];
	[cfg setObject:[NSNumber numberWithInt:[o_vbrQuality intValue]] forKey:@"XLDFdkAacOutput_VBRQuality"];
	[cfg setObject:[NSNumber numberWithInt:[[o_complexity selectedCell] tag]] forKey:@"XLDFdkAacOutput_Complexity"];
	[cfg setObject:[NSNumber numberWithInt:[o_manualLPF state]] forKey:@"XLDFdkAacOutput_ManualLPF"];
	[cfg setObject:[NSNumber numberWithInt:[o_LPFFreq intValue]] forKey:@"XLDFdkAacOutput_LPFFreq"];
	/* for task */
	[cfg setObject:[NSNumber numberWithUnsignedInt:[o_encoderMode indexOfSelectedItem]] forKey:@"Mode"];
	[cfg setObject:[NSNumber numberWithUnsignedInt:[o_bitrate intValue]*1000] forKey:@"Bitrate"];
	[cfg setObject:[NSNumber numberWithUnsignedInt:[o_vbrQuality intValue]] forKey:@"VBRQuality"];
	[cfg setObject:[NSNumber numberWithUnsignedInt:[[o_complexity selectedCell] tag]] forKey:@"Complexity"];
	[cfg setObject:[NSNumber numberWithUnsignedInt:[self LPFFreq]] forKey:@"LPFFreq"];
	/* desc */
	if([o_encoderMode indexOfSelectedItem] == 0) {
		if([[o_complexity selectedCell] tag] == 0)
			[cfg setObject:[NSString stringWithFormat:@"CBR %dkbps",[o_bitrate intValue]] forKey:@"ShortDesc"];
		else if([[o_complexity selectedCell] tag] == 1)
			[cfg setObject:[NSString stringWithFormat:@"HE-AAC, CBR %dkbps",[o_bitrate intValue]] forKey:@"ShortDesc"];
		else
			[cfg setObject:[NSString stringWithFormat:@"HE-AAC v2, CBR %dkbps",[o_bitrate intValue]] forKey:@"ShortDesc"];
	}
	else if([o_encoderMode indexOfSelectedItem] == 1) {
		if([o_vbrQuality intValue] < 2)
			[cfg setObject:[NSString stringWithFormat:@"HE-AAC v2, VBR quality %d",[o_vbrQuality intValue]] forKey:@"ShortDesc"];
		else if([o_vbrQuality intValue] < 6)
			[cfg setObject:[NSString stringWithFormat:@"HE-AAC, VBR quality %d",[o_vbrQuality intValue]] forKey:@"ShortDesc"];
		else
			[cfg setObject:[NSString stringWithFormat:@"VBR quality %d",[o_vbrQuality intValue]] forKey:@"ShortDesc"];
	}
	
	return [cfg autorelease];
}

- (IBAction)modeChanged:(id)sender
{
	if([o_encoderMode indexOfSelectedItem] == 0) {
		[o_bitrate setEnabled:YES];
		[o_complexity setEnabled:YES];
		[o_text1 setTextColor:[NSColor controlTextColor]];
		[o_text2 setTextColor:[NSColor controlTextColor]];
		[o_text5 setTextColor:[NSColor controlTextColor]];
		[o_vbrQuality setEnabled:NO];
		[o_summary setTextColor:[NSColor disabledControlTextColor]];
		[o_text3 setTextColor:[NSColor disabledControlTextColor]];
		[o_text4 setTextColor:[NSColor disabledControlTextColor]];
	}
	else if([o_encoderMode indexOfSelectedItem] == 1) {
		[o_bitrate setEnabled:NO];
		[o_complexity setEnabled:NO];
		[o_text1 setTextColor:[NSColor disabledControlTextColor]];
		[o_text2 setTextColor:[NSColor disabledControlTextColor]];
		[o_text5 setTextColor:[NSColor disabledControlTextColor]];
		[o_vbrQuality setEnabled:YES];
		[o_summary setTextColor:[NSColor controlTextColor]];
		[o_text3 setTextColor:[NSColor controlTextColor]];
		[o_text4 setTextColor:[NSColor controlTextColor]];
	}
	switch ([o_vbrQuality intValue]) {
		case 0:
			[o_summary setStringValue:@"Quality 0: HE-AAC v2, ~35kbps"];
			break;
		case 1:
			[o_summary setStringValue:@"Quality 1: HE-AAC v2, ~45kbps"];
			break;
		case 2:
			[o_summary setStringValue:@"Quality 2: HE-AAC, ~50kbps"];
			break;
		case 3:
			[o_summary setStringValue:@"Quality 3: HE-AAC, ~75kbps"];
			break;
		case 4:
			[o_summary setStringValue:@"Quality 4: HE-AAC, ~85kbps"];
			break;
		case 5:
			[o_summary setStringValue:@"Quality 5: HE-AAC, ~100kbps"];
			break;
		case 6:
			[o_summary setStringValue:@"Quality 6: LC-AAC, ~110kbps"];
			break;
		case 7:
			[o_summary setStringValue:@"Quality 7: LC-AAC, ~130kbps"];
			break;
		case 8:
			[o_summary setStringValue:@"Quality 8: LC-AAC, ~150kbps"];
			break;
		case 9:
			[o_summary setStringValue:@"Quality 9: LC-AAC, ~250kbps"];
			break;
		default:
			break;
	}
	if([o_manualLPF state] == NSOnState) {
		[o_LPFFreq setEnabled:YES];
		[o_text6 setTextColor:[NSColor controlTextColor]];
	}
	else {
		[o_LPFFreq setEnabled:NO];
		[o_text6 setTextColor:[NSColor disabledControlTextColor]];
	}
}

- (void)loadConfigurations:(id)cfg
{
	id obj;
	if(obj=[cfg objectForKey:@"XLDFdkAacOutput_Bitrate"]) {
		[o_bitrate setIntValue:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDFdkAacOutput_Mode"]) {
		if([obj intValue] < [o_encoderMode numberOfItems]) [o_encoderMode selectItemAtIndex:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDFdkAacOutput_VBRQuality"]) {
		[o_vbrQuality setIntValue:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDFdkAacOutput_Complexity"]) {
		[o_complexity selectCellWithTag:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDFdkAacOutput_ManualLPF"]) {
		[o_manualLPF setState:[obj intValue]];
	}
	if(obj=[cfg objectForKey:@"XLDFdkAacOutput_LPFFreq"]) {
		[o_LPFFreq setIntValue:[obj intValue]];
	}
	[self modeChanged:self];
}

@end
