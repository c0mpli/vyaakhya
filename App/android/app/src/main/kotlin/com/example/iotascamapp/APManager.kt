package com.example.iotascamapp

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.Uri
import android.net.wifi.WifiConfiguration
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.annotation.NonNull
import androidx.annotation.Nullable
import androidx.annotation.RequiresApi
import androidx.core.app.ActivityCompat
import java.lang.reflect.Method
import java.math.BigInteger
import java.security.MessageDigest
import java.security.NoSuchAlgorithmException
import java.util.Random
import android.util.Log

class APManager private constructor(context: Context) {
    private val wifiManager: WifiManager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
    private val locationManager: LocationManager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    private val utils = Utils()
    private var reservation: WifiManager.LocalOnlyHotspotReservation? = null
    private var ssid: String? = null
    private var password: String? = null

    companion object {
        private var apManager: APManager? = null

        fun getApManager(@NonNull context: Context): APManager {
            if (apManager == null) {
                apManager = APManager(context)
            }
            return apManager!!
        }

        const val ERROR_GPS_PROVIDER_DISABLED = 0
        const val ERROR_LOCATION_PERMISSION_DENIED = 4
        const val ERROR_DISABLE_HOTSPOT = 1
        const val ERROR_DISABLE_WIFI = 5
        const val ERROR_WRITE_SETTINGS_PERMISSION_REQUIRED = 6
        const val ERROR_UNKNOWN = 3
    }

    fun getSSID(): String? {
        return ssid
    }

    fun getPassword(): String? {
        return password
    }

    fun getUtils(): Utils {
        return utils
    }

    fun turnOnHotspot(context: Context, onSuccessListener: (String, String) -> Unit, onFailureListener: (Int, Exception?) -> Unit) {
        val providerEnabled = locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)

