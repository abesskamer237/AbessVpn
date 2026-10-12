package com.abessvpn

import android.os.Bundle
import android.net.TrafficStats
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "abessvpn/traffic"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        MethodChannel(flutterEngine?.dartExecutor?.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getTrafficCounters" -> {
                        try {
                            val uid = applicationInfo.uid
                            val rxBytes = TrafficStats.getUidRxBytes(uid).toLong()
                            val txBytes = TrafficStats.getUidTxBytes(uid).toLong()
                            result.success(mapOf(
                                "rxBytes" to rxBytes,
                                "txBytes" to txBytes,
                            ))
                        } catch (e: Exception) {
                            result.error("TRAFFIC_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
