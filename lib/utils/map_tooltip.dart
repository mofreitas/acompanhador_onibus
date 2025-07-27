import 'dart:ui';

import 'package:flutter/material.dart';

class CustomMarkerIcon extends StatelessWidget {
  const CustomMarkerIcon({
    super.key,
    required this.numeroCongregacao,
    required this.nomeCongregacao,
    required this.hue
  });

  final String numeroCongregacao;
  final String nomeCongregacao;
  final double hue;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 6.0, horizontal: 6.0),
      decoration: ShapeDecoration(
          color: HSVColor.fromAHSV(1, hue, 0.77, 0.93).toColor(),
          shape: TooltipShapeBorder(arrowArc: 0.0)
      ),
      child: Text("$nomeCongregacao - $numeroCongregacao", style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),),
    );
  }
}

class TooltipShapeBorder extends ShapeBorder {
  final double arrowWidth;
  final double arrowHeight;
  final double arrowArc;
  final double radius;

  const TooltipShapeBorder({
    this.radius = 10.0,
    this.arrowWidth = 20.0,
    this.arrowHeight = 10.0,
    this.arrowArc = 0.0,
  }) : assert(arrowArc <= 1.0 && arrowArc >= 0.0);

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.only(bottom: arrowHeight);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => Path();

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    rect = Rect.fromPoints(rect.topLeft, rect.bottomRight - Offset(0, arrowHeight));
    double x = arrowWidth, y = arrowHeight, r = 1 - arrowArc;
    return Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)))
      ..moveTo(rect.bottomCenter.dx + x / 2, rect.bottomCenter.dy)
      ..relativeLineTo(-x / 2 * r, y * r)
      ..relativeQuadraticBezierTo(-x / 2 * (1 - r), y * (1 - r), -x * (1 - r), 0)
      ..relativeLineTo(-x / 2 * r, -y * r);
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => this;
}
