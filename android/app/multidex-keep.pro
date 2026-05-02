# Fuerza las clases de ONNX Runtime al DEX primario.
# Sin esto, el código JNI nativo no puede encontrar OrtException
# desde hilos de fondo (usa bootstrap class loader, no el de la app).
-keep class ai.onnxruntime.** { *; }
