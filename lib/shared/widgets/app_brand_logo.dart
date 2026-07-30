import 'package:flutter/material.dart';

import '../../app/theme.dart';

class AppBrandLogo extends StatelessWidget {
  const AppBrandLogo({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'CalTrack logo',
      image: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/branding/caltrack-mark.png',
            width: size,
            height: size,
            fit: BoxFit.contain,
            excludeFromSemantics: true,
          ),
          const SizedBox(height: 8),
          Text(
            'CalTrack',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppTheme.onBackground,
            ),
          ),
        ],
      ),
    );
  }
}
