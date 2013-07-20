//
//  XLDFdkAacOutputTask.m
//  XLDFdkAacOutput
//
//  Created by tmkk on 12/07/20.
//  Copyright 2012 tmkk. All rights reserved.
//

#import "XLDFdkAacOutputTask.h"
typedef int64_t xldoffset_t;
#import "XLDTrack.h"
#import "l-smash/mp4a.h"
struct lsmash_codec_specific_list_tag
{
    lsmash_entry_list_t list;
};

#define MP4SYS_ADTS_MAX_FRAME_LENGTH ( ( 1 << 13 ) - 1 )

AACENC_BufDesc *allocDesc(void)
{
	AACENC_BufDesc *desc = (AACENC_BufDesc *)malloc(sizeof(AACENC_BufDesc));
	desc->bufs = malloc(sizeof(void*));
	desc->bufferIdentifiers = malloc(sizeof(INT));
	desc->bufSizes = malloc(sizeof(INT));
	desc->bufElSizes = malloc(sizeof(INT));
	return desc;
}

void freeDesc(AACENC_BufDesc *desc)
{
	free(desc->bufs);
	free(desc->bufferIdentifiers);
	free(desc->bufSizes);
	free(desc->bufElSizes);
	free(desc);
}

@implementation XLDFdkAacOutputTask

- (id)init
{
	[super init];
	
	return self;
}

- (id)initWithConfigurations:(NSDictionary *)cfg
{
	[self init];
	configurations = [cfg retain];
	return self;
}

- (void)dealloc
{
	if(configurations) [configurations release];
	if(root) lsmash_destroy_root(root);
	if(summary) lsmash_cleanup_summary((lsmash_summary_t *)summary);
	if(outbuf) free(outbuf);
	if(inDesc) freeDesc(inDesc);
	if(outDesc) freeDesc(outDesc);
	
	[super dealloc];
}

- (BOOL)setOutputFormat:(XLDFormat)fmt
{
	format = fmt;
	if(format.bps > 4 || format.isFloat) return NO;
	
	uint32_t chmode;
	switch (format.channels) {
		case 1: chmode = MODE_1; break;
		case 2: chmode = MODE_2; break;
		case 3: chmode = MODE_1_2; break;
		case 4: chmode = MODE_1_2_1; break;
		case 5: chmode = MODE_1_2_2; break;
		case 6: chmode = MODE_1_2_2_1; break;
		default:
			fprintf(stderr, "Unsupported number of channels %d\n", format.channels);
			return NO;
	}
	
	sbrEnabled = NO;
	psEnabled = NO;
	
	AACENC_ERROR err = aacEncOpen(&encoder,0,0);
	if(err != AACENC_OK) {
		fprintf(stderr,"aacEncOpen error 0x%x\n",err);
		return NO;
	}
	
	if([[configurations objectForKey:@"Mode"] unsignedIntValue] == 1) {
		int aot;
		int mode;
		switch ([[configurations objectForKey:@"VBRQuality"] unsignedIntValue]) {
			case 0: aot = 29; mode = 1; break;
			case 1: aot = 29; mode = 2; break;
			case 2: aot = 5; mode = 1; break;
			case 3: aot = 5; mode = 2; break;
			case 4: aot = 5; mode = 3; break;
			case 5: aot = 5; mode = 4; break;
			case 6: aot = 2; mode = 2; break;
			case 7: aot = 2; mode = 3; break;
			case 8: aot = 2; mode = 4; break;
			case 9: aot = 2; mode = 5; break;
			default: aot = 2; mode = 3; break;
		};
		
		err = aacEncoder_SetParam(encoder,AACENC_AOT,aot);
		if(err != AACENC_OK) {
			fprintf(stderr,"aacEncoder_SetParam (AACENC_AOT) error 0x%x\n",err);
			goto fail;
		}
		err = aacEncoder_SetParam(encoder,AACENC_BITRATEMODE,mode);
		if(err != AACENC_OK) {
			fprintf(stderr,"aacEncoder_SetParam (AACENC_BITRATEMODE) error 0x%x\n",err);
			goto fail;
		}
	}
	else {
		int aot;
		switch ([[configurations objectForKey:@"Complexity"] unsignedIntValue]) {
			case 0: aot = 2; break;
			case 1: aot = 5; break;
			case 2: aot = 29; break;
			default: aot = 2; break;
		}
		err = aacEncoder_SetParam(encoder,AACENC_AOT,aot);
		if(err != AACENC_OK) {
			fprintf(stderr,"aacEncoder_SetParam (AACENC_AOT) error 0x%x\n",err);
			goto fail;
		}
		err = aacEncoder_SetParam(encoder,AACENC_BITRATEMODE,0);
		if(err != AACENC_OK) {
			fprintf(stderr,"aacEncoder_SetParam (AACENC_BITRATEMODE) error 0x%x\n",err);
			goto fail;
		}
		err = aacEncoder_SetParam(encoder,AACENC_BITRATE,[[configurations objectForKey:@"Bitrate"] unsignedIntValue]);
		if(err != AACENC_OK) {
			fprintf(stderr,"aacEncoder_SetParam (AACENC_BITRATE) error 0x%x\n",err);
			goto fail;
		}
	}
	
	err = aacEncoder_SetParam(encoder,AACENC_SAMPLERATE,format.samplerate);
	if(err != AACENC_OK) {
		fprintf(stderr,"aacEncoder_SetParam (AACENC_SAMPLERATE) error 0x%x\n",err);
		goto fail;
	}
	
	err = aacEncoder_SetParam(encoder,AACENC_CHANNELMODE,chmode);
	if(err != AACENC_OK) {
		fprintf(stderr,"aacEncoder_SetParam (AACENC_CHANNELMODE) error 0x%x\n",err);
		goto fail;
	}
	err = aacEncoder_SetParam(encoder,AACENC_AFTERBURNER,1);
	if(err != AACENC_OK) {
		fprintf(stderr,"aacEncoder_SetParam (AACENC_AFTERBURNER) error 0x%x\n",err);
		goto fail;
	}
	if([configurations objectForKey:@"LPFFreq"]) {
		unsigned int LPFFreq = [[configurations objectForKey:@"LPFFreq"] unsignedIntValue];
		if(LPFFreq > format.samplerate / 2) LPFFreq = format.samplerate / 2;
		err = aacEncoder_SetParam(encoder,AACENC_BANDWIDTH,LPFFreq);
		if(err != AACENC_OK) {
			fprintf(stderr,"aacEncoder_SetParam (AACENC_BANDWIDTH) error 0x%x\n",err);
			goto fail;
		}
	}
	err = aacEncoder_SetParam(encoder,AACENC_TRANSMUX,0);
	if(err != AACENC_OK) {
		fprintf(stderr,"aacEncoder_SetParam (AACENC_TRANSMUX) error 0x%x\n",err);
		goto fail;
	}
	
	err = aacEncEncode(encoder,NULL,NULL,NULL,NULL);
	if(err != AACENC_OK) {
		fprintf(stderr,"aacEncEncode parameter initialiation error 0x%x\n",err);
		goto fail;
	}
	
	if(aacEncoder_GetParam(encoder,AACENC_AOT) == 5) {
		sbrEnabled = YES;
	}
	else if(aacEncoder_GetParam(encoder,AACENC_AOT) == 29) {
		sbrEnabled = YES;
		psEnabled = YES;
	}
	
	return YES;
	
fail:
	aacEncClose(&encoder);
	return NO;
}

