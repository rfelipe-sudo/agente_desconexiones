import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../models/transferencias_models.dart';

class TransferenciasService {
  static const String krpUrl = 'https://logistica.sbip.cl/api';
  static const String krpUsername = 'bmCgfkIydlMu';
  static const String krpPassword = 'bfoBIkNKSHDCThgpEWEF';
  
  final SupabaseClient supabase = Supabase.instance.client;
  
  /// Obtiene materiales de KRP con filtro por familias
  /// 
  /// [familiasIncluidas]: Lista de familias a incluir. Si es null, trae todas.
  /// [familiasExcluidas]: Lista de familias a excluir. Tiene prioridad sobre incluidas.
  /// [perfilFiltro]: Perfiles predefinidos: 'TODO', 'INSTALACION', 'SIN_EPP'
  Future<List<MaterialKrp>> obtenerMaterialesKrp({
    List<String>? familiasIncluidas,
    List<String>? familiasExcluidas,
    String perfilFiltro = 'INSTALACION',
  }) async {
    try {
      final credentials = base64Encode(utf8.encode('$krpUsername:$krpPassword'));
      
      final response = await http.get(
        Uri.parse('$krpUrl/get_all_materiales'),
        headers: {'Authorization': 'Basic $credentials'},
      ).timeout(Duration(seconds: 30));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> materialesJson = data['data'] ?? [];
        
        var materiales = materialesJson
            .map((json) => MaterialKrp.fromJson(json))
            .toList();
        
        // Aplicar filtro por perfil o listas personalizadas
        return _aplicarFiltroFamilias(
          materiales,
          familiasIncluidas: familiasIncluidas,
          familiasExcluidas: familiasExcluidas,
          perfilFiltro: perfilFiltro,
        );
      } else {
        throw Exception('Error ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      print('❌ Error consultando KRP: $e');
      rethrow;
    }
  }
  
  /// Aplica filtro por familias según perfil o listas personalizadas
  List<MaterialKrp> _aplicarFiltroFamilias(
    List<MaterialKrp> materiales, {
    List<String>? familiasIncluidas,
    List<String>? familiasExcluidas,
    required String perfilFiltro,
  }) {
    // Si se especifican listas personalizadas, usarlas
    if (familiasIncluidas != null || familiasExcluidas != null) {
      return materiales.where((m) {
        final familia = m.nombreFamilia ?? '';
        
        // Excluir tiene prioridad
        if (familiasExcluidas != null && familiasExcluidas.contains(familia)) {
          return false;
        }
        
        // Si hay lista de incluidas, solo permitir esas
        if (familiasIncluidas != null) {
          return familiasIncluidas.contains(familia);
        }
        
        return true;
      }).toList();
    }
    
    // Si no hay listas personalizadas, usar perfil
    switch (perfilFiltro) {
      case 'TODO':
        // Sin filtro, todos los materiales
        return materiales;
        
      case 'INSTALACION':
        // Solo familias de instalación (recomendado para transferencias)
        return materiales.where((m) {
          return FamiliasKRP.instalacion.contains(m.nombreFamilia ?? '');
        }).toList();
        
      case 'SIN_EPP':
        // Todo excepto EPP
        return materiales.where((m) {
          return m.nombreFamilia != 'EPP';
        }).toList();
        
      case 'SIN_HERRAMIENTAS':
        // Todo excepto herramientas
        return materiales.where((m) {
          return m.nombreFamilia != 'Herramientas';
        }).toList();
        
      case 'SIN_EXCLUIDOS':
        // Excluir familias que no se transfieren
        return materiales.where((m) {
          return !FamiliasKRP.excluir.contains(m.nombreFamilia ?? '');
        }).toList();
        
      case 'SOLO_HERRAMIENTAS':
        // Solo herramientas
        return materiales.where((m) {
          return m.nombreFamilia == 'Herramientas';
        }).toList();
        
      default:
        return materiales;
    }
  }
  
  Future<List<TecnicoConMaterial>> buscarTecnicosConMaterial({
    required String nombreMaterial,
    String? rutTecnicoActual,
  }) async {
    try {
      // Usar perfil INSTALACION por defecto para transferencias
      final materiales = await obtenerMaterialesKrp(perfilFiltro: 'INSTALACION');
      
      final materialesFiltrados = materiales.where((m) {
        final coincide = m.nombre.toUpperCase().contains(nombreMaterial.toUpperCase());
        final tieneRut = m.rutTrabajador != null && m.rutTrabajador!.isNotEmpty;
        final tieneCantidad = (m.cantidadDisponible ?? 0) > 0;
        final noEsElMismo = m.rutTrabajador != rutTecnicoActual;
        return coincide && tieneRut && tieneCantidad && noEsElMismo;
      }).toList();
      
      Map<String, TecnicoConMaterial> tecnicosPorRut = {};
      for (var material in materialesFiltrados) {
        final rut = material.rutTrabajador!;
        if (tecnicosPorRut.containsKey(rut)) {
          tecnicosPorRut[rut]!.materiales.add(material);
        } else {
          tecnicosPorRut[rut] = TecnicoConMaterial(
            rut: rut,
            nombre: material.nombreTrabajador ?? 'Técnico $rut',
            materiales: [material],
            latitud: material.latitud,
            longitud: material.longitud,
          );
        }
      }
      return tecnicosPorRut.values.toList();
    } catch (e) {
      print('❌ Error buscando técnicos: $e');
      rethrow;
    }
  }
  
  Future<List<TecnicoConMaterial>> ordenarPorDistancia({
    required List<TecnicoConMaterial> tecnicos,
    Position? ubicacionActual,
  }) async {
    try {
      ubicacionActual ??= await obtenerUbicacionActual();
      
      final tecnicosConDistancia = tecnicos.map((tecnico) {
        if (tecnico.latitud != null && tecnico.longitud != null) {
          final distancia = Geolocator.distanceBetween(
            ubicacionActual!.latitude,
            ubicacionActual.longitude,
            tecnico.latitud!,
            tecnico.longitud!,
          ) / 1000;
          return tecnico.copyWith(distancia: distancia);
        } else {
          return tecnico.copyWith(distancia: 9999);
        }
      }).toList();
      
      tecnicosConDistancia.sort((a, b) => (a.distancia ?? 9999).compareTo(b.distancia ?? 9999));
      return tecnicosConDistancia;
    } catch (e) {
      print('❌ Error ordenando por distancia: $e');
      return tecnicos;
    }
  }
  
  Future<Position> obtenerUbicacionActual() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Los servicios de ubicación están desactivados');
    }
    
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Permisos de ubicación denegados');
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      throw Exception('Permisos de ubicación denegados permanentemente');
    }
    
    return await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
  }
  
  Future<TransferenciaMaterial> crearSolicitudTransferencia({
    required String rutTecnicoOrigen,
    required String nombreTecnicoOrigen,
    required String rutTecnicoDestino,
    required String nombreTecnicoDestino,
    required MaterialTransferencia material,
    required String urgencia,
    double? distanciaKm,
    String? mensajeSolicitante,
  }) async {
    try {
      final codigo = await _generarCodigoTransferencia();
      
      final transferencia = TransferenciaMaterial(
        codigoTransferencia: codigo,
        rutTecnicoOrigen: rutTecnicoOrigen,
        nombreTecnicoOrigen: nombreTecnicoOrigen,
        rutTecnicoDestino: rutTecnicoDestino,
        nombreTecnicoDestino: nombreTecnicoDestino,
        material: material,
        estado: EstadoTransferencia.solicitado,
        urgencia: urgencia,
        distanciaKm: distanciaKm,
        mensajeSolicitante: mensajeSolicitante,
        fechaSolicitud: DateTime.now(),
      );
      
      final response = await supabase
          .from('transferencias_material')
          .insert(transferencia.toJson())
          .select()
          .single();
      
      return TransferenciaMaterial.fromJson(response);
    } catch (e) {
      print('❌ Error creando solicitud: $e');
      rethrow;
    }
  }
  
  Future<String> _generarCodigoTransferencia() async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = (timestamp % 10000).toString().padLeft(4, '0');
    return 'TRF-$random';
  }
  
  Future<void> aceptarTransferencia({required int transferenciaId}) async {
    try {
      await supabase.from('transferencias_material').update({
        'estado': EstadoTransferencia.aceptado,
        'fecha_aceptacion': DateTime.now().toIso8601String(),
      }).eq('id', transferenciaId);
    } catch (e) {
      print('❌ Error aceptando transferencia: $e');
      rethrow;
    }
  }
  
  Future<void> rechazarTransferencia({required int transferenciaId}) async {
    try {
      await supabase.from('transferencias_material').update({
        'estado': EstadoTransferencia.rechazado,
      }).eq('id', transferenciaId);
    } catch (e) {
      print('❌ Error rechazando transferencia: $e');
      rethrow;
    }
  }
  
  Future<void> registrarFirmas({
    required int transferenciaId,
    required String firmaEntrega,
    required String firmaRecepcion,
    String? serialTransferido,
    String? fotoTransferencia,
    Position? ubicacion,
  }) async {
    try {
      ubicacion ??= await obtenerUbicacionActual();
      
      await supabase.from('transferencias_material').update({
        'estado': EstadoTransferencia.firmado,
        'firma_entrega': firmaEntrega,
        'firma_recepcion': firmaRecepcion,
        'serial_transferido': serialTransferido,
        'foto_transferencia': fotoTransferencia,
        'latitud_encuentro': ubicacion.latitude,
        'longitud_encuentro': ubicacion.longitude,
        'fecha_firma': DateTime.now().toIso8601String(),
      }).eq('id', transferenciaId);
    } catch (e) {
      print('❌ Error registrando firmas: $e');
      rethrow;
    }
  }
  
  Future<List<TransferenciaMaterial>> obtenerTransferenciasPendientes({
    required String rutTecnico,
  }) async {
    try {
      final response = await supabase
          .from('transferencias_material')
          .select()
          .or('rut_tecnico_origen.eq.$rutTecnico,rut_tecnico_destino.eq.$rutTecnico')
          .inFilter('estado', [
            EstadoTransferencia.solicitado,
            EstadoTransferencia.aceptado,
            EstadoTransferencia.firmado,
          ])
          .order('fecha_solicitud', ascending: false);
      
      return (response as List).map((json) => TransferenciaMaterial.fromJson(json)).toList();
    } catch (e) {
      print('❌ Error obteniendo pendientes: $e');
      rethrow;
    }
  }
  
  Future<List<TransferenciaMaterial>> obtenerHistorial({
    required String rutTecnico,
    int limit = 50,
  }) async {
    try {
      final response = await supabase
          .from('transferencias_material')
          .select()
          .or('rut_tecnico_origen.eq.$rutTecnico,rut_tecnico_destino.eq.$rutTecnico')
          .order('fecha_solicitud', ascending: false)
          .limit(limit);
      
      return (response as List).map((json) => TransferenciaMaterial.fromJson(json)).toList();
    } catch (e) {
      print('❌ Error obteniendo historial: $e');
      rethrow;
    }
  }
}
