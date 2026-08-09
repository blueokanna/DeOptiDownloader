pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // AGP 9 enables "built-in Kotlin" by default, which breaks this plugin
    // mix: file_picker 11.x conditionally skips KGP under AGP 9 (expecting
    // built-in Kotlin) while camera_android_camerax / share_plus /
    // wakelock_plus / package_info_plus still require classic KGP. AGP 8.x
    // keeps the classic KGP path working for every plugin.
    id("com.android.application") version "8.13.0" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

include(":app")
