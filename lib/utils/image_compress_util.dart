import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Comprime una imagen a JPEG y devuelve base64 (para guardar en Supabase).
class ImageCompressUtil {
  ImageCompressUtil._();

  static Future<Map<String, dynamic>?> fileToCompressedPayload(
    String path, {
    String? label,
    int maxWidth = 1024,
    int quality = 65,
  }) async {
    try {
      final raw = await File(path).readAsBytes();
      final payload = bytesToCompressedPayload(
        raw,
        label: label,
        maxWidth: maxWidth,
        quality: quality,
      );
      return payload;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? bytesToCompressedPayload(
    Uint8List raw, {
    String? label,
    int maxWidth = 1024,
    int quality = 65,
  }) {
    final decoded = img.decodeImage(raw);
    if (decoded == null) return null;

    img.Image processed = decoded;
    if (decoded.width > maxWidth) {
      processed = img.copyResize(decoded, width: maxWidth);
    }

    final jpeg = img.encodeJpg(processed, quality: quality);
    return {
      if (label != null) 'label': label,
      'mime': 'image/jpeg',
      'ancho': processed.width,
      'alto': processed.height,
      'bytes_originales': raw.length,
      'bytes_comprimidos': jpeg.length,
      'data_base64': base64Encode(jpeg),
    };
  }

  /// Decodifica bytes desde un payload jsonb guardado en Supabase.
  static Uint8List? bytesFromPayload(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    final b64 = payload['data_base64'] as String?;
    if (b64 == null || b64.isEmpty) return null;
    try {
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  /// Convierte lista de paths locales a JSON listo para jsonb en Supabase.
  static Future<List<Map<String, dynamic>>> pathsToCompressedList(
    Iterable<String> paths, {
    String prefix = 'foto',
  }) async {
    final out = <Map<String, dynamic>>[];
    var i = 0;
    for (final path in paths) {
      i++;
      final item = await fileToCompressedPayload(path, label: '${prefix}_$i');
      if (item != null) out.add(item);
    }
    return out;
  }
}
