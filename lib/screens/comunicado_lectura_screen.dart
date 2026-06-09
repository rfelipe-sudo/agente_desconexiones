import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

import 'package:agente_desconexiones/services/comunicado_service.dart';
import 'package:agente_desconexiones/services/firma_electronica_leyenda_pdf.dart';
import 'package:agente_desconexiones/utils/session_manager.dart';

/// Pantalla bloqueante: título/mensaje destacados → Aceptar → firma.
class ComunicadoLecturaScreen extends StatefulWidget {
  const ComunicadoLecturaScreen({super.key, required this.comunicado});

  final Map<String, dynamic> comunicado;

  @override
  State<ComunicadoLecturaScreen> createState() =>
      _ComunicadoLecturaScreenState();
}

class _ComunicadoLecturaScreenState extends State<ComunicadoLecturaScreen> {
  static const Color _azulTitulo = Color(0xFF1D4ED8);
  static const Color _verdeMensaje = Color(0xFF15803D);

  String get _titulo =>
      widget.comunicado['titulo'] as String? ?? 'Comunicado CREABOX';

  String get _mensaje =>
      widget.comunicado['mensaje'] as String? ?? '';

  String get _comunicadoId => widget.comunicado['id'] as String? ?? '';

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red[800] : null,
      ),
    );
  }

  Future<void> _abrirCuadroFirma() async {
    final rut = await SessionManager.getRutTecnico();
    final nombre = await SessionManager.getNombreTecnico();
    final textoLegal = FirmaElectronicaLeyendaPdf.parrafoLegal(
      nombre: nombre,
      rut: rut,
      rol: 'destinatario',
    );

    final sigCtrl = SignatureController(
      penStrokeWidth: 3,
      penColor: Colors.black,
      exportBackgroundColor: Colors.white,
    );

    final confirmado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        var guardandoLocal = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Dialog(
              backgroundColor: const Color(0xFF0D1B2A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 24,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.75,
                  maxWidth: 480,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Firma Electrónica del Destinatario',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 120),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF2A3F5F)),
                        ),
                        child: SingleChildScrollView(
                          child: Text(
                            textoLegal,
                            textAlign: TextAlign.justify,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 11,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Firma Electrónica Simple — Ley N° 19.799 (Chile)',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF8FA8C8),
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 200,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Signature(
                              controller: sigCtrl,
                              backgroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: guardandoLocal ? null : sigCtrl.clear,
                          child: const Text(
                            'Limpiar firma',
                            style: TextStyle(color: Color(0xFF8FA8C8)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: guardandoLocal
                                  ? null
                                  : () => Navigator.of(dialogCtx).pop(false),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF8FA8C8),
                                side: const BorderSide(color: Color(0xFF2A3F5F)),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: const Text('Cancelar'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              onPressed: guardandoLocal
                                  ? null
                                  : () async {
                                      if (sigCtrl.isEmpty) {
                                        _snack('Firma antes de confirmar',
                                            error: true);
                                        return;
                                      }
                                      if (_comunicadoId.isEmpty) {
                                        _snack('Comunicado inválido',
                                            error: true);
                                        return;
                                      }
                                      setDialogState(() => guardandoLocal = true);
                                      try {
                                        final bytes =
                                            await sigCtrl.toPngBytes();
                                        if (bytes == null) {
                                          throw StateError(
                                              'No se pudo exportar la firma');
                                        }
                                        final b64 = base64Encode(bytes);
                                        final rut =
                                            await SessionManager.getRutTecnico();
                                        final nombre =
                                            await SessionManager
                                                .getNombreTecnico();

                                        await ComunicadoService.instance
                                            .marcarLeido(
                                          comunicadoId: _comunicadoId,
                                          rut: rut,
                                          nombre: nombre,
                                          firmaBase64: b64,
                                        );
                                        if (dialogCtx.mounted) {
                                          Navigator.of(dialogCtx).pop(true);
                                        }
                                      } catch (e) {
                                        _snack('Error al guardar: $e',
                                            error: true);
                                        setDialogState(
                                            () => guardandoLocal = false);
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF22C55E),
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: guardandoLocal
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'Confirmar firma',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    sigCtrl.dispose();

    if (confirmado == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A1628),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: _azulTitulo,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _titulo,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              height: 1.3,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: _verdeMensaje,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _mensaje,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF22C55E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _abrirCuadroFirma,
                  child: const Text(
                    'ACEPTAR',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
