import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/transferencias_models.dart';
import '../services/transferencias_service.dart';

class SolicitarMaterialScreen extends StatefulWidget {
  const SolicitarMaterialScreen({Key? key}) : super(key: key);

  @override
  _SolicitarMaterialScreenState createState() => _SolicitarMaterialScreenState();
}

class _SolicitarMaterialScreenState extends State<SolicitarMaterialScreen> {
  final _service = TransferenciasService();
  final _cantidadController = TextEditingController(text: '1');
  final _searchController = TextEditingController();
  
  bool _buscando = false;
  bool _cargandoMateriales = true;
  List<TecnicoConMaterial> _tecnicos = [];
  List<MaterialKrp> _todosMateriales = [];
  List<MaterialKrp> _materialesFiltrados = [];
  MaterialKrp? _materialSeleccionado;
  Position? _miUbicacion;
  String? _error;
  
  @override
  void initState() {
    super.initState();
    _obtenerUbicacion();
    _cargarCatalogoMateriales();
  }
  
  /// Carga el catálogo completo de materiales desde KRP
  Future<void> _cargarCatalogoMateriales() async {
    try {
      print('📦 Cargando catálogo de materiales...');
      final materiales = await _service.obtenerMaterialesKrp(
        perfilFiltro: 'INSTALACION',
      );
      
      setState(() {
        _todosMateriales = materiales;
        _materialesFiltrados = materiales;
        _cargandoMateriales = false;
      });
      
      print('✅ ${materiales.length} materiales cargados (perfil: INSTALACION)');
    } catch (e) {
      print('❌ Error cargando materiales: $e');
      setState(() {
        _cargandoMateriales = false;
        _error = 'Error cargando catálogo: $e';
      });
    }
  }
  
  /// Filtra materiales según el texto de búsqueda
  void _filtrarMateriales(String query) {
    setState(() {
      if (query.isEmpty) {
        _materialesFiltrados = _todosMateriales;
      } else {
        _materialesFiltrados = _todosMateriales.where((material) {
          final nombreLower = material.nombre.toLowerCase();
          final skuLower = material.sku.toLowerCase();
          final queryLower = query.toLowerCase();
          return nombreLower.contains(queryLower) || skuLower.contains(queryLower);
        }).toList();
      }
    });
  }
  
  Future<void> _obtenerUbicacion() async {
    try {
      final ubicacion = await _service.obtenerUbicacionActual();
      setState(() {
        _miUbicacion = ubicacion;
      });
    } catch (e) {
      setState(() {
        _error = 'No se pudo obtener tu ubicación: $e';
      });
    }
  }
  