- (BOOL)openFileForOutput:(NSString *)str withTrackData:(id)track
{
	/* create mp4 file instance */
	root = lsmash_open_movie([str UTF8String],LSMASH_FILE_MODE_WRITE);
	
	/* setup movie params */
	lsmash_movie_parameters_t movie_param;
	lsmash_initialize_movie_parameters( &movie_param );
	uint32_t brands[3];
	brands[0] = ISOM_BRAND_TYPE_M4A;
	brands[1] = ISOM_BRAND_TYPE_MP42;
	brands[2] = ISOM_BRAND_TYPE_ISOM;
	movie_param.major_brand = brands[0];
	movie_param.brands = brands;
	movie_param.number_of_brands = 3;
	movie_param.minor_version = 0x00000000;
	lsmash_set_movie_parameters( root, &movie_param );
	
	/* create track */
	tid = lsmash_create_track( root, ISOM_MEDIA_HANDLER_TYPE_AUDIO_TRACK );
	
	/* setup track params */
	lsmash_track_parameters_t track_param;
	lsmash_initialize_track_parameters( &track_param );
	track_param.mode = ISOM_TRACK_ENABLED | ISOM_TRACK_IN_MOVIE | ISOM_TRACK_IN_PREVIEW;
	lsmash_set_track_parameters( root, tid, &track_param );
	
	/* setup media params */
	lsmash_media_parameters_t media_param;
	lsmash_initialize_media_parameters( &media_param );
	media_param.ISO_language = ISOM_LANGUAGE_CODE_ENGLISH;
	media_param.timescale = sbrEnabled ? format.samplerate/2 : format.samplerate;
	media_param.media_handler_name = "L-SMASH Audio Handler";
	media_param.roll_grouping = 0;
	lsmash_set_media_parameters( root, tid, &media_param );
	
	/* setup track sample summary */
	summary = (lsmash_audio_summary_t *)lsmash_create_summary( LSMASH_SUMMARY_TYPE_AUDIO );
	summary->sample_type            = ISOM_CODEC_TYPE_MP4A_AUDIO;
	summary->max_au_length          = MP4SYS_ADTS_MAX_FRAME_LENGTH;
	summary->frequency              = sbrEnabled ? format.samplerate/2 : format.samplerate;
	summary->channels               = psEnabled ? 1 : format.channels;
	summary->sample_size            = 16;
	summary->samples_in_frame       = 1024;
	summary->aot                    = MP4A_AUDIO_OBJECT_TYPE_AAC_LC;
	summary->sbr_mode               = sbrEnabled ? MP4A_AAC_SBR_BACKWARD_COMPATIBLE : MP4A_AAC_SBR_NOT_SPECIFIED;
	
	uint32_t data_length;
	uint8_t *data = mp4a_export_AudioSpecificConfig(summary->aot, summary->frequency, summary->channels, summary->sbr_mode,
													NULL, 0, &data_length );
	if(!data) {
		lsmash_cleanup_summary( (lsmash_summary_t *)summary );
		summary = NULL;
		return NO;
	}
	lsmash_codec_specific_t *specific = lsmash_create_codec_specific_data(LSMASH_CODEC_SPECIFIC_DATA_TYPE_MP4SYS_DECODER_CONFIG,
																		  LSMASH_CODEC_SPECIFIC_FORMAT_STRUCTURED);
	if(!specific) {
		lsmash_cleanup_summary( (lsmash_summary_t *)summary );
		free(data);
		summary = NULL;
		return NO;
	}
	lsmash_mp4sys_decoder_parameters_t *param = (lsmash_mp4sys_decoder_parameters_t *)specific->data.structured;
    param->objectTypeIndication = MP4SYS_OBJECT_TYPE_Audio_ISO_14496_3;
    param->streamType           = MP4SYS_STREAM_TYPE_AudioStream;
    if( lsmash_set_mp4sys_decoder_specific_info( param, data, data_length ) )
	{
		lsmash_cleanup_summary( (lsmash_summary_t *)summary );
		lsmash_destroy_codec_specific_data( specific );
		free( data );
		summary = NULL;
		return NO;
	}
	free( data );
	
	if( lsmash_add_entry( &summary->opaque->list, specific ) ) {
		lsmash_cleanup_summary( (lsmash_summary_t *)summary );
		lsmash_destroy_codec_specific_data( specific );
		summary = NULL;
		return NO;
	}
	
	sample_entry = lsmash_add_sample_entry( root, tid, summary );
	
	outbuf = malloc(65536);
	inDesc = allocDesc();
	outDesc = allocDesc();
	inDesc->numBufs = 1;
	inDesc->bufferIdentifiers[0] = IN_AUDIO_DATA;
	outDesc->numBufs = 1;
	outDesc->bufs[0] = outbuf;
	outDesc->bufferIdentifiers[0] = OUT_BITSTREAM_DATA;
	outDesc->bufSizes[0] = 65536;
	outDesc->bufElSizes[0] = 1;
	
	if(addTag) {
		lsmash_itunes_metadata_t metadata;
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TITLE]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TITLE];
			metadata.item = ITUNES_METADATA_ITEM_TITLE;
			metadata.type = ITUNES_METADATA_TYPE_STRING;
			metadata.value.string = (char*)[str UTF8String];
			metadata.meaning = NULL;
			metadata.name = NULL;
			lsmash_set_itunes_metadata(root, metadata);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ARTIST]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ARTIST];
			metadata.item = ITUNES_METADATA_ITEM_ARTIST;
			metadata.type = ITUNES_METADATA_TYPE_STRING;
			metadata.value.string = (char*)[str UTF8String];
			metadata.meaning = NULL;
			metadata.name = NULL;
			lsmash_set_itunes_metadata(root, metadata);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUM]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUM];
			metadata.item = ITUNES_METADATA_ITEM_ALBUM_NAME;
			metadata.type = ITUNES_METADATA_TYPE_STRING;
			metadata.value.string = (char*)[str UTF8String];
			metadata.meaning = NULL;
			metadata.name = NULL;
			lsmash_set_itunes_metadata(root, metadata);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMARTIST]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMARTIST];
			metadata.item = ITUNES_METADATA_ITEM_ALBUM_ARTIST;
			metadata.type = ITUNES_METADATA_TYPE_STRING;
			metadata.value.string = (char*)[str UTF8String];
			metadata.meaning = NULL;
			metadata.name = NULL;
			lsmash_set_itunes_metadata(root, metadata);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GENRE]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GENRE];
			metadata.item = ITUNES_METADATA_ITEM_USER_GENRE;
			metadata.type = ITUNES_METADATA_TYPE_STRING;
			metadata.value.string = (char*)[str UTF8String];
			metadata.meaning = NULL;
			metadata.name = NULL;
			lsmash_set_itunes_metadata(root, metadata);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPOSER]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPOSER];
			metadata.item = ITUNES_METADATA_ITEM_COMPOSER;
			metadata.type = ITUNES_METADATA_TYPE_STRING;
			metadata.value.string = (char*)[str UTF8String];
			metadata.meaning = NULL;
			metadata.name = NULL;
			lsmash_set_itunes_metadata(root, metadata);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TRACK] || [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALTRACKS]) {
			NSMutableData *tagData = [NSMutableData data];
			[tagData increaseLengthBy:2];
			short tmp = 0;
			if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TRACK]) {
				tmp = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TRACK] shortValue];
				tmp = OSSwapHostToBigInt16(tmp);
			}
			[tagData appendBytes:&tmp length:2];
			tmp = 0;
			if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALTRACKS]) {
				tmp = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALTRACKS] shortValue];
				tmp = OSSwapHostToBigInt16(tmp);
			}
			[tagData appendBytes:&tmp length:2];
			[tagData increaseLengthBy:2];
			metadata.item = ITUNES_METADATA_ITEM_TRACK_NUMBER;
			metadata.type = ITUNES_METADATA_TYPE_BINARY;
			metadata.value.binary.subtype = ITUNES_METADATA_SUBTYPE_IMPLICIT;
			metadata.value.binary.size = [tagData length];
			metadata.value.binary.data = (uint8_t *)[tagData bytes];
			metadata.meaning = NULL;
			metadata.name = NULL;
			lsmash_set_itunes_metadata(root, metadata);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_DISC] || [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALDISCS]) {
			NSMutableData *tagData = [NSMutableData data];
			[tagData increaseLengthBy:2];
			short tmp = 0;
			if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_DISC]) {
				tmp = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_DISC] shortValue];
				tmp = OSSwapHostToBigInt16(tmp);
			}
			[tagData appendBytes:&tmp length:2];
			tmp = 0;
			if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALDISCS]) {
				tmp = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TOTALDISCS] shortValue];
				tmp = OSSwapHostToBigInt16(tmp);
			}
			[tagData appendBytes:&tmp length:2];
			metadata.item = ITUNES_METADATA_ITEM_DISC_NUMBER;
			metadata.type = ITUNES_METADATA_TYPE_BINARY;
			metadata.value.binary.subtype = ITUNES_METADATA_SUBTYPE_IMPLICIT;
			metadata.value.binary.size = [tagData length];
			metadata.value.binary.data = (uint8_t *)[tagData bytes];
			metadata.meaning = NULL;
			metadata.name = NULL;
			lsmash_set_itunes_metadata(root, metadata);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_DATE]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_DATE];
			metadata.item = ITUNES_METADATA_ITEM_RELEASE_DATE;
			metadata.type = ITUNES_METADATA_TYPE_STRING;
			metadata.value.string = (char*)[str UTF8String];
			metadata.meaning = NULL;
			metadata.name = NULL;
			lsmash_set_itunes_metadata(root, metadata);
		}
		else if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_YEAR]) {
			NSString *str = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_YEAR] stringValue];
			metadata.item = ITUNES_METADATA_ITEM_RELEASE_DATE;
			metadata.type = ITUNES_METADATA_TYPE_STRING;
			metadata.value.string = (char*)[str UTF8String];
			metadata.meaning = NULL;
			metadata.name = NULL;
			lsmash_set_itunes_metadata(root, metadata);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMMENT]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMMENT];
			metadata.item = ITUNES_METADATA_ITEM_USER_COMMENT;
			metadata.type = ITUNES_METADATA_TYPE_STRING;
			metadata.value.string = (char*)[str UTF8String];
			metadata.meaning = NULL;
			metadata.name = NULL;
			lsmash_set_itunes_metadata(root, metadata);
		}
		else {
			NSMutableString *tmpStr = [NSMutableString string];
			if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_SMPTE_TIMECODE_START]) {
				[tmpStr appendFormat:@"Start TC=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_SMPTE_TIMECODE_START]];
			}
			if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_SMPTE_TIMECODE_DURATION]) {
				if([tmpStr length]) [tmpStr appendFormat:@"; Duration TC=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_SMPTE_TIMECODE_DURATION]];
				else [tmpStr appendFormat:@"Duration TC=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_SMPTE_TIMECODE_DURATION]];
			}
			if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MEDIA_FPS]) {
				if([tmpStr length]) [tmpStr appendFormat:@"; Media FPS=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MEDIA_FPS]];
				else [tmpStr appendFormat:@"Media FPS=%@",[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MEDIA_FPS]];
			}
			if([tmpStr length]) {
				metadata.item = ITUNES_METADATA_ITEM_USER_COMMENT;
				metadata.type = ITUNES_METADATA_TYPE_STRING;
				metadata.value.string = (char*)[tmpStr UTF8String];
				metadata.meaning = NULL;
				metadata.name = NULL;
				lsmash_set_itunes_metadata(root, metadata);
			}
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_LYRICS]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_LYRICS];
			metadata.item = ITUNES_METADATA_ITEM_LYRICS;
			metadata.type = ITUNES_METADATA_TYPE_STRING;
			metadata.value.string = (char*)[str UTF8String];
			metadata.meaning = NULL;
			metadata.name = NULL;
			lsmash_set_itunes_metadata(root, metadata);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GROUP]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GROUP];
			metadata.item = ITUNES_METADATA_ITEM_GROUPING;
			metadata.type = ITUNES_METADATA_TYPE_STRING;
			metadata.value.string = (char*)[str UTF8String];
			metadata.meaning = NULL;
			metadata.name = NULL;
			lsmash_set_itunes_metadata(root, metadata);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TITLESORT]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TITLESORT];
			metadata.item = ITUNES_METADATA_ITEM_ITUNES_SORT_NAME;
			metadata.type = ITUNES_METADATA_TYPE_STRING;
			metadata.value.string = (char*)[str UTF8String];
			metadata.meaning = NULL;
			metadata.name = NULL;
			lsmash_set_itunes_metadata(root, metadata);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ARTISTSORT]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ARTISTSORT];
			metadata.item = ITUNES_METADATA_ITEM_ITUNES_SORT_ARTIST;
			metadata.type = ITUNES_METADATA_TYPE_STRING;
			metadata.value.string = (char*)[str UTF8String];
			metadata.meaning = NULL;
			metadata.name = NULL;
			lsmash_set_itunes_metadata(root, metadata);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMSORT]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMSORT];
			metadata.item = ITUNES_METADATA_ITEM_ITUNES_SORT_ALBUM;
			metadata.type = ITUNES_METADATA_TYPE_STRING;
			metadata.value.string = (char*)[str UTF8String];
			metadata.meaning = NULL;
			metadata.name = NULL;
			lsmash_set_itunes_metadata(root, metadata);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMARTISTSORT]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMARTISTSORT];
			metadata.item = ITUNES_METADATA_ITEM_ITUNES_SORT_ALBUM_ARTIST;
			metadata.type = ITUNES_METADATA_TYPE_STRING;
			metadata.value.string = (char*)[str UTF8String];
			metadata.meaning = NULL;
			metadata.name = NULL;
			lsmash_set_itunes_metadata(root, metadata);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPOSERSORT]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPOSERSORT];
			metadata.item = ITUNES_METADATA_ITEM_ITUNES_SORT_COMPOSER;
			metadata.type = ITUNES_METADATA_TYPE_STRING;
			metadata.value.string = (char*)[str UTF8String];
			metadata.meaning = NULL;
			metadata.name = NULL;
			lsmash_set_itunes_metadata(root, metadata);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPILATION]) {
			if([[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPILATION] boolValue]) {
				metadata.item = ITUNES_METADATA_ITEM_DISC_COMPILATION;
				metadata.type = ITUNES_METADATA_TYPE_BOOLEAN;
				metadata.value.boolean = LSMASH_BOOLEAN_TRUE;
				metadata.meaning = NULL;
				metadata.name = NULL;
				lsmash_set_itunes_metadata(root, metadata);
			}
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GRACENOTE]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GRACENOTE];
			metadata.item = ITUNES_METADATA_ITEM_CUSTOM;
			metadata.type = ITUNES_METADATA_TYPE_STRING;
			metadata.value.string = (char*)[str UTF8String];
			metadata.meaning = "com.apple.iTunes";
			metadata.name = "iTunes_CDDB_IDs";
			lsmash_set_itunes_metadata(root, metadata);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GRACENOTE2]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GRACENOTE2];
			metadata.item = ITUNES_METADATA_ITEM_CUSTOM;
			metadata.type = ITUNES_METADATA_TYPE_STRING;
			metadata.value.string = (char*)[str UTF8String];
			metadata.meaning = "com.apple.iTunes";
			metadata.name = "iTunes_CDDB_1";
			lsmash_set_itunes_metadata(root, metadata);
			if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TRACK]) {
				str = [NSString stringWithFormat:@"%d",[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TRACK] intValue]];
				metadata.item = ITUNES_METADATA_ITEM_CUSTOM;
				metadata.type = ITUNES_METADATA_TYPE_STRING;
				metadata.value.string = (char*)[str UTF8String];
				metadata.meaning = "com.apple.iTunes";
				metadata.name = "iTunes_CDDB_TrackNumber";
				lsmash_set_itunes_metadata(root, metadata);
			}
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_BPM]) {
			metadata.item = ITUNES_METADATA_ITEM_BEATS_PER_MINUTE;
			metadata.type = ITUNES_METADATA_TYPE_INTEGER;
			metadata.value.integer = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_BPM] shortValue];
			metadata.meaning = NULL;
			metadata.name = NULL;
			lsmash_set_itunes_metadata(root, metadata);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COPYRIGHT]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COPYRIGHT];
			metadata.item = ITUNES_METADATA_ITEM_COPYRIGHT;
			metadata.type = ITUNES_METADATA_TYPE_STRING;
			metadata.value.string = (char*)[str UTF8String];
			metadata.meaning = NULL;
			metadata.name = NULL;
			lsmash_set_itunes_metadata(root, metadata);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GAPLESSALBUM]) {
			if([[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GAPLESSALBUM] boolValue]) {
				metadata.item = ITUNES_METADATA_ITEM_GAPLESS_PLAYBACK;
				metadata.type = ITUNES_METADATA_TYPE_BOOLEAN;
				metadata.value.boolean = LSMASH_BOOLEAN_TRUE;
				metadata.meaning = NULL;
				metadata.name = NULL;
				lsmash_set_itunes_metadata(root, metadata);
			}
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_TRACKID]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_TRACKID];
			metadata.item = ITUNES_METADATA_ITEM_CUSTOM;
			metadata.type = ITUNES_METADATA_TYPE_STRING;
			metadata.value.string = (char*)[str UTF8String];
			metadata.meaning = "com.apple.iTunes";
			metadata.name = "MusicBrainz Track Id";
			lsmash_set_itunes_metadata(root, metadata);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMID]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMID];
			metadata.item = ITUNES_METADATA_ITEM_CUSTOM;
			metadata.type = ITUNES_METADATA_TYPE_STRING;
			metadata.value.string = (char*)[str UTF8String];
			metadata.meaning = "com.apple.iTunes";
			metadata.name = "MusicBrainz Album Id";
			lsmash_set_itunes_metadata(root, metadata);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ARTISTID]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ARTISTID];
			metadata.item = ITUNES_METADATA_ITEM_CUSTOM;
			metadata.type = ITUNES_METADATA_TYPE_STRING;
			metadata.value.string = (char*)[str UTF8String];
			metadata.meaning = "com.apple.iTunes";
			metadata.name = "MusicBrainz Artist Id";
			lsmash_set_itunes_metadata(root, metadata);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMARTISTID]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMARTISTID];
			metadata.item = ITUNES_METADATA_ITEM_CUSTOM;
			metadata.type = ITUNES_METADATA_TYPE_STRING;
			metadata.value.string = (char*)[str UTF8String];
			metadata.meaning = "com.apple.iTunes";
			metadata.name = "MusicBrainz Album Artist Id";
			lsmash_set_itunes_metadata(root, metadata);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_DISCID]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_DISCID];
			metadata.item = ITUNES_METADATA_ITEM_CUSTOM;
			metadata.type = ITUNES_METADATA_TYPE_STRING;
			metadata.value.string = (char*)[str UTF8String];
			metadata.meaning = "com.apple.iTunes";
			metadata.name = "MusicBrainz Disc Id";
			lsmash_set_itunes_metadata(root, metadata);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_PUID]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_PUID];
			metadata.item = ITUNES_METADATA_ITEM_CUSTOM;
			metadata.type = ITUNES_METADATA_TYPE_STRING;
			metadata.value.string = (char*)[str UTF8String];
			metadata.meaning = "com.apple.iTunes";
			metadata.name = "MusicIP PUID";
			lsmash_set_itunes_metadata(root, metadata);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMSTATUS]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMSTATUS];
			metadata.item = ITUNES_METADATA_ITEM_CUSTOM;
			metadata.type = ITUNES_METADATA_TYPE_STRING;
			metadata.value.string = (char*)[str UTF8String];
			metadata.meaning = "com.apple.iTunes";
			metadata.name = "MusicBrainz Album Status";
			lsmash_set_itunes_metadata(root, metadata);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMTYPE]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMTYPE];
			metadata.item = ITUNES_METADATA_ITEM_CUSTOM;
			metadata.type = ITUNES_METADATA_TYPE_STRING;
			metadata.value.string = (char*)[str UTF8String];
			metadata.meaning = "com.apple.iTunes";
			metadata.name = "MusicBrainz Album Type";
			lsmash_set_itunes_metadata(root, metadata);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_RELEASECOUNTRY]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_RELEASECOUNTRY];
			metadata.item = ITUNES_METADATA_ITEM_CUSTOM;
			metadata.type = ITUNES_METADATA_TYPE_STRING;
			metadata.value.string = (char*)[str UTF8String];
			metadata.meaning = "com.apple.iTunes";
			metadata.name = "MusicBrainz Album Release Country";
			lsmash_set_itunes_metadata(root, metadata);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_RELEASEGROUPID]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_RELEASEGROUPID];
			metadata.item = ITUNES_METADATA_ITEM_CUSTOM;
			metadata.type = ITUNES_METADATA_TYPE_STRING;
			metadata.value.string = (char*)[str UTF8String];
			metadata.meaning = "com.apple.iTunes";
			metadata.name = "MusicBrainz Release Group Id";
			lsmash_set_itunes_metadata(root, metadata);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_WORKID]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_WORKID];
			metadata.item = ITUNES_METADATA_ITEM_CUSTOM;
			metadata.type = ITUNES_METADATA_TYPE_STRING;
			metadata.value.string = (char*)[str UTF8String];
			metadata.meaning = "com.apple.iTunes";
			metadata.name = "MusicBrainz Work Id";
			lsmash_set_itunes_metadata(root, metadata);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_SMPTE_TIMECODE_START]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_SMPTE_TIMECODE_START];
			metadata.item = ITUNES_METADATA_ITEM_CUSTOM;
			metadata.type = ITUNES_METADATA_TYPE_STRING;
			metadata.value.string = (char*)[str UTF8String];
			metadata.meaning = "com.apple.iTunes";
			metadata.name = "SMPTE_TIMECODE_START";
			lsmash_set_itunes_metadata(root, metadata);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_SMPTE_TIMECODE_DURATION]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_SMPTE_TIMECODE_DURATION];
			metadata.item = ITUNES_METADATA_ITEM_CUSTOM;
			metadata.type = ITUNES_METADATA_TYPE_STRING;
			metadata.value.string = (char*)[str UTF8String];
			metadata.meaning = "com.apple.iTunes";
			metadata.name = "SMPTE_TIMECODE_DURATION";
			lsmash_set_itunes_metadata(root, metadata);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MEDIA_FPS]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MEDIA_FPS];
			metadata.item = ITUNES_METADATA_ITEM_CUSTOM;
			metadata.type = ITUNES_METADATA_TYPE_STRING;
			metadata.value.string = (char*)[str UTF8String];
			metadata.meaning = "com.apple.iTunes";
			metadata.name = "MEDIA_FPS";
			lsmash_set_itunes_metadata(root, metadata);
		}
		
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COVER]) {
			NSData *imgData = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COVER];
			if([imgData length] >= 8 && 0 == memcmp([imgData bytes], "\x89PNG\x0d\x0a\x1a\x0a", 8))
				metadata.value.binary.subtype = ITUNES_METADATA_SUBTYPE_PNG;
			else if([imgData length] >= 2 && 0 == memcmp([imgData bytes], "BM", 2))
				metadata.value.binary.subtype = ITUNES_METADATA_SUBTYPE_BMP;
			else if([imgData length] >= 3 && 0 == memcmp([imgData bytes], "GIF", 3))
				metadata.value.binary.subtype = ITUNES_METADATA_SUBTYPE_GIF;
			else metadata.value.binary.subtype = ITUNES_METADATA_SUBTYPE_JPEG;
			metadata.item = ITUNES_METADATA_ITEM_COVER_ART;
			metadata.type = ITUNES_METADATA_TYPE_BINARY;
			metadata.value.binary.size = [imgData length];
			metadata.value.binary.data = (uint8_t *)[imgData bytes];
			metadata.meaning = NULL;
			metadata.name = NULL;
			lsmash_set_itunes_metadata(root, metadata);
		}
		{
			LIB_INFO *info = calloc(FDK_MODULE_LAST, sizeof(LIB_INFO));
			aacEncGetLibInfo(info);
			int i;
			for(i=0;i<FDK_MODULE_LAST;i++) {
				if(info[i].module_id == FDK_AACENC) break;
			}
			NSString *params;
			if([[configurations objectForKey:@"Mode"] unsignedIntValue] == 1) {
				params = [NSString stringWithFormat:@"%@%@, VBR Quality %d",sbrEnabled?@", HE-AAC":@"",psEnabled?@" v2":@"",[[configurations objectForKey:@"VBRQuality"] unsignedIntValue]];
			}
			else {
				params = [NSString stringWithFormat:@"%@%@, CBR %d kbps",sbrEnabled?@", HE-AAC":@"",psEnabled?@" v2":@"",[[configurations objectForKey:@"Bitrate"] unsignedIntValue]/1000];
			}
			NSString *str = [NSString stringWithFormat:@"X Lossless Decoder %@, FDK AAC Encoder %s%@",[[NSBundle mainBundle] objectForInfoDictionaryKey: @"CFBundleShortVersionString"],info[i].versionStr,params];
			metadata.item = ITUNES_METADATA_ITEM_ENCODING_TOOL;
			metadata.type = ITUNES_METADATA_TYPE_STRING;
			metadata.value.string = (char*)[str UTF8String];
			metadata.meaning = NULL;
			metadata.name = NULL;
			lsmash_set_itunes_metadata(root, metadata);
			free(info);
		}
	}
	
	return YES;
}

