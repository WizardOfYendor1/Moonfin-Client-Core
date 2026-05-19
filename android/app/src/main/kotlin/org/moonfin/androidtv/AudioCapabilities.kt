package org.moonfin.androidtv

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.os.Build

object AudioCapabilities {
    private val baselineCapabilities = mapOf(
        "supportsAc3" to false,
        "supportsDts" to false,
        "supportsTrueHd" to false,
        "supportsPcm" to true,
        "supportsAac" to true,
    )

    private fun isBitstreamOutputDevice(device: AudioDeviceInfo): Boolean {
        return when (device.type) {
            AudioDeviceInfo.TYPE_HDMI,
            AudioDeviceInfo.TYPE_HDMI_ARC,
            AudioDeviceInfo.TYPE_LINE_DIGITAL,
            -> true
            else -> Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                device.type == AudioDeviceInfo.TYPE_HDMI_EARC
        }
    }

    fun query(context: Context): Map<String, Boolean> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return baselineCapabilities
        }

        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            ?: return baselineCapabilities

        val encodings = audioManager
            .getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            .asSequence()
            .filter(::isBitstreamOutputDevice)
            .flatMap { device -> device.encodings.asSequence() }
            .toSet()

        if (encodings.isEmpty()) {
            return baselineCapabilities
        }

        val supportsAc3 = encodings.contains(AudioFormat.ENCODING_AC3) ||
            encodings.contains(AudioFormat.ENCODING_E_AC3)
        val supportsDts = encodings.contains(AudioFormat.ENCODING_DTS) ||
            encodings.contains(AudioFormat.ENCODING_DTS_HD)
        val supportsTrueHd = encodings.contains(AudioFormat.ENCODING_DOLBY_TRUEHD)

        return mapOf(
            "supportsAc3" to supportsAc3,
            "supportsDts" to supportsDts,
            "supportsTrueHd" to supportsTrueHd,
            "supportsPcm" to true,
            "supportsAac" to true,
        )
    }
}
