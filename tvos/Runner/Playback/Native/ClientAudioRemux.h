#ifndef ClientAudioRemux_h
#define ClientAudioRemux_h

#include <stdint.h>

int moonfin_remux_audio_to_hls(const char *inUrl,
                               int audioStreamIndex,
                               const char *outDir,
                               const char *playlistName,
                               double segmentSeconds,
                               volatile int *cancelFlag);

#endif
