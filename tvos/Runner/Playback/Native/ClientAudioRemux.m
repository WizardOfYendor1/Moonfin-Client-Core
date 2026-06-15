#import "ClientAudioRemux.h"

#include <stdio.h>

@import Libavformat;
@import Libavcodec;
@import Libavutil;

int moonfin_remux_audio_to_hls(const char *inUrl,
                               int audioStreamIndex,
                               const char *outDir,
                               const char *playlistName,
                               double segmentSeconds,
                               volatile int *cancelFlag) {
    AVFormatContext *ifmt = NULL;
    AVFormatContext *ofmt = NULL;
    AVPacket *pkt = NULL;
    AVDictionary *opts = NULL;
    AVStream *inStream = NULL;
    AVStream *outStream = NULL;
    int ret = 0;
    int audioIdx = audioStreamIndex;
    char playlistPath[4096];
    char segPattern[4096];
    char segDur[32];
    int64_t firstPts = AV_NOPTS_VALUE;
    int64_t startWall = 0;
    const double leadSeconds = 3.0;

    if ((ret = avformat_open_input(&ifmt, inUrl, NULL, NULL)) < 0) goto end;
    if ((ret = avformat_find_stream_info(ifmt, NULL)) < 0) goto end;

    if (audioIdx < 0) {
        audioIdx = av_find_best_stream(ifmt, AVMEDIA_TYPE_AUDIO, -1, -1, NULL, 0);
        if (audioIdx < 0) { ret = audioIdx; goto end; }
    }
    if (audioIdx >= (int)ifmt->nb_streams) { ret = AVERROR(EINVAL); goto end; }
    inStream = ifmt->streams[audioIdx];
    if (inStream->codecpar->codec_type != AVMEDIA_TYPE_AUDIO) {
        audioIdx = av_find_best_stream(ifmt, AVMEDIA_TYPE_AUDIO, -1, -1, NULL, 0);
        if (audioIdx < 0) { ret = AVERROR(EINVAL); goto end; }
        inStream = ifmt->streams[audioIdx];
    }

    for (unsigned i = 0; i < ifmt->nb_streams; i++) {
        ifmt->streams[i]->discard = (i == (unsigned)audioIdx) ? AVDISCARD_DEFAULT : AVDISCARD_ALL;
    }

    snprintf(playlistPath, sizeof(playlistPath), "%s/%s", outDir, playlistName);
    snprintf(segPattern, sizeof(segPattern), "%s/seg%%d.m4s", outDir);
    snprintf(segDur, sizeof(segDur), "%g", segmentSeconds > 0 ? segmentSeconds : 4.0);

    if ((ret = avformat_alloc_output_context2(&ofmt, NULL, "hls", playlistPath)) < 0) goto end;

    outStream = avformat_new_stream(ofmt, NULL);
    if (!outStream) { ret = AVERROR(ENOMEM); goto end; }
    if ((ret = avcodec_parameters_copy(outStream->codecpar, inStream->codecpar)) < 0) goto end;
    outStream->codecpar->codec_tag = 0;

    av_dict_set(&opts, "hls_segment_type", "fmp4", 0);
    av_dict_set(&opts, "hls_time", segDur, 0);
    av_dict_set(&opts, "hls_list_size", "0", 0);
    av_dict_set(&opts, "hls_playlist_type", "event", 0);
    av_dict_set(&opts, "hls_flags", "independent_segments+temp_file", 0);
    av_dict_set(&opts, "hls_fmp4_init_filename", "init.mp4", 0);
    av_dict_set(&opts, "hls_segment_filename", segPattern, 0);

    if ((ret = avformat_write_header(ofmt, &opts)) < 0) goto end;

    pkt = av_packet_alloc();
    if (!pkt) { ret = AVERROR(ENOMEM); goto end; }

    while (av_read_frame(ifmt, pkt) >= 0) {
        if (cancelFlag && *cancelFlag) { av_packet_unref(pkt); break; }
        if (pkt->stream_index == audioIdx) {
            if (pkt->pts != AV_NOPTS_VALUE) {
                if (firstPts == AV_NOPTS_VALUE) { firstPts = pkt->pts; startWall = av_gettime(); }
                double mediaSec = (double)(pkt->pts - firstPts) * av_q2d(inStream->time_base);
                while (!(cancelFlag && *cancelFlag)) {
                    double wallSec = (double)(av_gettime() - startWall) / 1e6;
                    if (mediaSec - wallSec <= leadSeconds) break;
                    av_usleep(100000);
                }
            }
            pkt->stream_index = 0;
            av_packet_rescale_ts(pkt, inStream->time_base, outStream->time_base);
            pkt->pos = -1;
            ret = av_interleaved_write_frame(ofmt, pkt);
            if (ret < 0) break;
        } else {
            av_packet_unref(pkt);
        }
    }

    av_write_trailer(ofmt);

end:
    if (opts) av_dict_free(&opts);
    if (pkt) av_packet_free(&pkt);
    if (ofmt) avformat_free_context(ofmt);
    if (ifmt) avformat_close_input(&ifmt);
    return ret;
}
