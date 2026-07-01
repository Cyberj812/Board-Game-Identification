import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

class OcrService {
  final TextRecognizer _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  Future<String> extractText(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    final recognizedText = await _recognizer.processImage(inputImage);

    final buffer = StringBuffer();
    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        buffer.writeln(line.text);
      }
    }
    return buffer.toString().trim();
  }

  /// Extract a representative dominant color (average of sampled pixels) for box art color matching.
  /// Returns 0xAARRGGBB int suitable for Color(value).
  Future<int> extractDominantColorInt(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return 0xFF888888;

      // Resize small for speed + average sample
      final small = img.copyResize(decoded, width: 64);
      int r = 0, g = 0, b = 0, count = 0;
      const step = 4; // sample stride

      for (int y = 0; y < small.height; y += step) {
        for (int x = 0; x < small.width; x += step) {
          final p = small.getPixel(x, y);
          r += p.r.toInt();
          g += p.g.toInt();
          b += p.b.toInt();
          count++;
        }
      }
      if (count == 0) return 0xFF888888;
      final avgR = (r / count).round().clamp(0, 255);
      final avgG = (g / count).round().clamp(0, 255);
      final avgB = (b / count).round().clamp(0, 255);
      return (0xFF << 24) | (avgR << 16) | (avgG << 8) | avgB;
    } catch (_) {
      return 0xFF888888;
    }
  }

  void dispose() {
    _recognizer.close();
  }
}
