import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../core/money.dart';

/// Karte mit runden Ecken und optionalem Titel.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, this.trailing, required this.child, this.padding = const EdgeInsets.all(20)});

  final String? title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null) ...[
              Padding(
                // Bei Karten mit wenig Rand (Listen) steht der Titel trotzdem bündig.
                padding: EdgeInsets.symmetric(horizontal: math.max(0, 16 - padding.left)),
                child: Row(
                  children: [
                    Expanded(child: Text(title!, style: Theme.of(context).textTheme.titleMedium)),
                    ?trailing,
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// Betrag in CHF, Einnahmen grün, Ausgaben pink (mit Vorzeichen).
class AmountText extends StatelessWidget {
  const AmountText(this.rappen, {super.key, this.style, this.colored = true, this.sign = true});

  final int rappen;
  final TextStyle? style;
  final bool colored;
  final bool sign;

  @override
  Widget build(BuildContext context) {
    final c = context.conti;
    final color = !colored || rappen == 0 ? null : (rappen > 0 ? c.plus : c.minus);
    return Text(
      Money.format(rappen, sign: sign),
      style: (style ?? Theme.of(context).textTheme.bodyLarge)?.copyWith(
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

/// Grosse, feine Zahl (z. B. Gewinn auf der Startseite).
class BigNumber extends StatelessWidget {
  const BigNumber(this.text, {super.key, this.size = 40});
  final String text;
  final double size;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w300,
      height: 1.05,
      letterSpacing: -0.5,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );
}

/// Kleine Überschrift in Grossbuchstaben („EINNAHMEN“).
class CapsLabel extends StatelessWidget {
  const CapsLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: context.conti.muted, letterSpacing: 1.2),
  );
}

/// Ring mit Farbverlauf, [value] 0..1.
class GradientRing extends StatelessWidget {
  const GradientRing({super.key, required this.value, required this.colors, this.size = 92, this.stroke = 9, this.label});

  final double value;
  final List<Color> colors;
  final double size;
  final double stroke;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(value.clamp(0, 1).toDouble(), colors, context.conti.track, stroke),
        child: label == null
            ? null
            : Center(
                child: Text(
                  label!,
                  style: TextStyle(fontSize: size * 0.18, fontWeight: FontWeight.w300),
                ),
              ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.colors, this.track, this.stroke);
  final double value;
  final List<Color> colors;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    canvas.drawArc(
      r,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    if (value <= 0) return;
    final sweep = math.pi * 2 * value;
    final paint = Paint()
      ..shader = SweepGradient(
        colors: colors,
        startAngle: 0,
        endAngle: math.max(sweep, 0.01),
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(r, -math.pi / 2, sweep, false, paint);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.colors != colors || old.track != track;
}

/// Waagrechter Balken mit Verlauf, [value] 0..1.
class GradientBar extends StatelessWidget {
  const GradientBar({super.key, required this.value, required this.colors, this.height = 8});

  final double value;
  final List<Color> colors;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: context.conti.track)),
            Positioned.fill(
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: value.clamp(0, 1).toDouble(),
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: colors),
                    borderRadius: BorderRadius.circular(height / 2),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Knopf mit Farbverlauf (Hauptaktion).
class GradientButton extends StatelessWidget {
  const GradientButton({super.key, required this.label, required this.onPressed, this.icon, this.colors});

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final List<Color>? colors;

  @override
  Widget build(BuildContext context) {
    final c = colors ?? context.conti.pink;
    final onColor = Theme.of(context).brightness == Brightness.dark ? const Color(0xFF14081F) : Colors.white;
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: LinearGradient(colors: c), borderRadius: BorderRadius.circular(999)),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[Icon(icon, size: 20, color: onColor), const SizedBox(width: 8)],
                  Text(
                    label,
                    style: TextStyle(color: onColor, fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Schwebender Knopf unten rechts mit Verlauf (z. B. „+ Buchung“).
class GradientFab extends StatelessWidget {
  const GradientFab({super.key, required this.label, required this.icon, required this.onPressed});

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final glow = context.conti.pink.last.withValues(alpha: 0.35);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        boxShadow: [BoxShadow(color: glow, blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: GradientButton(label: label, icon: icon, onPressed: onPressed),
    );
  }
}

/// Monatsbalken: Einnahmen (Mint-Blau) und Ausgaben (Gelb-Pink) pro Monat.
class MonthBars extends StatelessWidget {
  const MonthBars({super.key, required this.income, required this.expenses, required this.labels, this.height = 160});

  final List<int> income;
  final List<int> expenses;
  final List<String> labels;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.conti;
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _BarsPainter(
          income,
          expenses,
          labels,
          c.mint,
          c.sun,
          c.line,
          Theme.of(context).textTheme.labelSmall!.copyWith(color: c.muted),
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.income, this.expenses, this.labels, this.inC, this.exC, this.line, this.labelStyle);
  final List<int> income, expenses;
  final List<String> labels;
  final List<Color> inC, exC;
  final Color line;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    const labelH = 18.0;
    final chartH = size.height - labelH;
    final maxV = [...income, ...expenses, 1].reduce(math.max).toDouble();
    final n = income.length;
    final slot = size.width / n;
    final barW = math.min(10.0, slot * 0.28);
    canvas.drawLine(Offset(0, chartH), Offset(size.width, chartH), Paint()..color = line);
    for (var i = 0; i < n; i++) {
      final x = slot * i + slot / 2;
      void bar(double dx, int v, List<Color> colors) {
        if (v <= 0) return;
        final h = math.max(3.0, chartH * (v / maxV));
        final r = RRect.fromRectAndCorners(
          Rect.fromLTWH(x + dx - barW / 2, chartH - h, barW, h),
          topLeft: Radius.circular(barW / 2),
          topRight: Radius.circular(barW / 2),
        );
        canvas.drawRRect(
          r,
          Paint()
            ..shader = LinearGradient(
              colors: colors,
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ).createShader(r.outerRect),
        );
      }

      bar(-barW * 0.65, income[i], inC);
      bar(barW * 0.65, expenses[i], exC);
      final tp = TextPainter(
        text: TextSpan(text: labels[i], style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      if (slot > tp.width + 2 || i.isEven) {
        tp.paint(canvas, Offset(x - tp.width / 2, chartH + 4));
      }
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.income != income || old.expenses != expenses || old.inC != inC;
}

/// Kleines Conti-Zeichen: Quadrat mit Verlauf und einem „C“.
class ContiMark extends StatelessWidget {
  const ContiMark({super.key, this.size = 36});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: context.conti.pink, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      alignment: Alignment.center,
      child: Text(
        'C',
        style: TextStyle(
          fontFamily: fontDisplay,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.56,
          color: Colors.white,
          height: 1,
        ),
      ),
    );
  }
}

/// Leerer Zustand mit Symbol, Titel und Erklärung.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.text, this.action});
  final IconData icon;
  final String title;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShaderMask(
              shaderCallback: (r) => LinearGradient(colors: context.conti.pink).createShader(r),
              child: Icon(icon, size: 56, color: Colors.white),
            ),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.conti.muted),
              ),
            ),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}
