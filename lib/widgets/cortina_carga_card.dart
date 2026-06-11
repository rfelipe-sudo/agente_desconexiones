import 'package:flutter/material.dart';

/// Cortina de espera unificada al abrir una card del Home.
class CortinaCargaCard extends StatelessWidget {
  const CortinaCargaCard({
    super.key,
    required this.accentColor,
    required this.titulo,
    this.subtitulo = 'Cargando…',
  });

  final Color accentColor;
  final String titulo;
  final String subtitulo;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF0A1628),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      accentColor,
                      Color.lerp(accentColor, Colors.black, 0.35)!,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.35),
                      blurRadius: 30,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Center(
                  child: SizedBox(
                    width: 60,
                    height: 60,
                    child: CircularProgressIndicator(
                      strokeWidth: 5,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                titulo,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                subtitulo,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF8FA8C8),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1B2A),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF1E3A5F)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline, color: accentColor, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      'CREABOX',
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Envuelve [destination] con la cortina hasta que [hastaListo] termine.
class PantallaConCortina extends StatefulWidget {
  const PantallaConCortina({
    super.key,
    required this.accentColor,
    required this.titulo,
    required this.destination,
    this.subtitulo,
    this.hastaListo,
  });

  final Color accentColor;
  final String titulo;
  final String? subtitulo;
  final Widget destination;
  final Future<void> Function()? hastaListo;

  @override
  State<PantallaConCortina> createState() => _PantallaConCortinaState();
}

class _PantallaConCortinaState extends State<PantallaConCortina> {
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _resolver();
  }

  Future<void> _resolver() async {
    try {
      if (widget.hastaListo != null) {
        await widget.hastaListo!();
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    } catch (_) {}
    if (mounted) setState(() => _visible = false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.destination,
        if (_visible)
          CortinaCargaCard(
            accentColor: widget.accentColor,
            titulo: widget.titulo,
            subtitulo: widget.subtitulo ?? 'Cargando…',
          ),
      ],
    );
  }
}
