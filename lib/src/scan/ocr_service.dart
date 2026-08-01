import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'
    as mlkit;

import 'ocr_types.dart';

/// Reads word boxes out of a photo using whatever text recogniser the platform
/// already ships — ML Kit on Android and iOS, Vision on macOS. Nothing is
/// uploaded anywhere.
class OcrService {
  static const MethodChannel _visionChannel = MethodChannel(
    'attendance_tracker/ocr',
  );

  static bool get isSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  static String get unsupportedReason =>
      'Automatic reading is not available on this platform. '
      'You can still place the classes yourself with the photo on screen.';

  static Future<List<OcrWord>> recognise(String imagePath) async {
    if (!isSupported) throw OcrUnavailable(unsupportedReason);
    if (!await File(imagePath).exists()) {
      throw const OcrUnavailable('That image could not be opened.');
    }
    try {
      if (Platform.isMacOS) return await _recogniseWithVision(imagePath);
      return await _recogniseWithMlKit(imagePath);
    } on OcrUnavailable {
      rethrow;
    } on PlatformException catch (error) {
      throw OcrUnavailable(
        error.message ?? 'The text recogniser could not read that photo.',
      );
    } on MissingPluginException {
      throw const OcrUnavailable(
        'The text recogniser is not installed in this build.',
      );
    } catch (error) {
      throw OcrUnavailable('The photo could not be read: $error');
    }
  }

  // ------------------------------------------------------------ Android/iOS
  static Future<List<OcrWord>> _recogniseWithMlKit(String imagePath) async {
    final size = await _imageSize(imagePath);
    if (size == null) {
      throw const OcrUnavailable('That image could not be decoded.');
    }
    final recogniser = mlkit.TextRecognizer(
      script: mlkit.TextRecognitionScript.latin,
    );
    try {
      final result = await recogniser.processImage(
        mlkit.InputImage.fromFilePath(imagePath),
      );
      final words = <OcrWord>[];
      final scaleX = 1 / size.width;
      final scaleY = 1 / size.height;
      for (final block in result.blocks) {
        for (final line in block.lines) {
          for (final element in line.elements) {
            final text = element.text.trim();
            if (text.isEmpty) continue;
            final rect = element.boundingBox;
            words.add(
              OcrWord(
                text,
                TextBox(
                  (rect.left * scaleX).clamp(0.0, 1.0),
                  (rect.top * scaleY).clamp(0.0, 1.0),
                  (rect.right * scaleX).clamp(0.0, 1.0),
                  (rect.bottom * scaleY).clamp(0.0, 1.0),
                ),
              ),
            );
          }
        }
      }
      return words;
    } finally {
      await recogniser.close();
    }
  }

  static Future<({double width, double height})?> _imageSize(
    String path,
  ) async {
    try {
      final bytes = await File(path).readAsBytes();
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final size = (
        width: descriptor.width.toDouble(),
        height: descriptor.height.toDouble(),
      );
      descriptor.dispose();
      buffer.dispose();
      return size.width > 0 && size.height > 0 ? size : null;
    } catch (_) {
      return null;
    }
  }

  // ----------------------------------------------------------------- macOS
  static Future<List<OcrWord>> _recogniseWithVision(String imagePath) async {
    final raw = await _visionChannel.invokeListMethod<Object?>('recognise', {
      'path': imagePath,
    });
    if (raw == null) {
      throw const OcrUnavailable('The text recogniser returned nothing.');
    }
    final words = <OcrWord>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final text = (entry['text'] as String?)?.trim();
      if (text == null || text.isEmpty) continue;
      final left = (entry['left'] as num?)?.toDouble();
      final top = (entry['top'] as num?)?.toDouble();
      final right = (entry['right'] as num?)?.toDouble();
      final bottom = (entry['bottom'] as num?)?.toDouble();
      if (left == null || top == null || right == null || bottom == null) {
        continue;
      }
      words.add(OcrWord(text, TextBox(left, top, right, bottom)));
    }
    return words;
  }
}
