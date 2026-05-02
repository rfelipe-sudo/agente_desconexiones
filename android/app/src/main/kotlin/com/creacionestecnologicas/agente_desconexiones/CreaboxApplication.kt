package com.creacionestecnologicas.agente_desconexiones

import androidx.multidex.MultiDexApplication

/**
 * Application personalizada que instala MultiDex de forma explícita antes de
 * que cualquier biblioteca nativa (ONNX Runtime, CameraX) intente cargar clases.
 *
 * Sin esto, el thread pool de ONNX Runtime obtiene el bootstrap classloader
 * al llamar FindClass("ai/onnxruntime/OrtException") desde JNI, causando
 * ClassNotFoundException aunque la clase esté correctamente incluida en el DEX.
 */
class CreaboxApplication : MultiDexApplication()
