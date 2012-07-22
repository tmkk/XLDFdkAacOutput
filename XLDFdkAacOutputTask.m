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
	media_param.timescale = sbrEnabled ? 22050 : 44100;
	media_param.media_handler_name = "L-SMASH Audio Handler";
	media_param.roll_grouping = 0;
	lsmash_set_media_parameters( root, tid, &media_param );
	
	/* setup track sample summary */
	summary = (lsmash_audio_summary_t *)lsmash_create_summary(MP4SYS_STREAM_TYPE_AudioStream);
	summary->sample_type            = ISOM_CODEC_TYPE_MP4A_AUDIO;
	summary->object_type_indication = MP4SYS_OBJECT_TYPE_Audio_ISO_14496_3;
	summary->max_au_length          = MP4SYS_ADTS_MAX_FRAME_LENGTH;
	summary->frequency              = sbrEnabled ? format.samplerate/2 : format.samplerate;
	summary->channels               = psEnabled ? 1 : format.channels;
	summary->bit_depth              = 16;
	summary->samples_in_frame       = 1024;
	summary->aot                    = MP4A_AUDIO_OBJECT_TYPE_AAC_LC;
	summary->sbr_mode               = sbrEnabled ? MP4A_AAC_SBR_BACKWARD_COMPATIBLE : MP4A_AAC_SBR_NOT_SPECIFIED;
	lsmash_setup_AudioSpecificConfig(summary);
	sample_entry = lsmash_add_sample_entry( root, tid, ISOM_CODEC_TYPE_MP4A_AUDIO, summary );
	
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
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TITLE]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TITLE];
			lsmash_set_itunes_metadata(root, ITUNES_METADATA_ITEM_TITLE, ITUNES_METADATA_TYPE_STRING, (lsmash_itunes_metadata_t)(char*)[str UTF8String], NULL, NULL);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ARTIST]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ARTIST];
			lsmash_set_itunes_metadata(root, ITUNES_METADATA_ITEM_ARTIST, ITUNES_METADATA_TYPE_STRING, (lsmash_itunes_metadata_t)(char*)[str UTF8String], NULL, NULL);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUM]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUM];
			lsmash_set_itunes_metadata(root, ITUNES_METADATA_ITEM_ALBUM_NAME, ITUNES_METADATA_TYPE_STRING, (lsmash_itunes_metadata_t)(char*)[str UTF8String], NULL, NULL);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMARTIST]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMARTIST];
			lsmash_set_itunes_metadata(root, ITUNES_METADATA_ITEM_ALBUM_ARTIST, ITUNES_METADATA_TYPE_STRING, (lsmash_itunes_metadata_t)(char*)[str UTF8String], NULL, NULL);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GENRE]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GENRE];
			lsmash_set_itunes_metadata(root, ITUNES_METADATA_ITEM_USER_GENRE, ITUNES_METADATA_TYPE_STRING, (lsmash_itunes_metadata_t)(char*)[str UTF8String], NULL, NULL);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPOSER]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPOSER];
			lsmash_set_itunes_metadata(root, ITUNES_METADATA_ITEM_COMPOSER, ITUNES_METADATA_TYPE_STRING, (lsmash_itunes_metadata_t)(char*)[str UTF8String], NULL, NULL);
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
			lsmash_set_itunes_metadata_custom(root,ITUNES_METADATA_ITEM_TRACH_NUMBER,0,(void*)[tagData bytes],[tagData length],NULL,NULL);
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
			lsmash_set_itunes_metadata_custom(root,ITUNES_METADATA_ITEM_DISC_NUMBER,0,(void*)[tagData bytes],[tagData length],NULL,NULL);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_DATE]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_DATE];
			lsmash_set_itunes_metadata(root, ITUNES_METADATA_ITEM_RELEASE_DATE, ITUNES_METADATA_TYPE_STRING, (lsmash_itunes_metadata_t)(char*)[str UTF8String], NULL, NULL);
		}
		else if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_YEAR]) {
			NSString *str = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_YEAR] stringValue];
			lsmash_set_itunes_metadata(root, ITUNES_METADATA_ITEM_RELEASE_DATE, ITUNES_METADATA_TYPE_STRING, (lsmash_itunes_metadata_t)(char*)[str UTF8String], NULL, NULL);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMMENT]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMMENT];
			lsmash_set_itunes_metadata(root, ITUNES_METADATA_ITEM_USER_COMMENT, ITUNES_METADATA_TYPE_STRING, (lsmash_itunes_metadata_t)(char*)[str UTF8String], NULL, NULL);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_LYRICS]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_LYRICS];
			lsmash_set_itunes_metadata(root, ITUNES_METADATA_ITEM_LYRICS, ITUNES_METADATA_TYPE_STRING, (lsmash_itunes_metadata_t)(char*)[str UTF8String], NULL, NULL);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GROUP]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GROUP];
			lsmash_set_itunes_metadata(root, ITUNES_METADATA_ITEM_0XA9_GROUPING, ITUNES_METADATA_TYPE_STRING, (lsmash_itunes_metadata_t)(char*)[str UTF8String], NULL, NULL);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TITLESORT]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TITLESORT];
			lsmash_set_itunes_metadata(root, ITUNES_METADATA_ITEM_ITUNES_TITLE_SORT, ITUNES_METADATA_TYPE_STRING, (lsmash_itunes_metadata_t)(char*)[str UTF8String], NULL, NULL);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ARTISTSORT]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ARTISTSORT];
			lsmash_set_itunes_metadata(root, ITUNES_METADATA_ITEM_ITUNES_ARTIST_SORT, ITUNES_METADATA_TYPE_STRING, (lsmash_itunes_metadata_t)(char*)[str UTF8String], NULL, NULL);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMSORT]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMSORT];
			lsmash_set_itunes_metadata(root, ITUNES_METADATA_ITEM_ITUNES_ALBUM_SORT, ITUNES_METADATA_TYPE_STRING, (lsmash_itunes_metadata_t)(char*)[str UTF8String], NULL, NULL);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMARTISTSORT]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_ALBUMARTISTSORT];
			lsmash_set_itunes_metadata(root, ITUNES_METADATA_ITEM_ITUNES_ALBUMARTIST_SORT, ITUNES_METADATA_TYPE_STRING, (lsmash_itunes_metadata_t)(char*)[str UTF8String], NULL, NULL);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPOSERSORT]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPOSERSORT];
			lsmash_set_itunes_metadata(root, ITUNES_METADATA_ITEM_ITUNES_COMPOSER_SORT, ITUNES_METADATA_TYPE_STRING, (lsmash_itunes_metadata_t)(char*)[str UTF8String], NULL, NULL);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPILATION]) {
			if([[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COMPILATION] boolValue]) {
				lsmash_itunes_metadata_t item;
				item.boolean = LSMASH_BOOLEAN_TRUE;
				lsmash_set_itunes_metadata(root, ITUNES_METADATA_ITEM_DISC_COMPILATION, ITUNES_METADATA_TYPE_BOOLEAN, item, NULL, NULL);
			}
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GRACENOTE]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GRACENOTE];
			lsmash_set_itunes_metadata(root, ITUNES_METADATA_ITEM_CUSTOM, ITUNES_METADATA_TYPE_STRING, (lsmash_itunes_metadata_t)(char*)[str UTF8String], "com.apple.iTunes", "iTunes_CDDB_IDs");
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GRACENOTE2]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GRACENOTE2];
			lsmash_set_itunes_metadata(root, ITUNES_METADATA_ITEM_CUSTOM, ITUNES_METADATA_TYPE_STRING, (lsmash_itunes_metadata_t)(char*)[str UTF8String], "com.apple.iTunes", "iTunes_CDDB_1");
			if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TRACK]) {
				str = [NSString stringWithFormat:@"%d",[[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_TRACK] intValue]];
				lsmash_set_itunes_metadata(root, ITUNES_METADATA_ITEM_CUSTOM, ITUNES_METADATA_TYPE_STRING, (lsmash_itunes_metadata_t)(char*)[str UTF8String], "com.apple.iTunes", "iTunes_CDDB_TrackNumber");
			}
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_BPM]) {
			lsmash_itunes_metadata_t item;
			item.integer = [[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_BPM] shortValue];
			lsmash_set_itunes_metadata(root, ITUNES_METADATA_ITEM_BEATS_PER_MINUTE, ITUNES_METADATA_TYPE_INTEGER, item, NULL, NULL);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COPYRIGHT]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COPYRIGHT];
			lsmash_set_itunes_metadata(root, ITUNES_METADATA_ITEM_COPYRIGHT, ITUNES_METADATA_TYPE_STRING, (lsmash_itunes_metadata_t)(char*)[str UTF8String], NULL, NULL);
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GAPLESSALBUM]) {
			if([[[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_GAPLESSALBUM] boolValue]) {
				lsmash_itunes_metadata_t item;
				item.boolean = LSMASH_BOOLEAN_TRUE;
				lsmash_set_itunes_metadata(root, ITUNES_METADATA_ITEM_GAPLESS_PLAYBACK, ITUNES_METADATA_TYPE_BOOLEAN, item, NULL, NULL);
			}
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_TRACKID]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_TRACKID];
			lsmash_set_itunes_metadata(root, ITUNES_METADATA_ITEM_CUSTOM, ITUNES_METADATA_TYPE_STRING, (lsmash_itunes_metadata_t)(char*)[str UTF8String], "com.apple.iTunes", "MusicBrainz Track Id");
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMID]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMID];
			lsmash_set_itunes_metadata(root, ITUNES_METADATA_ITEM_CUSTOM, ITUNES_METADATA_TYPE_STRING, (lsmash_itunes_metadata_t)(char*)[str UTF8String], "com.apple.iTunes", "MusicBrainz Album Id");
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ARTISTID]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ARTISTID];
			lsmash_set_itunes_metadata(root, ITUNES_METADATA_ITEM_CUSTOM, ITUNES_METADATA_TYPE_STRING, (lsmash_itunes_metadata_t)(char*)[str UTF8String], "com.apple.iTunes", "MusicBrainz Artist Id");
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMARTISTID]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMARTISTID];
			lsmash_set_itunes_metadata(root, ITUNES_METADATA_ITEM_CUSTOM, ITUNES_METADATA_TYPE_STRING, (lsmash_itunes_metadata_t)(char*)[str UTF8String], "com.apple.iTunes", "MusicBrainz Album Artist Id");
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_DISCID]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_DISCID];
			lsmash_set_itunes_metadata(root, ITUNES_METADATA_ITEM_CUSTOM, ITUNES_METADATA_TYPE_STRING, (lsmash_itunes_metadata_t)(char*)[str UTF8String], "com.apple.iTunes", "MusicBrainz Disc Id");
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_PUID]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_PUID];
			lsmash_set_itunes_metadata(root, ITUNES_METADATA_ITEM_CUSTOM, ITUNES_METADATA_TYPE_STRING, (lsmash_itunes_metadata_t)(char*)[str UTF8String], "com.apple.iTunes", "MusicIP PUID");
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMSTATUS]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMSTATUS];
			lsmash_set_itunes_metadata(root, ITUNES_METADATA_ITEM_CUSTOM, ITUNES_METADATA_TYPE_STRING, (lsmash_itunes_metadata_t)(char*)[str UTF8String], "com.apple.iTunes", "MusicBrainz Album Status");
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMTYPE]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_ALBUMTYPE];
			lsmash_set_itunes_metadata(root, ITUNES_METADATA_ITEM_CUSTOM, ITUNES_METADATA_TYPE_STRING, (lsmash_itunes_metadata_t)(char*)[str UTF8String], "com.apple.iTunes", "MusicBrainz Album Type");
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_RELEASECOUNTRY]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_RELEASECOUNTRY];
			lsmash_set_itunes_metadata(root, ITUNES_METADATA_ITEM_CUSTOM, ITUNES_METADATA_TYPE_STRING, (lsmash_itunes_metadata_t)(char*)[str UTF8String], "com.apple.iTunes", "MusicBrainz Album Release Country");
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_RELEASEGROUPID]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_RELEASEGROUPID];
			lsmash_set_itunes_metadata(root, ITUNES_METADATA_ITEM_CUSTOM, ITUNES_METADATA_TYPE_STRING, (lsmash_itunes_metadata_t)(char*)[str UTF8String], "com.apple.iTunes", "MusicBrainz Release Group Id");
		}
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_WORKID]) {
			NSString *str = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_MB_WORKID];
			lsmash_set_itunes_metadata(root, ITUNES_METADATA_ITEM_CUSTOM, ITUNES_METADATA_TYPE_STRING, (lsmash_itunes_metadata_t)(char*)[str UTF8String], "com.apple.iTunes", "MusicBrainz Work Id");
		}
		
		if([[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COVER]) {
			uint8_t type;
			NSData *imgData = [[(XLDTrack *)track metadata] objectForKey:XLD_METADATA_COVER];
			if([imgData length] >= 8 && 0 == memcmp([imgData bytes], "\x89PNG\x0d\x0a\x1a\x0a", 8))
				type = 0xe;
			else if([imgData length] >= 2 && 0 == memcmp([imgData bytes], "BM", 2))
				type = 0x1b;
			else if([imgData length] >= 3 && 0 == memcmp([imgData bytes], "GIF", 3))
				type = 0xc;
			else type = 0xd;
			lsmash_set_itunes_metadata_custom(root,ITUNES_METADATA_ITEM_COVER_ART,type,(void*)[imgData bytes],[imgData length],NULL,NULL);
		}
		{
			LIB_INFO *info = malloc(sizeof(LIB_INFO)*FDK_MODULE_LAST);
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
			lsmash_set_itunes_metadata(root, ITUNES_METADATA_ITEM_ENCODING_TOOL, ITUNES_METADATA_TYPE_STRING, (lsmash_itunes_metadata_t)(char*)[str UTF8String], NULL, NULL);
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
			sample->prop.random_access_type = ISOM_SAMPLE_RANDOM_ACCESS_TYPE_SYNC;
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
			sample->prop.random_access_type = ISOM_SAMPLE_RANDOM_ACCESS_TYPE_SYNC;
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
		AACENC_InfoStruct info;
		aacEncInfo(encoder,&info);
		char iTunSMPB[256];
		uint32_t delay = info.encoderDelay;
		uint64_t duration = totalFrames;
		if(sbrEnabled) {
			delay = 2048;
			duration /= 2;
		}
		uint32_t padding = (uint32_t)ceil((duration + delay)/1024.0)*1024 - (duration + delay);
		sprintf(iTunSMPB," 00000000 %08X %08X %016llX 00000000 00000000 00000000 00000000 00000000 00000000 00000000 00000000",delay,padding,duration);
		lsmash_set_itunes_metadata(root,ITUNES_METADATA_ITEM_CUSTOM,ITUNES_METADATA_TYPE_STRING,
								   (lsmash_itunes_metadata_t)iTunSMPB,
								   "com.apple.iTunes",
								   "iTunSMPB");
	}
	{
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
		LIB_INFO *info = malloc(sizeof(LIB_INFO)*FDK_MODULE_LAST);
		aacEncGetLibInfo(info);
		int i;
		for(i=0;i<FDK_MODULE_LAST;i++) {
			if(info[i].module_id == FDK_AACENC) break;
		}
		tmp = OSSwapHostToBigInt32(info[i].version);
		free(info);
		[tagData appendBytes:"cdcv" length:4];
		[tagData appendBytes:&tmp length:4];
		lsmash_set_itunes_metadata_custom(root,ITUNES_METADATA_ITEM_CUSTOM,0,(void*)[tagData bytes],[tagData length],"com.apple.iTunes","Encoding Params");
	}
	
	//lsmash_set_free(root,(uint8_t*)[[NSMutableData dataWithCapacity:4096] bytes],4096);
	
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
