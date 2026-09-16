# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }

# Firebase & Google Play Services (Prevent R8 from stripping auth/firestore reflection)
-keepattributes Signature, *Annotation*, EnclosingMethod
-keep public class com.google.firebase.** { *; }
-keep public class com.google.android.gms.** { *; }
-keep public class com.google.protobuf.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Play Core warnings suppression
-dontwarn com.google.android.play.core.**

# App Package & Models (Keep all classes and members in app namespace from obfuscation/shrinking issues)
-keep class com.vamjo.leafyearth.** { *; }
-keepclassmembers class com.vamjo.leafyearth.** {
    *;
}

# Optional / Payment SDK warnings suppression
-dontwarn com.google.android.apps.nbu.paisa.inapp.client.api.PaymentsClient
-dontwarn com.google.android.apps.nbu.paisa.inapp.client.api.Wallet
-dontwarn com.google.android.apps.nbu.paisa.inapp.client.api.WalletUtils
