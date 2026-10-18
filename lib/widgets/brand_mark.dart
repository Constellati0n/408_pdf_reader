import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Simplified version of the original 408真题系统 diamond logo.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) {
    final double square = size * 0.62;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: <Widget>[
          Positioned(
            left: 0,
            top: 0,
            child: Transform.rotate(
              angle: 0.783,
              child: Container(
                width: square,
                height: square,
                decoration: const BoxDecoration(
                  color: kBrandTeal,
                  borderRadius: BorderRadius.all(Radius.circular(3)),
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Transform.rotate(
              angle: 0.783,
              child: Container(
                width: square,
                height: square,
                decoration: const BoxDecoration(
                  color: kBrandGreen,
                  borderRadius: BorderRadius.all(Radius.circular(3)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
