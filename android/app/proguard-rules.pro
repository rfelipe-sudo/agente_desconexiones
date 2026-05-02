# ── ONNX Runtime ────────────────────────────────────────────────────────────
# El código nativo (libonnxruntime4j_jni.so) usa FindClass("ai/onnxruntime/...")
# con los nombres ORIGINALES. Si R8 los renombra, el JNI no los encuentra.
-keep class ai.onnxruntime.** { *; }
-keepnames class ai.onnxruntime.** { *; }
-dontwarn ai.onnxruntime.**

# ── AWS SDK ──────────────────────────────────────────────────────────────────
-keep class com.amazonaws.** { *; }
-dontwarn com.amazonaws.**

# ── WorkManager ──────────────────────────────────────────────────────────────
-keep class androidx.work.** { *; }