- (NSString *)extensionStr
{
	return @"m4a";
}

- (BOOL)writeBuffer:(int *)buffer frames:(int)counts
{
	AACENC_ERROR err;
	totalFrames += counts;
	int rest = counts * format.channels;
	AACENC_InArgs inArgs;
	AACENC_OutArgs outArgs;
	while(rest) {
		inDesc->bufs[0] = buffer;
		inDesc->bufSizes[0] = rest * 4;
		inDesc->bufElSizes[0] = 4;
		inArgs.numInSamples = rest;
		inArgs.numAncBytes = 0;
		err = aacEncEncode(encoder,inDesc,outDesc,&inArgs,&outArgs);
		if(err != AACENC_OK) {
			fprintf(stderr,"aacEncEncode error 0x%x\n",err);
			return NO;
		}
		rest -= outArgs.numInSamples;
		buffer += outArgs.numInSamples;
		if(outArgs.numOutBytes) {
			lsmash_sample_t *sample = lsmash_create_sample( summary->max_au_length );
			sample->prop.ra_flags = ISOM_SAMPLE_RANDOM_ACCESS_FLAG_SYNC;
			sample->prop.pre_roll.distance = 1;
			sample->index = sample_entry;
			memcpy(sample->data,outbuf,outArgs.numOutBytes);
			sample->length = outArgs.numOutBytes;
			sample->dts = au_number++ * summary->samples_in_frame;
			sample->cts = sample->dts;
			lsmash_append_sample(root,tid,sample);
			encoded += outArgs.numOutBytes;
		}
		if(rest == 0) break;
	}
	return YES;
}

