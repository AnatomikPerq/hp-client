import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Живой фон главного экрана: медленно дрейфующее звёздное поле.
///
/// Мерцание намеренно слабое — фон не должен перетягивать внимание с кнопки.
/// Когда туннель поднят, поле теплеет и слегка разгорается.
class Starfield extends StatefulWidget {
  const Starfield({
    super.key,
    required this.active,
    required this.idleColor,
    required this.activeColor,
    this.density = 1.0,
  });

  /// Туннель поднят: звёзды теплеют и становятся ярче.
  final bool active;
  final Color idleColor;
  final Color activeColor;

  /// Множитель количества звёзд относительно площади.
  final double density;

  @override
  State<Starfield> createState() => _StarfieldState();
}

class _StarfieldState extends State<Starfield>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  List<_Star> _stars = const [];
  Size _lastSize = Size.zero;

  @override
  void initState() {
    super.initState();
    // Длинный цикл: одна фаза дыхания занимает почти две минуты, поэтому
    // движение читается как дрейф, а не как мигание.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 110),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _rebuildStars(Size size) {
    if (size == _lastSize || size.isEmpty) {
      return;
    }
    _lastSize = size;
    // Фиксированное зерно: при изменении размера окна звёзды не
    // перепрыгивают на новые случайные места.
    final random = math.Random(20260813);
    final count = ((size.width * size.height) / 5200 * widget.density)
        .clamp(28, 220)
        .round();
    _stars = List<_Star>.generate(count, (_) {
      return _Star(
        dx: random.nextDouble(),
        dy: random.nextDouble(),
        radius: 0.4 + random.nextDouble() * 1.15,
        phase: random.nextDouble() * math.pi * 2,
        // Разброс скоростей небольшой, иначе поле начинает "кипеть".
        speed: 0.35 + random.nextDouble() * 0.5,
        drift: 0.25 + random.nextDouble() * 0.75,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return LayoutBuilder(
      builder: (context, constraints) {
        _rebuildStars(constraints.biggest);
        return RepaintBoundary(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return CustomPaint(
                size: constraints.biggest,
                painter: _StarfieldPainter(
                  stars: _stars,
                  time: reduceMotion ? 0.25 : _controller.value,
                  active: widget.active,
                  idleColor: widget.idleColor,
                  activeColor: widget.activeColor,
                  animate: !reduceMotion,
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// Орбита вокруг кнопки подключения: тонкое кольцо и спутник на нём.
///
/// Один медленный оборот вместо мигания — движение, за которое глаз
/// цепляется, но которое не мешает.
class OrbitRing extends StatefulWidget {
  const OrbitRing({
    super.key,
    required this.diameter,
    required this.color,
    required this.active,
  });

  final double diameter;
  final Color color;
  final bool active;

  @override
  State<OrbitRing> createState() => _OrbitRingState();
}

class _OrbitRingState extends State<OrbitRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 34),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return IgnorePointer(
      child: SizedBox.square(
        dimension: widget.diameter,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return CustomPaint(
                painter: _OrbitPainter(
                  turn: reduceMotion ? 0.12 : _controller.value,
                  color: widget.color,
                  active: widget.active,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter({
    required this.turn,
    required this.color,
    required this.active,
  });

  final double turn;
  final Color color;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    if (radius <= 0) {
      return;
    }
    // Кольцо рисуется внутрь на радиус спутника, чтобы тот шёл ровно по
    // линии, а не свисал с неё половиной себя.
    const satelliteRadius = 4.5;
    final orbitRadius = radius - satelliteRadius;
    if (orbitRadius <= 0) {
      return;
    }
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = color.withValues(alpha: active ? 0.5 : 0.3);
    canvas.drawCircle(center, orbitRadius, ring);

    final angle = turn * math.pi * 2 - math.pi / 2;
    final satellite = Offset(
      center.dx + math.cos(angle) * orbitRadius,
      center.dy + math.sin(angle) * orbitRadius,
    );
    // Заметный шарик: прежние 2.6px на светящемся фоне просто терялись.
    final glow = Paint()
      ..color = color.withValues(alpha: active ? 0.45 : 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
    canvas.drawCircle(satellite, satelliteRadius * 2, glow);
    canvas.drawCircle(
      satellite,
      satelliteRadius,
      Paint()..color = color.withValues(alpha: active ? 1 : 0.85),
    );
  }

  @override
  bool shouldRepaint(_OrbitPainter oldDelegate) {
    return oldDelegate.turn != turn ||
        oldDelegate.color != color ||
        oldDelegate.active != active;
  }
}

class _Star {
  const _Star({
    required this.dx,
    required this.dy,
    required this.radius,
    required this.phase,
    required this.speed,
    required this.drift,
  });

  final double dx;
  final double dy;
  final double radius;
  final double phase;
  final double speed;
  final double drift;
}

class _StarfieldPainter extends CustomPainter {
  _StarfieldPainter({
    required this.stars,
    required this.time,
    required this.active,
    required this.idleColor,
    required this.activeColor,
    required this.animate,
  });

  final List<_Star> stars;
  final double time;
  final bool active;
  final Color idleColor;
  final Color activeColor;
  final bool animate;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    final color = active ? activeColor : idleColor;
    // Амплитуда мерцания намеренно мала: 0.86..1.0 вместо привычных 0..1.
    const twinkleDepth = 0.14;
    final baseAlpha = active ? 0.42 : 0.20;
    final paint = Paint()..style = PaintingStyle.fill;

    for (final star in stars) {
      final wave = animate
          ? math.sin(time * math.pi * 2 * star.speed + star.phase)
          : 0.0;
      final alpha =
          baseAlpha * (1 - twinkleDepth + twinkleDepth * (wave + 1) / 2);
      // Вертикальный дрейф на пару пикселей за цикл — движение есть,
      // но заметить его можно только если специально смотреть.
      final offsetY = animate ? wave * star.drift : 0.0;
      paint.color = color.withValues(alpha: alpha.clamp(0.0, 1.0));
      canvas.drawCircle(
        Offset(star.dx * size.width, star.dy * size.height + offsetY),
        star.radius * (active ? 1.25 : 1.0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_StarfieldPainter oldDelegate) {
    return oldDelegate.time != time ||
        oldDelegate.active != active ||
        oldDelegate.idleColor != idleColor ||
        oldDelegate.activeColor != activeColor ||
        !identical(oldDelegate.stars, stars);
  }
}
