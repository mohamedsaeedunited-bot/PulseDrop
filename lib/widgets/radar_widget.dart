import 'dart:math';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';

class RadarWidget extends StatefulWidget {
  final String deviceName;
  final String? localIp;
  final bool stealthMode;
  final List<PeerDevice> peers;
  final Set<String> selectedPeerIds;
  final VoidCallback onCenterTap;
  final ValueChanged<PeerDevice> onPeerTap;

  const RadarWidget({
    super.key,
    required this.deviceName,
    required this.localIp,
    required this.stealthMode,
    required this.peers,
    required this.selectedPeerIds,
    required this.onCenterTap,
    required this.onPeerTap,
  });

  @override
  State<RadarWidget> createState() => _RadarWidgetState();
}

class _RadarWidgetState extends State<RadarWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = min(constraints.maxWidth, 310.0);
        final center = size / 2;
        final orbitRadius = size * 0.36;

        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedBuilder(
                animation: _controller,
                builder: (_, __) {
                  return CustomPaint(
                    size: Size(size, size),
                    painter: _RadarPainter(
                      progress: _controller.value,
                      isDark: isDark,
                      stealthMode: widget.stealthMode,
                    ),
                  );
                },
              ),
              GestureDetector(
                onTap: widget.onCenterTap,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: widget.stealthMode
                              ? [Colors.blueGrey, Colors.grey]
                              : [AppColors.primary, AppColors.accent],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (widget.stealthMode ? Colors.grey : AppColors.primary).withAlpha(90),
                            blurRadius: 18,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Icon(
                        widget.stealthMode ? Icons.visibility_off_rounded : Icons.bolt_rounded,
                        color: Colors.white,
                        size: 34,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                        ),
                      ),
                      child: Text(
                        widget.deviceName,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ),
                    if (widget.localIp != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          widget.localIp!,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              for (int i = 0; i < widget.peers.length; i++)
                _buildPeerNode(widget.peers[i], i, widget.peers.length, center, orbitRadius, isDark),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPeerNode(
    PeerDevice peer,
    int index,
    int total,
    double center,
    double radius,
    bool isDark,
  ) {
    final angle = (2 * pi * index / max(total, 1)) - (pi / 2);
    final dx = center + radius * cos(angle) - 36;
    final dy = center + radius * sin(angle) - 36;
    final isSelected = widget.selectedPeerIds.contains(peer.id);

    return Positioned(
      left: dx,
      top: dy,
      child: GestureDetector(
        onTap: () => widget.onPeerTap(peer),
        child: SizedBox(
          width: 72,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected
                      ? AppColors.primary
                      : (isDark ? AppColors.darkSurface : AppColors.lightSurface),
                  border: Border.all(
                    color: isSelected ? AppColors.success : AppColors.accent,
                    width: 2.4,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (isSelected ? AppColors.primary : AppColors.accent).withAlpha(80),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: Icon(
                  isSelected ? Icons.check_rounded : Icons.smartphone_rounded,
                  color: isSelected ? Colors.white : AppColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                peer.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double progress;
  final bool isDark;
  final bool stealthMode;

  _RadarPainter({
    required this.progress,
    required this.isDark,
    required this.stealthMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = (isDark ? AppColors.darkBorder : AppColors.lightBorder).withAlpha(140);

    for (final factor in [0.35, 0.65, 0.95]) {
      canvas.drawCircle(center, maxRadius * factor, ringPaint);
    }

    if (stealthMode) return;

    for (int i = 0; i < 3; i++) {
      final waveProgress = (progress + i / 3.0) % 1.0;
      final radius = maxRadius * (0.2 + 0.8 * waveProgress);
      final alpha = ((1.0 - waveProgress) * 110).toInt().clamp(0, 255);

      final wavePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = AppColors.accent.withAlpha(alpha);

      canvas.drawCircle(center, radius, wavePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.isDark != isDark ||
      oldDelegate.stealthMode != stealthMode;
}