- (void)finalize
{
	AACENC_ERROR err;
	AACENC_InArgs inArgs;
	AACENC_OutArgs outArgs;
	while(1) {
		inDesc->bufs[0] = NULL;
		inDesc->bufSizes[0] = 0;
		inDesc->bufElSizes[0] = 4;
		inArgs.numInSamples = -1;
		inArgs.numAncBytes = 0;
		err = aacEncEncode(encoder,inDesc,outDesc,&inArgs,&outArgs);
		if(err != AACENC_OK && err != AACENC_ENCODE_EOF) {
			fprintf(stderr,"aacEncEncode error 0x%x\n",err);
			break;
		}
		if(err == AACENC_ENCODE_EOF) break;
		if(outArgs.numOutBytes) {
			lsmash_sample_t *sample = lsmash_create_sample( summary->max_au_length );
			sample->prop.ra_flags = ISOM_SAMPLE_RANDOM_ACCESS_FLAG_SYNC;
			sample->prop.pre_roll.distance = 1;
			sample->index = sample_entry;
			memcpy(sample->data,outbuf,outArgs.numOutBytes);
			sample->length = outArgs.numOutBytes;
			sample->dts = au_number++ * summary->samples_in_frame;
			sample->cts = sample->dts;
			lsmash_append_sample(root,tid,sample);
			encoded += outArgs.numOutBytes;
		}
	}
	lsmash_flush_pooled_samples(root,tid,1024);
	
	{
		lsmash_itunes_metadata_t metadata;
		AACENC_InfoStruct info;
		aacEncInfo(encoder,&info);
		char iTunSMPB[256];
		uint32_t delay = info.encoderDelay;
		uint64_t duration = totalFrames;
		if(sbrEnabled) {
			duration /= 2;
#if 1
			/* HACK for iTunes : Apple's decoder does not play gaplessly with the provided delay value */
			if(!psEnabled) delay = 2048;
			else delay = 2544;
#else
			delay /= 2;
#endif
		}
		uint32_t padding = (uint32_t)ceil((duration + delay)/1024.0)*1024 - (duration + delay);
		sprintf(iTunSMPB," 00000000 %08X %08X %016llX 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000",delay,padding,duration);
		metadata.item = ITUNES_METADATA_ITEM_CUSTOM;
		metadata.type = ITUNES_METADATA_TYPE_STRING;
		metadata.value.string = iTunSMPB;
		metadata.meaning = "com.apple.iTunes";
		metadata.name = "iTunSMPB";
		lsmash_set_itunes_metadata(root, metadata);
	}
	{
		lsmash_itunes_metadata_t metadata;
		double sec = (double)totalFrames/(double)format.samplerate;
		NSMutableData *tagData = [NSMutableData data];
		int tmp;
		tmp = OSSwapHostToBigInt32(1);
		[tagData appendBytes:"vers" length:4];
		[tagData appendBytes:&tmp length:4];
		tmp = [[configurations objectForKey:@"Mode"] unsignedIntValue];
		if(tmp > 0) tmp = 3;
		tmp = OSSwapHostToBigInt32(tmp);
		[tagData appendBytes:"acbf" length:4];
		[tagData appendBytes:&tmp length:4];
		tmp = OSSwapHostToBigInt32((int)round(encoded/sec*8));
		[tagData appendBytes:"brat" length:4];
		[tagData appendBytes:&tmp length:4];
		LIB_INFO *info = calloc(FDK_MODULE_LAST, sizeof(LIB_INFO));
		aacEncGetLibInfo(info);
		int i;
		for(i=0;i<FDK_MODULE_LAST;i++) {
			if(info[i].module_id == FDK_AACENC) break;
		}
		tmp = OSSwapHostToBigInt32(info[i].version);
		[tagData appendBytes:"cdcv" length:4];
		[tagData appendBytes:&tmp length:4];
		metadata.item = ITUNES_METADATA_ITEM_CUSTOM;
		metadata.type = ITUNES_METADATA_TYPE_BINARY;
		metadata.value.binary.subtype = ITUNES_METADATA_SUBTYPE_IMPLICIT;
		metadata.value.binary.size = [tagData length];
		metadata.value.binary.data = (uint8_t *)[tagData bytes];
		metadata.meaning = "com.apple.iTunes";
		metadata.name = "Encoding Params";
		lsmash_set_itunes_metadata(root, metadata);
		free(info);
	}
	
	lsmash_adhoc_remux_t moov_to_front;
	moov_to_front.func        = NULL;
	moov_to_front.buffer_size = 4*1024*1024;    /* 4MiB */
	moov_to_front.param       = NULL;
	
	lsmash_finish_movie(root,&moov_to_front);
}

- (void)closeFile
{
	aacEncClose(&encoder);
}

- (void)setEnableAddTag:(BOOL)flag
{
	addTag = flag;
}

@end
