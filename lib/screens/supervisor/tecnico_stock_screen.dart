import 'package:flutter/material.dart';

import 'package:agente_desconexiones/models/solicitud_material.dart';
import 'package:agente_desconexiones/services/logistica_service.dart';

class TecnicoStockScreen extends StatelessWidget {
  final TecnicoStock tecnico;

  const TecnicoStockScreen({super.key, required this.tecnico});

  static const _bg      = Color(0xFF0A0F1E);
  static const _surface = Color(0xFF0D1B2A);
  static const _border  = Color(0xFF1E3A5F);
  static const _accent  = Color(0xFF00D9FF);
  static const _textDim = Color(0xFF8FA8C8);
  static const _green   = Color(0xFF22C55E);
  static const _orange  = Color(0xFFF59E0B);
  static const _red     = Color(0xFFEF4444);

  static final List<MaterialItem> _categorias = kMateriales;

  @override
  Widget build(BuildContext context) {
    final inicial = tecnico.nombre.isNotEmpty
        ? tecnico.nombre[0].toUpperCase()
        : '?';

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                inicial,
                style: const TextStyle(
                    color: _accent,
                    fontWeight: FontWeight.bold,
                    fontSize: 13),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tecnico.nombre,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _seccion('MATERIALES NO SERIADOS', _accent),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border),
            ),
            child: Column(
              children: _categorias
                  .where((m) => !m.esSeriado)
                  .map((m) => _buildFila(m.nombre, false))
                  .toList(),
            ),
          ),
          const SizedBox(height: 20),
          _seccion('EQUIPOS SERIADOS', _accent),
          const SizedBox(height: 4),
          Text(
            'Toca una categoría con stock para ver los números de serie.',
            style: TextStyle(color: _textDim.withValues(alpha: 0.85), fontSize: 11),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border),
            ),
            child: Column(
              children: _categorias
                  .where((m) => m.esSeriado)
                  .map((m) => _buildFila(m.nombre, true))
                  .toList(),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _seccion(String titulo, Color color) => Row(children: [
        Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(
          titulo,
          style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 11,
              letterSpacing: 0.8),
        ),
      ]);

  Widget _buildFila(String categoria, bool esSeriado) {
    final cantidad = tecnico.stock[categoria] ?? 0;
    final sinStock = cantidad == 0;
    final color = _stockColor(cantidad);
    final isLast = (esSeriado
            ? _categorias.where((m) => m.esSeriado)
            : _categorias.where((m) => !m.esSeriado))
        .last
        .nombre ==
        categoria;

    final series = esSeriado && !sinStock
        ? tecnico.seriadosPorCategoria(categoria)
        : const <ItemStock>[];

    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: sinStock ? 0.06 : 0.15),
        borderRadius: BorderRadius.circular(8),
        border: sinStock
            ? Border.all(color: _border.withValues(alpha: 0.5), width: 0.5)
            : null,
      ),
      child: Text(
        sinStock
            ? '0'
            : (cantidad == cantidad.truncate()
                ? '${cantidad.toInt()}'
                : cantidad.toStringAsFixed(1)),
        style: TextStyle(
          color: sinStock ? _textDim.withValues(alpha: 0.4) : color,
          fontWeight: sinStock ? FontWeight.normal : FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );

    Widget filaPrincipal({VoidCallback? onTap}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(children: [
            Icon(
              esSeriado ? Icons.memory_outlined : Icons.cable_outlined,
              color: sinStock ? _textDim.withValues(alpha: 0.4) : _textDim,
              size: 15,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                categoria,
                style: TextStyle(
                  color:
                      sinStock ? _textDim.withValues(alpha: 0.5) : Colors.white,
                  fontSize: 13,
                ),
              ),
            ),
            if (esSeriado && !sinStock) ...[
              badge,
              const SizedBox(width: 6),
              Icon(Icons.expand_more,
                  color: _textDim.withValues(alpha: 0.7), size: 18),
            ] else
              badge,
          ]),
        );

    return Column(
      children: [
        if (esSeriado && !sinStock)
          Theme(
            data: ThemeData(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding:
                  const EdgeInsets.only(left: 41, right: 16, bottom: 10),
              title: filaPrincipal(),
              iconColor: _textDim,
              collapsedIconColor: _textDim,
              children: series
                  .map((item) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.qr_code_2,
                                color: _accent, size: 14),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.serie ?? '',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                  if (item.nombre.isNotEmpty)
                                    Text(
                                      item.nombre,
                                      style: TextStyle(
                                        color: _textDim.withValues(alpha: 0.8),
                                        fontSize: 10,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          )
        else
          filaPrincipal(),
        if (!isLast) const Divider(height: 1, indent: 41, color: _border),
      ],
    );
  }

  Color _stockColor(double cantidad) {
    if (cantidad == 0) return _textDim;
    if (cantidad >= 5) return _green;
    if (cantidad >= 2) return _orange;
    return _red;
  }
}
