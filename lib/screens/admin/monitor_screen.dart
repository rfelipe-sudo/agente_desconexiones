import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import 'package:agente_desconexiones/services/alerta_sistema_service.dart';

// ─── Modelo de resultado de ping ────────────────────────────────────────────
class _PingResult {
  final String nombre;
  final String url;
  bool? ok;
  int? latencyMs;
  String? errorMsg;

  _PingResult({required this.nombre, required this.url});
}

// ─── Endpoints a monitorear ──────────────────────────────────────────────────
final List<_PingResult> _endpointsBase = [
  _PingResult(nombre: 'Kepler Stock',       url: 'https://logistica.sbip.cl/api/get_all_saldo'),
  _PingResult(nombre: 'Kepler Intercambio', url: 'https://logistica.sbip.cl'),
  _PingResult(nombre: 'Kepler v2',          url: 'https://keplerv2.sbip.cl'),
  _PingResult(nombre: 'Supabase DB',        url: 'https://efvicvqffvxocnrqjxrs.supabase.co/rest/v1/'),
  _PingResult(nombre: 'Edge: fcm-send',          url: 'https://efvicvqffvxocnrqjxrs.supabase.co/functions/v1/fcm-send'),
  _PingResult(nombre: 'Edge: generar-pin',       url: 'https://efvicvqffvxocnrqjxrs.supabase.co/functions/v1/generar-pin'),
  _PingResult(nombre: 'Edge: aprobar-traspaso',  url: 'https://efvicvqffvxocnrqjxrs.supabase.co/functions/v1/aprobar-traspaso'),
  _PingResult(nombre: 'Edge: notificar-bodega',  url: 'https://efvicvqffvxocnrqjxrs.supabase.co/functions/v1/notificar-bodega-traspaso'),
  _PingResult(nombre: 'Edge: registrar-fcm', url: 'https://efvicvqffvxocnrqjxrs.supabase.co/functions/v1/registrar-fcm-dispositivo'),
  _PingResult(nombre: 'Edge: notificar-guia-bodega', url: 'https://efvicvqffvxocnrqjxrs.supabase.co/functions/v1/notificar-bodegueros-guia'),
];

class MonitorScreen extends StatefulWidget {
  final String rutAdmin;
  const MonitorScreen({super.key, required this.rutAdmin});

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
  final _alertaService = AlertaSistemaService();

  List<_PingResult> _endpoints = [];
  bool _pinging = false;
  DateTime? _ultimoPing;

  List<Map<String, dynamic>> _alertas = [];
  bool _loadingAlertas = true;
  String _filtroEstado = 'todas';

  @override
  void initState() {
    super.initState();
    _endpoints = _endpointsBase
        .map((e) => _PingResult(nombre: e.nombre, url: e.url))
        .toList();
    _pingAll();
    _cargarAlertas();
  }

  // ─── Ping ────────────────────────────────────────────────────────────────

  Future<void> _pingAll() async {
    if (_pinging) return;
    setState(() {
      _pinging = true;
      for (final e in _endpoints) {
        e.ok = null;
        e.latencyMs = null;
        e.errorMsg = null;
      }
    });

    await Future.wait(_endpoints.map(_pingOne));

    if (mounted) {
      setState(() {
        _pinging = false;
        _ultimoPing = DateTime.now();
      });
    }
  }

  Future<void> _pingOne(_PingResult endpoint) async {
    final sw = Stopwatch()..start();
    try {
      final res = await http
          .get(Uri.parse(endpoint.url))
          .timeout(const Duration(seconds: 5));
      sw.stop();
      // Consideramos OK cualquier respuesta HTTP (incluso 401/405 significa que el server responde)
      final ok = res.statusCode < 500;
      if (mounted) {
        setState(() {
          endpoint.ok = ok;
          endpoint.latencyMs = sw.elapsedMilliseconds;
          endpoint.errorMsg = ok ? null : 'HTTP ${res.statusCode}';
        });
      }
    } catch (e) {
      sw.stop();
      if (mounted) {
        setState(() {
          endpoint.ok = false;
          endpoint.latencyMs = sw.elapsedMilliseconds;
          endpoint.errorMsg = e.toString().split(':').first;
        });
      }
    }
  }