        if (isDeviceConnectedToWifi()) {
            onFailureListener(ERROR_DISABLE_WIFI, null)
            
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (utils.checkLocationPermission(context) && providerEnabled && !isWifiApEnabled()) {
                try {
                    wifiManager.startLocalOnlyHotspot(object : WifiManager.LocalOnlyHotspotCallback() {
                        override fun onStarted(reservation: WifiManager.LocalOnlyHotspotReservation) {
                            super.onStarted(reservation)
                            this@APManager.reservation = reservation
                            try {
                                ssid = reservation.wifiConfiguration?.SSID
                                password = reservation.wifiConfiguration?.preSharedKey
                                onSuccessListener(ssid ?: "", password ?: "")
                            } catch (e: Exception) {
                                e.printStackTrace()
                                onFailureListener(ERROR_UNKNOWN, e)
                            }
                        }

                        override fun onFailed(reason: Int) {
                            super.onFailed(reason)
                            onFailureListener(if (reason == ERROR_TETHERING_DISALLOWED) ERROR_DISABLE_HOTSPOT else ERROR_UNKNOWN, null)
                        }
                    }, Handler(Looper.getMainLooper()))
                } catch (e: Exception) {
                    onFailureListener(ERROR_UNKNOWN, e)
                }
            } else if (!providerEnabled) {
                onFailureListener(ERROR_GPS_PROVIDER_DISABLED, null)
            } else if (isWifiApEnabled()) {
                onFailureListener(ERROR_DISABLE_HOTSPOT, null)
            } else {
                onFailureListener(ERROR_LOCATION_PERMISSION_DENIED, null)
            }
        } else {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                if (!utils.checkLocationPermission(context)) {
                    onFailureListener(ERROR_LOCATION_PERMISSION_DENIED, null)
                    return
                }
                if (!utils.checkWriteSettingPermission(context)) {
                    onFailureListener(ERROR_WRITE_SETTINGS_PERMISSION_REQUIRED, null)
                    return
                }
            }
            try {
                ssid = "AndroidAP_" + Random().nextInt(10000)
                password = getRandomPassword()
                val wifiConfiguration = WifiConfiguration()
                wifiConfiguration.SSID = ssid
                wifiConfiguration.preSharedKey = password
                wifiConfiguration.allowedAuthAlgorithms.set(WifiConfiguration.AuthAlgorithm.SHARED)
                wifiConfiguration.allowedProtocols.set(WifiConfiguration.Protocol.RSN)
                wifiConfiguration.allowedProtocols.set(WifiConfiguration.Protocol.WPA)
                wifiConfiguration.allowedKeyManagement.set(WifiConfiguration.KeyMgmt.WPA_PSK)
                wifiManager.isWifiEnabled = false
                setWifiApEnabled(wifiConfiguration, true)
                onSuccessListener(ssid ?: "", password ?: "")
            } catch (e: Exception) {
                e.printStackTrace()
                onFailureListener(ERROR_LOCATION_PERMISSION_DENIED, e)
            }
        }
    }

    // fun turnOnHotspot(context: Context, onSuccessListener: (String, String) -> Unit, onFailureListener: (Int, Exception?) -> Unit) {
    //     val providerEnabled = locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)

    //     if (isDeviceConnectedToWifi()) {
    //         Log.d("APManager.kt","wifi is on")
    //         onFailureListener(ERROR_DISABLE_WIFI, null)
    //         return
    //     }

    //     if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
    //         if (!utils.checkLocationPermission(context)) {
    //             Log.d("APManager.kt","loc permisson denied")
    //             onFailureListener(ERROR_LOCATION_PERMISSION_DENIED, null)
    //             return
    //         }
    //         if (!utils.checkWriteSettingPermission(context)) {
    //             Log.d("APManager.kt","write setting permisson denied")
    //             onFailureListener(ERROR_WRITE_SETTINGS_PERMISSION_REQUIRED, null)
    //             return
    //         }
    //     }

    //     try {
    //         ssid = "AndroidAP_" + Random().nextInt(10000)
    //         password = getRandomPassword()
    //         val wifiConfiguration = WifiConfiguration().apply {
    //             SSID = "\"$ssid\""
    //             preSharedKey = "\"$password\""
    //             allowedAuthAlgorithms.set(WifiConfiguration.AuthAlgorithm.SHARED)
    //             allowedProtocols.set(WifiConfiguration.Protocol.RSN)
    //             allowedProtocols.set(WifiConfiguration.Protocol.WPA)
    //             allowedKeyManagement.set(WifiConfiguration.KeyMgmt.WPA_PSK)
    //         }

    //         wifiManager.isWifiEnabled = false
    //         setWifiApEnabled(wifiConfiguration, true)
    //         Log.d("APManager.kt" , "hotspot is on")

    //         onSuccessListener(ssid ?: "", password ?: "")
    //     } catch (e: Exception) {
    //         e.printStackTrace()
    //         onFailureListener(ERROR_LOCATION_PERMISSION_DENIED, e)
    //     }
    // }


    fun disableWifiAp() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                reservation?.close()
            } else {
                setWifiApEnabled(null, false)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun isWifiApEnabled(): Boolean {
        return try {
            val method = wifiManager.javaClass.getMethod("isWifiApEnabled")
            method.invoke(wifiManager) as Boolean
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    fun isDeviceConnectedToWifi(): Boolean {
        return wifiManager.dhcpInfo.ipAddress != 0
    }

    @Throws(Exception::class)
    private fun setWifiApEnabled(wifiConfiguration: WifiConfiguration?, enable: Boolean) {
        val method = wifiManager.javaClass.getMethod("setWifiApEnabled", WifiConfiguration::class.java, Boolean::class.javaPrimitiveType)
        method.invoke(wifiManager, wifiConfiguration, enable)
    }

    private fun getRandomPassword(): String {
        return try {
            val ms = MessageDigest.getInstance("MD5")
            val bytes = ByteArray(10)
            Random().nextBytes(bytes)
            val digest = ms.digest(bytes)
            val bigInteger = BigInteger(1, digest)
            bigInteger.toString(16).substring(0, 10)
        } catch (e: NoSuchAlgorithmException) {
            e.printStackTrace()
            "jfs82433#$2"
        }
    }

    class Utils {
        fun checkLocationPermission(context: Context): Boolean {
            return ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        }

        fun askLocationPermission(activity: Activity, requestCode: Int) {
            ActivityCompat.requestPermissions(activity, arrayOf(Manifest.permission.ACCESS_FINE_LOCATION), requestCode)
        }

        @RequiresApi(Build.VERSION_CODES.M)
        fun askWriteSettingPermission(@NonNull activity: Activity) {
            val intent = Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS)
            intent.data = Uri.parse("package:" + activity.packageName)
            activity.startActivity(intent)
        }

        @RequiresApi(Build.VERSION_CODES.M)
        fun checkWriteSettingPermission(@NonNull context: Context): Boolean {
            return Settings.System.canWrite(context)
        }

        fun getTetheringSettingIntent(): Intent {
            val intent = Intent()
            intent.setClassName("com.android.settings", "com.android.settings.TetherSettings")
            return intent
        }

        fun askForGpsProvider(activity: Activity) {
            val intent = Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)
            activity.startActivity(intent)
        }

        fun askForDisableWifi(activity: Activity) {
            activity.startActivity(Intent(Settings.ACTION_WIFI_SETTINGS))
        }
    }
}
