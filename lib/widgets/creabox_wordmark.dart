import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Wordmark "CREABOX" con gradiente y halo (mismo lenguaje visual que el splash).
class CreaboxWordmark extends StatelessWidget {
  const CreaboxWordmark({
    super.key,
    this.fontSize = 46,
    this.letterSpacing = 5,
  });

  final double fontSize;
  final double letterSpacing;

  static const String _text = 'CREABOX';

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Text(
            _text,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              letterSpacing: letterSpacing,
              color: const Color(0xFF448AFF),
            ),
          ),
        ),
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Text(
            _text,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              letterSpacing: letterSpacing,
              color: const Color(0xFF7C4DFF),
            ),
          ),
        ),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) {
            return const LinearGradient(
              colors: [
                Color(0xFFE9D5FF),
                Color(0xFFE9D5FF),
                Color(0xFF7C4DFF),
                Color(0xFF448AFF),
                Color(0xFF4FC3F7),
              ],
              stops: [0.0, 0.15, 0.4, 0.72, 1.0],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ).createShader(bounds);
          },
          child: Text(
            _text,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              letterSpacing: letterSpacing,
              color: Colors.white,
              height: 1.05,
            ),
          ),
        ),
      ],
    );
  }
}