  // ─── Alertas ─────────────────────────────────────────────────────────────

  Future<void> _cargarAlertas() async {
    setState(() => _loadingAlertas = true);
    try {
      final lista = await _alertaService.listarAlertas(
        filtroEstado: _filtroEstado == 'todas' ? null : _filtroEstado,
        limite: 200,
      );
      if (mounted) setState(() => _alertas = lista);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando alertas: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingAlertas = false);
    }
  }

  Future<void> _marcarRevisada(String alertaId) async {
    try {
      await _alertaService.marcarRevisada(
        alertaId: alertaId,
        rutAdmin: widget.rutAdmin,
      );
      await _cargarAlertas();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1628),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1B2A),
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.monitor_heart_rounded, color: Color(0xFF00D9FF), size: 22),
            SizedBox(width: 10),
            Text(
              'Monitor del Sistema',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: _pinging
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF00D9FF)),
                  )
                : const Icon(Icons.refresh_rounded, color: Color(0xFF00D9FF)),
            tooltip: 'Repetir pings',
            onPressed: _pinging ? null : _pingAll,
          ),
        ],
      ),
      body: RefreshIndicator(
        color: const Color(0xFF00D9FF),
        onRefresh: () async {
          await Future.wait([_pingAll(), _cargarAlertas()]);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildEndpointsSection(),
            const SizedBox(height: 24),
            _buildAlertasSection(),
          ],
        ),
      ),
    );
  }

  // ─── Bloque 1: Endpoints ─────────────────────────────────────────────────

  Widget _buildEndpointsSection() {
    final fmt = DateFormat('HH:mm:ss');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'ESTADO DE ENDPOINTS',
              style: TextStyle(
                color: Color(0xFF00D9FF),
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            const Spacer(),
            if (_ultimoPing != null)
              Text(
                'Último: ${fmt.format(_ultimoPing!)}',
                style: const TextStyle(color: Color(0xFF4A6FA5), fontSize: 11),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0D1B2A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.07)),
          ),
          child: Column(
            children: List.generate(_endpoints.length, (i) {
              final e = _endpoints[i];
              return _buildEndpointRow(e, isLast: i == _endpoints.length - 1);
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildEndpointRow(_PingResult e, {required bool isLast}) {
    final Widget statusIcon;

    if (e.ok == null) {
      statusIcon = const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4A6FA5)),
      );
    } else if (e.ok!) {
      statusIcon = const Icon(Icons.circle, color: Color(0xFF22C55E), size: 12);
    } else {
      statusIcon = const Icon(Icons.circle, color: Color(0xFFEF4444), size: 12);
    }

    final latencyText = e.latencyMs != null ? '${e.latencyMs} ms' : '';
    final latencyColor = e.latencyMs == null
        ? Colors.transparent
        : e.latencyMs! < 500
            ? const Color(0xFF22C55E)
            : e.latencyMs! < 2000
                ? const Color(0xFFF59E0B)
                : const Color(0xFFEF4444);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                    color: Colors.white.withOpacity(0.05), width: 1)),
      ),
      child: Row(
        children: [
          statusIcon,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.nombre,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                ),
                if (e.errorMsg != null)
                  Text(
                    e.errorMsg!,
                    style: const TextStyle(color: Color(0xFFEF4444), fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (latencyText.isNotEmpty)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: latencyColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                latencyText,
                style: TextStyle(
                    color: latencyColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Bloque 2: Alertas ───────────────────────────────────────────────────

  Widget _buildAlertasSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'HISTORIAL DE ALERTAS',
              style: TextStyle(
                color: Color(0xFF00D9FF),
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.refresh_rounded,
                  color: Color(0xFF4A6FA5), size: 18),
              tooltip: 'Recargar alertas',
              onPressed: _cargarAlertas,
            ),
          ],
        ),
        // Filtro de estado
        Row(
          children: [
            _filtroChip('todas', 'Todas'),
            const SizedBox(width: 8),
            _filtroChip('nueva', 'Nuevas'),
            const SizedBox(width: 8),
            _filtroChip('revisada', 'Revisadas'),
          ],
        ),
        const SizedBox(height: 10),
        if (_loadingAlertas)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(color: Color(0xFF00D9FF)),
            ),
          )
        else if (_alertas.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1B2A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.07)),
            ),
            child: const Center(
              child: Text(
                'Sin alertas',
                style: TextStyle(color: Color(0xFF4A6FA5), fontSize: 14),
              ),
            ),
          )
        else
          ...List.generate(_alertas.length, (i) => _buildAlertaCard(_alertas[i])),
      ],
    );
  }

  Widget _filtroChip(String value, String label) {
    final selected = _filtroEstado == value;
    return GestureDetector(
      onTap: () {
        setState(() => _filtroEstado = value);
        _cargarAlertas();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF00D9FF).withOpacity(0.15)
              : const Color(0xFF0D1B2A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? const Color(0xFF00D9FF)
                : Colors.white.withOpacity(0.1),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFF00D9FF) : const Color(0xFF8FA8C8),
            fontSize: 12,
            fontWeight:
                selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildAlertaCard(Map<String, dynamic> alerta) {
    final esNueva = (alerta['estado'] as String?) == 'nueva';
    final ts = alerta['timestamp'] as String?;
    final DateTime? fecha =
        ts != null ? DateTime.tryParse(ts)?.toLocal() : null;
    final fmtFecha = DateFormat('dd/MM HH:mm');
    final id = alerta['id'] as String? ?? '';

    final modulo = alerta['modulo'] as String? ?? '';
    final tipoError = alerta['tipo_error'] as String? ?? '';
    final mensaje = alerta['mensaje'] as String? ?? '';
    final nombreTecnico = alerta['nombre_tecnico'] as String?;
    final rutTecnico = alerta['rut_tecnico'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: esNueva
              ? const Color(0xFFEF4444).withOpacity(0.4)
              : Colors.white.withOpacity(0.07),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: esNueva
                      ? const Color(0xFFEF4444).withOpacity(0.15)
                      : const Color(0xFF22C55E).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  modulo,
                  style: TextStyle(
                    color: esNueva
                        ? const Color(0xFFEF4444)
                        : const Color(0xFF22C55E),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                tipoError,
                style: const TextStyle(
                    color: Color(0xFF8FA8C8), fontSize: 11),
              ),
              const Spacer(),
              Text(
                fecha != null ? fmtFecha.format(fecha) : '',
                style: const TextStyle(
                    color: Color(0xFF4A6FA5), fontSize: 11),
              ),
            ],
          ),
          if (nombreTecnico != null || rutTecnico != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.person_outline,
                    color: Color(0xFF8FA8C8), size: 13),
                const SizedBox(width: 4),
                Text(
                  [
                    if (nombreTecnico != null) nombreTecnico,
                    if (rutTecnico != null) rutTecnico,
                  ].join(' · '),
                  style: const TextStyle(
                      color: Color(0xFF8FA8C8), fontSize: 12),
                ),
              ],
            ),
          ],
          if (mensaje.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              mensaje,
              style: const TextStyle(
                  color: Color(0xFFCBD5E1), fontSize: 12),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (esNueva) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  backgroundColor:
                      const Color(0xFF22C55E).withOpacity(0.1),
                  foregroundColor: const Color(0xFF22C55E),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.check_circle_outline, size: 16),
                label: const Text('Marcar revisada',
                    style: TextStyle(fontSize: 12)),
                onPressed: () => _marcarRevisada(id),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
