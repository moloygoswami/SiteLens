package com.sitelens.app

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.GnssStatus
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.sitelens.app/gnss"
    private var locationManager: LocationManager? = null
    private var gnssCallback: GnssStatus.Callback? = null
    private var latestGnssStatus: GnssStatus? = null
    private var lastGnssTimestamp: Long = 0L
    private var isCallbackRegistered: Boolean = false
    private var locationListener: android.location.LocationListener? = null
    private var latestLocation: android.location.Location? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        locationManager = getSystemService(Context.LOCATION_SERVICE) as? LocationManager

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getGnssStatus" -> {
                    handleGetGnssStatus(result)
                }
                "startGnssUpdates" -> {
                    startGnssUpdates()
                    result.success(true)
                }
                "stopGnssUpdates" -> {
                    stopGnssUpdates()
                    result.success(true)
                }
                "getAltitudeTelemetry" -> {
                    handleGetAltitudeTelemetry(result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // Attempt initial registration if permission is already granted
        startGnssUpdates()
    }

    private fun startGnssUpdates() {
        val permission = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION)
        if (permission != PackageManager.PERMISSION_GRANTED) return

        if (locationListener == null) {
            locationListener = android.location.LocationListener { loc ->
                latestLocation = loc
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    locationManager?.requestLocationUpdates(
                        LocationManager.FUSED_PROVIDER,
                        1000L,
                        0f,
                        locationListener!!,
                        Looper.getMainLooper()
                    )
                } else {
                    locationManager?.requestLocationUpdates(
                        LocationManager.GPS_PROVIDER,
                        1000L,
                        0f,
                        locationListener!!,
                        Looper.getMainLooper()
                    )
                }
            } catch (_: Exception) {}
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
        if (isCallbackRegistered) return

        if (gnssCallback == null) {
            gnssCallback = object : GnssStatus.Callback() {
                override fun onSatelliteStatusChanged(status: GnssStatus) {
                    latestGnssStatus = status
                    lastGnssTimestamp = System.currentTimeMillis()
                }
            }
        }

        try {
            gnssCallback?.let { callback ->
                locationManager?.registerGnssStatusCallback(callback, Handler(Looper.getMainLooper()))
                isCallbackRegistered = true
            }
        } catch (_: SecurityException) {
            isCallbackRegistered = false
        } catch (_: Exception) {
            isCallbackRegistered = false
        }
    }

    private fun stopGnssUpdates() {
        locationListener?.let {
            try {
                locationManager?.removeUpdates(it)
            } catch (_: Exception) {}
        }
        locationListener = null

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
        if (!isCallbackRegistered) return

        gnssCallback?.let { callback ->
            try {
                locationManager?.unregisterGnssStatusCallback(callback)
            } catch (_: Exception) {}
        }
        isCallbackRegistered = false
    }

    private fun handleGetGnssStatus(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            result.success(mapOf(
                "isSupported" to false,
                "isAvailable" to false,
                "satelliteCount" to 0,
                "satellitesUsedInFix" to 0,
                "constellations" to emptyMap<String, Any>(),
                "timestampMillis" to null
            ))
            return
        }

        // Try to start updates if not already registered
        if (!isCallbackRegistered) {
            startGnssUpdates()
        }

        val status = latestGnssStatus
        if (status == null) {
            result.success(mapOf(
                "isSupported" to true,
                "isAvailable" to false,
                "satelliteCount" to 0,
                "satellitesUsedInFix" to 0,
                "constellations" to emptyMap<String, Any>(),
                "timestampMillis" to null
            ))
            return
        }

        val count = status.satelliteCount
        var usedInFixCount = 0
        val constellationMap = mutableMapOf<String, MutableMap<String, Int>>()

        for (i in 0 until count) {
            val cType = status.getConstellationType(i)
            val cName = getConstellationName(cType)
            val used = status.usedInFix(i)

            if (used) {
                usedInFixCount++
            }

            val summary = constellationMap.getOrPut(cName) {
                mutableMapOf("tracked" to 0, "usedInFix" to 0)
            }
            summary["tracked"] = (summary["tracked"] ?: 0) + 1
            if (used) {
                summary["usedInFix"] = (summary["usedInFix"] ?: 0) + 1
            }
        }

        result.success(mapOf(
            "isSupported" to true,
            "isAvailable" to true,
            "satelliteCount" to count,
            "satellitesUsedInFix" to usedInFixCount,
            "constellations" to constellationMap,
            "timestampMillis" to lastGnssTimestamp
        ))
    }

    private fun getConstellationName(constellationType: Int): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            when (constellationType) {
                GnssStatus.CONSTELLATION_GPS -> "gps"
                GnssStatus.CONSTELLATION_SBAS -> "sbas"
                GnssStatus.CONSTELLATION_GLONASS -> "glonass"
                GnssStatus.CONSTELLATION_QZSS -> "qzss"
                GnssStatus.CONSTELLATION_BEIDOU -> "beidou"
                GnssStatus.CONSTELLATION_GALILEO -> "galileo"
                GnssStatus.CONSTELLATION_IRNSS -> "irnss"
                else -> "unknown"
            }
        } else {
            "unknown"
        }
    }

    private fun handleGetAltitudeTelemetry(result: MethodChannel.Result) {
        val permission = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION)
        if (permission != PackageManager.PERMISSION_GRANTED) {
            result.success(mapOf(
                "hasMslAltitude" to false,
                "mslAltitudeMeters" to null,
                "wgs84AltitudeMeters" to null
            ))
            return
        }

        try {
            val loc = latestLocation
                ?: (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    locationManager?.getLastKnownLocation(LocationManager.FUSED_PROVIDER)
                        ?: locationManager?.getLastKnownLocation(LocationManager.GPS_PROVIDER)
                } else {
                    locationManager?.getLastKnownLocation(LocationManager.GPS_PROVIDER)
                })

            if (loc == null) {
                result.success(mapOf(
                    "hasMslAltitude" to false,
                    "mslAltitudeMeters" to null,
                    "wgs84AltitudeMeters" to null
                ))
                return
            }

            val hasMsl = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                loc.hasMslAltitude()
            } else {
                false
            }

            val mslAltitude = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE && hasMsl) {
                loc.mslAltitudeMeters
            } else {
                null
            }

            val wgs84Altitude = if (loc.hasAltitude()) loc.altitude else null

            result.success(mapOf(
                "hasMslAltitude" to hasMsl,
                "mslAltitudeMeters" to mslAltitude,
                "wgs84AltitudeMeters" to wgs84Altitude
            ))
        } catch (_: Exception) {
            result.success(mapOf(
                "hasMslAltitude" to false,
                "mslAltitudeMeters" to null,
                "wgs84AltitudeMeters" to null
            ))
        }
    }

    override fun onResume() {
        super.onResume()
        startGnssUpdates()
    }

    override fun onDestroy() {
        stopGnssUpdates()
        super.onDestroy()
    }
}
