import 'package:flutter/material.dart';

class AppAssets {
  AppAssets._();

  static const String logo = 'assets/images/gemma_edu_logo.png';
  static const String hero = 'assets/images/gemma_edu_hero.png';
  static const String mascot = 'assets/images/mascot.png';
  static const String profile = 'assets/images/profile_avatar.png';
}

class SafeAssetImage extends StatelessWidget {
  final String path;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget fallback;

  const SafeAssetImage({
    super.key,
    required this.path,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    required this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      path,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => SizedBox(
        width: width,
        height: height,
        child: Center(child: fallback),
      ),
    );
  }
}
