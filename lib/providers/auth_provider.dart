import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:agente_desconexiones/models/usuario.dart';
import 'package:agente_desconexiones/constants/app_constants.dart';
import 'package:agente_desconexiones/services/tecnico_service.dart';
import 'package:agente_desconexiones/utils/session_manager.dart';

/// Estado del registro del dispositivo
enum RegistroEstado {
  cargando,       // Verificando si está registrado
  noRegistrado,   // Dispositivo nuevo, necesita registro
  registrado,     // Ya registrado, puede entrar
  error,          // Error al verificar
}

/// Provider para manejar autenticación y sesión del usuario
class AuthProvider extends ChangeNotifier {
  Usuario? _usuario;
  Usuario? get usuario => _usuario;
  
  TecnicoData? _tecnico;
  TecnicoData? get tecnico => _tecnico;
  
  bool _isLoading = true;
  bool get isLoading => _isLoading;
  
  RegistroEstado _registroEstado = RegistroEstado.cargando;
  RegistroEstado get registroEstado => _registroEstado;
  
  bool get isAuthenticated => _registroEstado == RegistroEstado.registrado && _usuario != null;
  bool get necesitaRegistro => _registroEstado == RegistroEstado.noRegistrado;
  
  String? _error;
  String? get error => _error;
  
  String? _deviceId;
  String? get deviceId => _deviceId;