  Future<void> _buscarTecnicos() async {
    if (_materialSeleccionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('⚠️ Selecciona un material primero')),
      );
      return;
    }
    
    setState(() {
      _buscando = true;
      _error = null;
      _tecnicos = [];
    });
    
    try {
      print('🔍 Buscando técnicos con: ${_materialSeleccionado!.nombre}');
      
      final tecnicos = await _service.buscarTecnicosConMaterial(
        nombreMaterial: _materialSeleccionado!.nombre,
        rutTecnicoActual: '11111111-1',
      );
      
      final tecnicosOrdenados = await _service.ordenarPorDistancia(
        tecnicos: tecnicos,
        ubicacionActual: _miUbicacion,
      );
      
      setState(() {
        _tecnicos = tecnicosOrdenados;
        _buscando = false;
      });
      
      if (_tecnicos.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ No se encontraron técnicos con ese material'),
            backgroundColor: Colors.red,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ ${tecnicosOrdenados.length} técnico(s) encontrado(s)'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _buscando = false;
        _error = 'Error: $e';
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
        ),
      );
    }
  }
  
  Future<void> _enviarSolicitud(TecnicoConMaterial tecnico) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('📨 Confirmar Solicitud'),
        content: Text(
          '¿Enviar solicitud a ${tecnico.nombre}?\n\n'
          'Material: ${_materialSeleccionado!.nombre}\n'
          'Cantidad: ${_cantidadController.text}\n'
          'Distancia: ${tecnico.distancia?.toStringAsFixed(1) ?? '?'} km'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Enviar'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          ),
        ],
      ),
    );
    
    if (confirmar != true) return;
    
    try {
      final material = MaterialTransferencia(
        sku: _materialSeleccionado!.sku,
        nombre: _materialSeleccionado!.nombre,
        cantidad: int.parse(_cantidadController.text),
        uuid: _materialSeleccionado!.uuid,
      );
      
      await _service.crearSolicitudTransferencia(
        rutTecnicoOrigen: tecnico.rut,
        nombreTecnicoOrigen: tecnico.nombre,
        rutTecnicoDestino: '11111111-1',
        nombreTecnicoDestino: 'Usuario Prueba',
        material: material,
        urgencia: UrgenciaTransferencia.normal,
        distanciaKm: tecnico.distancia,
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Solicitud enviada a ${tecnico.nombre}'),
          backgroundColor: Colors.green,
        ),
      );
      
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
        ),
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.inventory_2, color: Colors.white),
            SizedBox(width: 8),
            Text('Ayuda con Material Faltante'),
          ],
        ),
        backgroundColor: Colors.orange,
        elevation: 0,
      ),
      body: _cargandoMateriales
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                  ),
                  SizedBox(height: 16),
                  Text('Cargando catálogo de materiales...'),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '¿Qué material necesitas?',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Buscaremos técnicos cercanos que tengan el material disponible',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                  
                  SizedBox(height: 24),
                  
                  // CAMPO DE BÚSQUEDA Y SELECTOR DE MATERIAL
                  _buildSelectorMaterial(),
                  
                  SizedBox(height: 16),
                  
                  // Campo de cantidad
                  TextField(
                    controller: _cantidadController,
                    decoration: InputDecoration(
                      labelText: 'Cantidad',
                      prefixIcon: Icon(Icons.pin, color: Colors.orange),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.orange, width: 2),
                      ),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  
                  SizedBox(height: 20),
                  
                  // Información de ubicación
                  if (_miUbicacion != null)
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: Icon(Icons.location_on, color: Colors.green, size: 32),
                        title: Text(
                          'Tu ubicación detectada',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          'Lat: ${_miUbicacion!.latitude.toStringAsFixed(4)}\n'
                          'Lng: ${_miUbicacion!.longitude.toStringAsFixed(4)}',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    )
                  else if (_error != null)
                    Card(
                      color: Colors.orange[50],
                      child: ListTile(
                        leading: Icon(Icons.warning, color: Colors.orange),
                        title: Text('Ubicación no disponible'),
                        subtitle: Text(
                          'La búsqueda funcionará pero sin ordenar por distancia',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  
                  SizedBox(height: 20),
                  
                  // Botón de búsqueda
                  ElevatedButton.icon(
                    onPressed: (_buscando || _materialSeleccionado == null) ? null : _buscarTecnicos,
                    icon: _buscando 
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Icon(Icons.search, size: 28),
                    label: Text(
                      _buscando ? 'BUSCANDO...' : '🔍 BUSCAR TÉCNICOS CERCANOS',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.all(18),
                      backgroundColor: (_materialSeleccionado == null) ? Colors.grey : Colors.orange,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 4,
                    ),
                  ),
                  
                  SizedBox(height: 24),
                  
                  if (_tecnicos.isNotEmpty || _error != null)
                    Divider(thickness: 2),
                  
                  if (_error != null && _tecnicos.isEmpty)
                    Card(
                      color: Colors.red[50],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(Icons.error, color: Colors.red),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _error!,
                                style: TextStyle(color: Colors.red[900]),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  
                  if (_tecnicos.isNotEmpty) ...[
                    Text(
                      '✅ ${_tecnicos.length} técnico(s) con material disponible:',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                    
                    SizedBox(height: 16),
                    
                    ..._tecnicos.map((tecnico) => _buildTecnicoCard(tecnico)),
                  ],
                  
                  if (_buscando)
                    Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Column(
                          children: [
                            CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                            ),
                            SizedBox(height: 16),
                            Text(
                              'Buscando técnicos con material...',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
  
  /// Widget selector de material con búsqueda y dropdown
  Widget _buildSelectorMaterial() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Campo de búsqueda con dropdown
        GestureDetector(
          onTap: () => _mostrarDropdownMateriales(),
          child: AbsorbPointer(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: _materialSeleccionado == null 
                    ? 'Seleccionar material' 
                    : _materialSeleccionado!.nombre,
                hintText: 'Toca para seleccionar',
                prefixIcon: Icon(
                  _materialSeleccionado == null ? Icons.search : Icons.check_circle,
                  color: _materialSeleccionado == null ? Colors.orange : Colors.green,
                ),
                suffixIcon: Icon(Icons.arrow_drop_down, color: Colors.orange),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.orange, width: 2),
                ),
              ),
            ),
          ),
        ),
        
        SizedBox(height: 8),
        
        // Material seleccionado actual (compacto)
        if (_materialSeleccionado != null)
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green, width: 1),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _materialSeleccionado!.nombre,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        'SKU: ${_materialSeleccionado!.sku}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: Colors.red, size: 20),
                  onPressed: () {
                    setState(() {
                      _materialSeleccionado = null;
                      _searchController.clear();
                    });
                  },
                  tooltip: 'Cambiar material',
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(),
                ),
              ],
            ),
          )
        else
          Text(
            'Toca el campo para ver el catálogo de materiales',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
      ],
    );
  }
  
  /// Mostrar modal con lista de materiales
  Future<void> _mostrarDropdownMateriales() async {
    final TextEditingController busquedaController = TextEditingController();
    List<MaterialKrp> materialesFiltrados = _todosMateriales;
    
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  // Título
                  Row(
                    children: [
                      Icon(Icons.inventory_2, color: Colors.orange),
                      SizedBox(width: 12),
                      Text(
                        'Seleccionar Material',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Spacer(),
                      IconButton(
                        icon: Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  
                  SizedBox(height: 16),
                  
                  // Campo de búsqueda dentro del modal
                  TextField(
                    controller: busquedaController,
                    autofocus: true,
                    onChanged: (query) {
                      setModalState(() {
                        if (query.isEmpty) {
                          materialesFiltrados = _todosMateriales;
                        } else {
                          materialesFiltrados = _todosMateriales.where((material) {
                            final nombreLower = material.nombre.toLowerCase();
                            final skuLower = material.sku.toLowerCase();
                            final queryLower = query.toLowerCase();
                            return nombreLower.contains(queryLower) || skuLower.contains(queryLower);
                          }).toList();
                        }
                      });
                    },
                    decoration: InputDecoration(
                      labelText: 'Buscar',
                      hintText: 'Escribe para filtrar (ej: ONT, AMARRA)',
                      prefixIcon: Icon(Icons.search, color: Colors.orange),
                      suffixIcon: busquedaController.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear),
                              onPressed: () {
                                busquedaController.clear();
                                setModalState(() {
                                  materialesFiltrados = _todosMateriales;
                                });
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.orange, width: 2),
                      ),
                    ),
                  ),
                  
                  SizedBox(height: 12),
                  
                  // Contador de resultados
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${materialesFiltrados.length} material(es) encontrado(s)',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ),
                  
                  SizedBox(height: 8),
                  
                  // Lista de materiales
                  Expanded(
                    child: materialesFiltrados.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
                                SizedBox(height: 16),
                                Text(
                                  'No se encontraron materiales',
                                  style: TextStyle(color: Colors.grey[600]),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: materialesFiltrados.length,
                            itemBuilder: (context, index) {
                              final material = materialesFiltrados[index];
                              final isSelected = _materialSeleccionado?.id == material.id;
                              
                              return Card(
                                elevation: isSelected ? 3 : 1,
                                color: isSelected ? Colors.green[50] : null,
                                margin: EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: Icon(
                                    material.esSeriado ? Icons.qr_code : Icons.inventory,
                                    color: isSelected ? Colors.green : Colors.orange,
                                    size: 28,
                                  ),
                                  title: Text(
                                    material.nombre,
                                    style: TextStyle(
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                  subtitle: Text('SKU: ${material.sku}'),
                                  trailing: isSelected
                                      ? Icon(Icons.check_circle, color: Colors.green, size: 28)
                                      : Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16),
                                  onTap: () {
                                    setState(() {
                                      _materialSeleccionado = material;
                                      _searchController.text = material.nombre;
                                    });
                                    Navigator.pop(context);
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
  
  Widget _buildTecnicoCard(TecnicoConMaterial tecnico) {
    final material = tecnico.materiales.first;
    final distancia = tecnico.distancia ?? 9999;
    final tieneUbicacion = distancia < 9999;
    
    return Card(
      elevation: 4,
      margin: EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _enviarSolicitud(tecnico),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.blue,
                    child: Icon(Icons.person, color: Colors.white),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tecnico.nombre,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'RUT: ${tecnico.rut}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (tieneUbicacion)
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: distancia < 5 ? Colors.green[50] : Colors.orange[50],
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: distancia < 5 ? Colors.green : Colors.orange,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.location_on,
                            size: 16,
                            color: distancia < 5 ? Colors.green : Colors.orange,
                          ),
                          SizedBox(width: 4),
                          Text(
                            '${distancia.toStringAsFixed(1)} km',
                            style: TextStyle(
                              color: distancia < 5 ? Colors.green : Colors.orange,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              
              SizedBox(height: 16),
              
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.inventory_2, color: Colors.blue, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Material Disponible',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[900],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      material.nombre,
                      style: TextStyle(fontSize: 14),
                    ),
                    SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          'Cantidad: ',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          '${material.cantidadDisponible ?? '?'}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[900],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              SizedBox(height: 16),
              
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _enviarSolicitud(tecnico),
                  icon: Icon(Icons.send, size: 20),
                  label: Text(
                    'SOLICITAR MATERIAL',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: EdgeInsets.all(14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  @override
  void dispose() {
    _cantidadController.dispose();
    _searchController.dispose();
    super.dispose();
  }
}
