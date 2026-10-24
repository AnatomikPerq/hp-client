import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Звёздное поле за кнопкой подключения.
///
/// Анимации здесь только конечные: при подключении поле плавно теплеет и
/// разгорается, при отключении остывает. Постоянного мерцания нет намеренно:
/// окно клиента часто висит открытым часами, и бесконечная анимация тратила
/// бы процессор ради фона.
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
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    value: widget.active ? 1 : 0,
  );
  List<_Star> _stars = const [];
  Size _lastSize = Size.zero;

  @override
  void didUpdateWidget(covariant Starfield oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active == widget.active) return;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final target = widget.active ? 1.0 : 0.0;
    if (reduceMotion) {
      _glow.value = target;
    } else {
      _glow.animateTo(target, curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _glow.dispose();
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
        // Неровная яркость вместо мерцания: поле живое и без анимации.
        brightness: 0.55 + random.nextDouble() * 0.45,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _rebuildStars(constraints.biggest);
        return IgnorePointer(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _glow,
              builder: (context, _) {
                return CustomPaint(
                  size: constraints.biggest,
                  painter: _StarfieldPainter(
                    stars: _stars,
                    glow: _glow.value,
                    idleColor: widget.idleColor,
                    activeColor: widget.activeColor,
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// Орбита вокруг кнопки подключения: тонкое кольцо и спутник на нём.
///
/// Пока идёт подключение, спутник кружит; в момент подключения он плавно
/// доворачивает до точки покоя и останавливается: заметный знак «готово»
/// без постоянного движения на экране. Кружение ограничено самим
/// подключением, как и индикатор в центре кнопки.
class OrbitRing extends StatefulWidget {
  const OrbitRing({
    super.key,
    required this.diameter,
    required this.color,
    required this.active,
    this.spinning = false,
  });

  final double diameter;
  final Color color;
  final bool active;

  /// Подключение идёт: спутник кружит без остановки.
  final bool spinning;

  @override
  State<OrbitRing> createState() => _OrbitRingState();
}

class _OrbitRingState extends State<OrbitRing> with TickerProviderStateMixin {
  /// Положение спутника в покое, в долях оборота.
  static const _rest = 0.12;

  /// Один оборот кружения.
  static const _spinPeriod = Duration(milliseconds: 1500);

  /// Где спутник стоит, пока ничего не движется.
  double _base = _rest;

  // Доворот до точки покоя: откуда, куда и как.
  double _from = _rest;
  double _to = _rest;
  Curve _curve = Curves.easeInOutCubic;

  late final AnimationController _turn = AnimationController(vsync: this)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) _base = _to % 1;
    });
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: _spinPeriod,
  );

  bool get _reduceMotion =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  double get _position {
    if (_spin.isAnimating) return _base + _spin.value;
    if (_turn.isAnimating) {
      return _from + (_to - _from) * _curve.transform(_turn.value);
    }
    return _base;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduceMotion) {
      _stopSpin();
    } else if (widget.spinning && !_spin.isAnimating) {
      _spin.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant OrbitRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    final reduceMotion = _reduceMotion;
    var fromSpin = false;
    if (widget.spinning && !oldWidget.spinning && !reduceMotion) {
      _stopTurn();
      _spin.repeat();
    } else if (!widget.spinning && oldWidget.spinning) {
      fromSpin = _spin.isAnimating;
      _stopSpin();
    }
    if (widget.active && !oldWidget.active && !reduceMotion) {
      _stopTurn();
      _from = _base;
      // Хотя бы полоборота: иначе остановка выглядит как рывок.
      var to = _rest + 1;
      while (to - _from < 0.5) {
        to += 1;
      }
      _to = to;
      if (fromSpin) {
        // Спутник уже летит: тормозит с той же скорости, без рывка.
        // У easeOutQuad начальная скорость вдвое выше средней.
        _curve = Curves.easeOutQuad;
        _turn.duration = _spinPeriod * (2 * (_to - _from));
      } else {
        _curve = Curves.easeInOutCubic;
        _turn.duration = const Duration(milliseconds: 2400);
      }
      _turn.forward(from: 0);
    }
  }

  void _stopTurn() {
    if (!_turn.isAnimating) return;
    _base = _position % 1;
    _turn.stop();
  }

  void _stopSpin() {
    if (!_spin.isAnimating) return;
    _base = _position % 1;
    _spin
      ..stop()
      ..value = 0;
  }

  @override
  void dispose() {
    _turn.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox.square(
        dimension: widget.diameter,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: Listenable.merge([_turn, _spin]),
            builder: (context, _) {
              return CustomPaint(
                painter: _OrbitPainter(
                  turn: _position,
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
    required this.brightness,
  });

  final double dx;
  final double dy;
  final double radius;
  final double brightness;
}

class _StarfieldPainter extends CustomPainter {
  _StarfieldPainter({
    required this.stars,
    required this.glow,
    required this.idleColor,
    required this.activeColor,
  });

  final List<_Star> stars;

  /// 0 в покое, 1 при поднятом туннеле.
  final double glow;
  final Color idleColor;
  final Color activeColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    final color = Color.lerp(idleColor, activeColor, glow)!;
    final baseAlpha = 0.20 + 0.22 * glow;
    final scale = 1.0 + 0.25 * glow;
    final paint = Paint()..style = PaintingStyle.fill;
    for (final star in stars) {
      paint.color = color.withValues(
        alpha: (baseAlpha * star.brightness).clamp(0.0, 1.0),
      );
      canvas.drawCircle(
        Offset(star.dx * size.width, star.dy * size.height),
        star.radius * scale,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_StarfieldPainter oldDelegate) {
    return oldDelegate.glow != glow ||
        oldDelegate.idleColor != idleColor ||
        oldDelegate.activeColor != activeColor ||
        !identical(oldDelegate.stars, stars);
  }
}