  /// Inicializa el provider verificando el registro del dispositivo
  Future<void> initialize() async {
    _isLoading = true;
    _registroEstado = RegistroEstado.cargando;
    notifyListeners();
    
    try {
      await SessionManager.init();
      // Obtener el device ID
      _deviceId = await TecnicoService.getDeviceId();
      print('📱 Device ID: $_deviceId');

      // CREABOX tiene prioridad: si hay RUT en prefs, no usar registro legacy mock
      // (evita nombre antiguo con RUT nuevo cuando coexistía `tecnico_registrado`).
      final rutCrea = await SessionManager.getRutTecnico();
      if (rutCrea.isNotEmpty) {
        await SessionManager.asegurarNombreCoherenteConRutActual();
        _tecnico = null;
        final nombreCrea = await SessionManager.getNombreTecnico();
        final rolStr = await SessionManager.getRol();
        _usuario = Usuario(
          id: _deviceId ?? '',
          nombre: nombreCrea.isNotEmpty ? nombreCrea : rutCrea,
          telefono: rutCrea,
          email: '$rutCrea@crea.cl',
          rol: (rolStr == 'supervisor' || rolStr == 'ito')
              ? RolUsuario.supervisor
              : RolUsuario.tecnico,
          ultimaConexion: DateTime.now(),
        );
        _registroEstado = RegistroEstado.registrado;
        print('✅ Sesión CREABOX: ${_usuario!.nombre} ($rutCrea)');
      } else {
        _tecnico = await TecnicoService.verificarRegistro();

        if (_tecnico != null) {
          _usuario = Usuario(
            id: _tecnico!.deviceId,
            nombre: _tecnico!.nombre,
            telefono: _tecnico!.telefono,
            email: '${_tecnico!.telefono}@crea.cl',
            rol: _tecnico!.esSupervisor ? RolUsuario.supervisor : RolUsuario.tecnico,
            ultimaConexion: DateTime.now(),
          );
          _registroEstado = RegistroEstado.registrado;
          print('✅ Usuario autenticado (legacy): ${_usuario!.nombre}');
        } else {
          _registroEstado = RegistroEstado.noRegistrado;
          print('⚠️ Sin RUT CREABOX: pantalla de registro');
        }
      }
    } catch (e) {
      print('❌ Error inicializando auth: $e');
      _error = 'Error al verificar registro: $e';
      _registroEstado = RegistroEstado.error;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Registra el dispositivo con los datos del técnico
  Future<bool> registrarDispositivo({
    required String telefono,
    required String nombre,
    String rol = 'tecnico',
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      // Validaciones
      if (telefono.trim().isEmpty) {
        _error = 'El teléfono es obligatorio';
        _isLoading = false;
        notifyListeners();
        return false;
      }
      
      if (nombre.trim().isEmpty) {
        _error = 'El nombre es obligatorio';
        _isLoading = false;
        notifyListeners();
        return false;
      }
      
      // Registrar el técnico
      _tecnico = await TecnicoService.registrarTecnico(
        telefono: telefono.trim(),
        nombre: nombre.trim(),
        rol: rol,
      );
      
      if (_tecnico == null) {
        _error = 'Error al registrar el dispositivo';
        _isLoading = false;
        notifyListeners();
        return false;
      }
      
      // Crear usuario
      _usuario = Usuario(
        id: _tecnico!.deviceId,
        nombre: _tecnico!.nombre,
        telefono: _tecnico!.telefono,
        email: '${_tecnico!.telefono}@crea.cl',
        rol: _tecnico!.esSupervisor ? RolUsuario.supervisor : RolUsuario.tecnico,
        ultimaConexion: DateTime.now(),
      );
      
      // Guardar sesión
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        AppConstants.storageKeyUsuario,
        jsonEncode(_usuario!.toJson()),
      );
      
      _registroEstado = RegistroEstado.registrado;
      _isLoading = false;
      notifyListeners();
      
      print('✅ Registro exitoso: ${_usuario!.nombre}');
      return true;
    } catch (e) {
      _error = 'Error de registro: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Limpia sesión CREABOX (RUT/nombre en prefs) cuando el panel elimina el dispositivo.
  Future<void> invalidarSesionCreabox() async {
    try {
      _tecnico = null;
      await SessionManager.limpiarMarcadorNombreAtado();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('rut_tecnico');
      await prefs.remove('user_rut');
      await prefs.remove('user_nombre');
      await prefs.remove('nombre_tecnico');
      await prefs.remove('user_rol');
      await prefs.remove('tipo_personal');
      await prefs.remove(AppConstants.storageKeyUsuario);
      _usuario = null;
      _registroEstado = RegistroEstado.noRegistrado;
      notifyListeners();
    } catch (e) {
      print('⚠️ invalidarSesionCreabox: $e');
    }
  }

  /// Cierra la sesión del usuario (limpia registro local)
  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      // Limpiar registro local
      await TecnicoService.limpiarRegistro();
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(AppConstants.storageKeyUsuario);
      
      _usuario = null;
      _tecnico = null;
      _registroEstado = RegistroEstado.noRegistrado;
    } catch (e) {
      print('Error en logout: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Actualiza datos del usuario
  Future<void> actualizarUsuario(Usuario usuario) async {
    _usuario = usuario;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppConstants.storageKeyUsuario,
      jsonEncode(usuario.toJson()),
    );
    
    notifyListeners();
  }
  
  /// Reintentar verificación (para botón de reintentar en error)
  Future<void> reintentar() async {
    await initialize();
  }

  /// Actualiza [Usuario] desde prefs CREABOX sin pantalla de carga global.
  /// Útil tras guardar nombre/RUT o sincronizar desde Supabase.
  Future<void> syncUsuarioDesdePrefs() async {
    try {
      final rut = await SessionManager.getRutTecnico();
      if (rut.isEmpty) return;

      await SessionManager.asegurarNombreCoherenteConRutActual();

      final nombre = await SessionManager.getNombreTecnico();
      final rolStr = await SessionManager.getRol();
      final rol = (rolStr == 'supervisor' || rolStr == 'ito')
          ? RolUsuario.supervisor
          : RolUsuario.tecnico;

      final nuevo = Usuario(
        id: _deviceId ?? _usuario?.id ?? '',
        nombre: nombre.isNotEmpty ? nombre : rut,
        telefono: rut,
        email: '$rut@crea.cl',
        rol: rol,
        ultimaConexion: DateTime.now(),
      );

      if (_usuario != null &&
          _registroEstado == RegistroEstado.registrado &&
          _usuario!.nombre == nuevo.nombre &&
          _usuario!.telefono == nuevo.telefono &&
          _usuario!.rol == nuevo.rol) {
        return;
      }

      _usuario = nuevo;
      _registroEstado = RegistroEstado.registrado;
      notifyListeners();
    } catch (e) {
      print('⚠️ syncUsuarioDesdePrefs: $e');
    }
  }
}
