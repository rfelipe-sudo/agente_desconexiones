import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'bodega_screen.dart';
import 'configuracion_screen.dart';

class BodegueroMenuScreen extends StatefulWidget {
  const BodegueroMenuScreen({super.key});

  @override
  State<BodegueroMenuScreen> createState() => _BodegueroMenuScreenState();
}

class _BodegueroMenuScreenState extends State<BodegueroMenuScreen> {
  final supabase = Supabase.instance.client;

  int _pendientes = 0;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarPendientes();
  }

  Future<void> _cargarPendientes() async {
    setState(() => _cargando = true);

    try {
      print('🔍 [BodegueroMenu] Consultando contador...');
      
      final count = await supabase
          .from('equipos_reversa')
          .select('id')
          .eq('estado', 'en_revision');

      print('🔍 [BodegueroMenu] Equipos encontrados: ${count.length}');

      setState(() {
        _pendientes = count.length;
        _cargando = false;
      });
    } catch (e) {
      setState(() => _cargando = false);
      print('❌ [BodegueroMenu] Error cargando pendientes: $e');
    }
  }

  String _getNombreMes(int mes) {
    const meses = [
      '',
      'Enero',
      'Febrero',
      'Marzo',
      'Abril',
      'Mayo',
      'Junio',
      'Julio',
      'Agosto',
      'Septiembre',
      'Octubre',
      'Noviembre',
      'Diciembre'
    ];
    return meses[mes];
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final nombreMes = _getNombreMes(now.month);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bodega'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ConfiguracionScreen(),
              ),
            ),
            tooltip: 'Configuración',
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargarPendientes,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Título del mes
                    Text(
                      '$nombreMes ${now.year}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Card Recepción Reversa
                    _buildMenuCard(
                      icon: Icons.inventory_2,
                      color: Colors.deepOrange,
                      titulo: 'Recepción Reversa',
                      valor: _pendientes.toString(),
                      subtitulo: 'Equipos pendientes de recibir',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const BodegaScreen()),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Card Historial Recepciones
                    _buildMenuCard(
                      icon: Icons.history,
                      color: Colors.green[700]!,
                      titulo: 'Historial Recepciones',
                      valor: '--',
                      subtitulo: 'Equipos recibidos',
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Próximamente'),
                            backgroundColor: Colors.blue,
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 12),

                    // Card Rechazados
                    _buildMenuCard(
                      icon: Icons.cancel,
                      color: Colors.red[700]!,
                      titulo: 'Rechazados',
                      valor: '--',
                      subtitulo: 'Equipos rechazados',
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Próximamente'),
                            backgroundColor: Colors.blue,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildMenuCard({
    required IconData icon,
    required Color color,
    required String titulo,
    required String valor,
    required String subtitulo,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    Text(
                      valor,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    Text(
                      subtitulo,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}





