// Tests para los parsers puros de [OntWifiService].
//
// Las fixtures en `test/fixtures/` son respuestas reales capturadas contra una
// ONT Huawei HG8145X6 (firmware CHILECLARO2) en el ambiente de pruebas. El
// objetivo es que cualquier cambio futuro al parser no rompa silenciosamente
// la lectura de los datos del firmware del operador.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:agente_desconexiones/services/ont_wifi_service.dart';

String _readFixture(String name) {
  final f = File('test/fixtures/$name');
  return f.readAsStringSync();
}

void main() {
  group('parseTopologyForTest', () {
    test('parsea fixture real de ONT', () {
      final body = _readFixture('topology.txt');
      final topo = OntWifiService.parseTopologyForTest(body);

      expect(topo, hasLength(1));
      final main = topo.first;
      expect(main['DevType'], 'HG8145X6-13');
      expect(main['SN'], '4857544324C4EFB4');
      expect(main['MAC'], '78:EB:46:AA:09:B7');
      expect(main['IP'], '192.168.1.50');
      expect(main['Level'], '1');

      final subStas = main['sub_sta'] as List;
      expect(subStas, hasLength(1));
      final s = subStas.first as Map;
      expect(s['MAC'], '08:6d:41:d9:e6:e8');
      expect(s['HostName'], 'Air-de-Jonathan');
      expect(s['AccessType'], 'Wireless');
      expect(s['WifiFreq'], '5G');
      expect(s['WirelessMode'], '11ac');
    });

    test('respuesta vacía "NONE" devuelve lista vacía', () {
      expect(OntWifiService.parseTopologyForTest('"NONE"'), isEmpty);
      expect(OntWifiService.parseTopologyForTest(''), isEmpty);
      expect(OntWifiService.parseTopologyForTest('   '), isEmpty);
    });

    test('respuesta basura no crashea, devuelve lista vacía', () {
      expect(OntWifiService.parseTopologyForTest('not-a-json'), isEmpty);
      expect(OntWifiService.parseTopologyForTest('<html>oops</html>'), isEmpty);
    });
  });

  group('parseWlanClientsForTest', () {
    test('parsea fixture real de RSSI dBm', () {
      final body = _readFixture('wlan_associated.txt');
      final readings = OntWifiService.parseWlanClientsForTest(body);

      expect(readings, hasLength(1));
      final r = readings['08:6D:41:D9:E6:E8'];
      expect(r, isNotNull);
      expect(r!.rssiDbm, -80);
      expect(r.snrDb, -1);
      expect(r.signalQualityPct, 14);
      expect(r.wirelessMode, '11ac');
      expect(r.ip, '192.168.1.24');
      expect(r.hostname, 'Air-de-Jonathan');
      expect(r.antennas, '2*2');
      expect(r.band, '5G');
      expect(r.ssidIndex, 5);
    });

    test('respuesta sin clientes devuelve mapa vacío', () {
      expect(OntWifiService.parseWlanClientsForTest('function(){return new Array(null);}'),
          isEmpty);
    });
  });

  group('parseDevicesFromResponses (end-to-end con fixtures reales)', () {
    test('cruza topología con RSSI dBm y produce OntDevice válido', () {
      final wlan = _readFixture('wlan_associated.txt');
      final topo = _readFixture('topology.txt');

      final result = OntWifiService.parseDevicesFromResponses(wlan, topo);

      expect(result.ontMac, '78:EB:46:AA:09:B7');
      expect(result.ontModel, 'HG8145X6-13');
      expect(result.ontSerial, '4857544324C4EFB4');

      expect(result.devices, hasLength(1));
      final d = result.devices.first;
      expect(d.mac, '08:6D:41:D9:E6:E8');
      expect(d.name, 'Air-de-Jonathan');
      expect(d.ip, '192.168.1.24');
      expect(d.rssi, -80, reason: 'dBm real del endpoint A, no la calidad');
      expect(d.rssiKnown, isTrue);
      expect(d.isWired, isFalse);
      expect(d.band, '5G');
      expect(d.es5GHz, isTrue);
      expect(d.esCableado, isFalse);
      expect(d.parentIsOnt, isTrue);
      expect(d.parentMac, '78:EB:46:AA:09:B7');
      expect(d.calidad, 'Crítico'); // -80 dBm < -75
    });

    test('topología vacía devuelve devices vacíos pero no falla', () {
      final result = OntWifiService.parseDevicesFromResponses('', '"NONE"');
      expect(result.devices, isEmpty);
      expect(result.ontMac, isNull);
      expect(result.ontModel, isNull);
    });

    test('cliente colgado de repetidor (no en wlanByMac del ONT) → rssiKnown=false', () {
      // ONT principal sin clientes + un repetidor con un cliente.
      const topo = '['
          '{APInst:"33",DevType:"HG8145X6-13",SN:"X1",Level:"1",'
          'AccessType:"2",MAC:"AA:BB:CC:DD:EE:01",IP:"192.168.1.50",'
          'sub_sta:[]},'
          '{APInst:"40",DevType:"WS5200",SN:"R1",Level:"2",'
          'AccessType:"Wireless",MAC:"BB:BB:BB:BB:BB:01",IP:"192.168.1.51",'
          'sub_sta:[{HostName:"Cliente repetidor",MAC:"11:22:33:44:55:66",'
          'IP:"192.168.1.99",AccessType:"Wireless",AccessPort:"5",'
          'WifiFreq:"5G",WirelessMode:"11ac",rssi:"50"}]}'
          ']';
      final result = OntWifiService.parseDevicesFromResponses('', topo);
      expect(result.devices, hasLength(1));
      final d = result.devices.first;
      expect(d.parentIsOnt, isFalse);
      expect(d.parentMac, 'BB:BB:BB:BB:BB:01');
      expect(d.rssiKnown, isFalse);
      expect(d.calidad, 'Sin lectura');
      expect(d.rssi, -90);
    });

    test('WiFi sin IP (DHCP en curso) sí aparece desde wlanByMac', () {
      // El test del bug crítico: el endpoint A trae un device que la topología
      // NO trae aún (porque DHCP no completó). La app debe mostrarlo.
      const wlan = '''
function() {
  return new Array(
    new stAssociatedDevice("InternetGatewayDevice\\x2eLANDevice\\x2e1\\x2eWLANConfiguration\\x2e5\\x2eAssociatedDevice\\x2e1",
      "AA\\x3aAA\\x3aAA\\x3aAA\\x3aAA\\x3a01",
      "120","100","200","\\x2d65","\\x2d90","25","30","11ax",
      "0","0","0","0\\x2e0\\x2e0\\x2e0","","2\\x2a2","0","0","1","1","0"),
    null);
}''';
      const topo = '[{APInst:"33",DevType:"HG8145X6-13",SN:"X1",Level:"1",'
          'AccessType:"2",MAC:"BB:BB:BB:BB:BB:01",IP:"192.168.1.50",'
          'sub_sta:[]}]';
      final result = OntWifiService.parseDevicesFromResponses(wlan, topo);
      expect(result.devices, hasLength(1));
      final d = result.devices.first;
      expect(d.mac, 'AA:AA:AA:AA:AA:01');
      expect(d.rssiKnown, isTrue);
      expect(d.rssi, -65);
      expect(d.ip, ''); // 0.0.0.0 se ignora
      expect(d.parentIsOnt, isTrue);
    });
  });

  group('parseNeighboursFromResponse', () {
    test('parsea ejemplo real con 2.4G y 5G', () {
      const body = '''
function() {
  return new Array(
    new stNeighbourAP("InternetGatewayDevice.LANDevice.1.WiFi.Radio.1.X_HW_NeighborAP.1",
      "Wifi-Vecino","DE\\x3a4F\\x3a22\\x3a10\\x3a02\\x3aDB",
      "AP","6","\\x2d54","\\x2d90","1","100","WPA2-PSK","11b/g/n","300"),
    new stNeighbourAP("InternetGatewayDevice.LANDevice.1.WiFi.Radio.2.X_HW_NeighborAP.1",
      "Wifi-Vecino-5G","DE\\x3a4F\\x3a22\\x3a10\\x3a02\\x3aDC",
      "AP","36","\\x2d22","\\x2d90","1","100","WPA2-PSK","11ac","867"),
    null);
}''';
      final list = OntWifiService.parseNeighboursFromResponse(body);
      expect(list, hasLength(2));
      expect(list[0].ssid, 'Wifi-Vecino');
      expect(list[0].band, '2.4G');
      expect(list[0].channel, 6);
      expect(list[0].rssiDbm, -54);
      expect(list[1].ssid, 'Wifi-Vecino-5G');
      expect(list[1].band, '5G');
      expect(list[1].channel, 36);
      expect(list[1].rssiDbm, -22);
    });

    test('respuesta vacía', () {
      expect(OntWifiService.parseNeighboursFromResponse('function() { return new Array(null); }'), isEmpty);
      expect(OntWifiService.parseNeighboursFromResponse(''), isEmpty);
    });

    test('cliente Ethernet queda como cableado (sin RSSI)', () {
      const topo = '[{APInst:"33",DevType:"HG8145X6-13",SN:"X1",Level:"1",'
          'AccessType:"2",MAC:"AA:BB:CC:DD:EE:01",IP:"192.168.1.50",'
          'sub_sta:[{HostName:"PC Sala",MAC:"AA:11:22:33:44:55",'
          'IP:"192.168.1.10",AccessType:"Ethernet",AccessPort:"1"}]}]';
      final result = OntWifiService.parseDevicesFromResponses('', topo);
      expect(result.devices, hasLength(1));
      final d = result.devices.first;
      expect(d.esCableado, isTrue);
      expect(d.banda, 'Cable');
      expect(d.calidad, 'Cableado');
      expect(d.colorCalidad.toARGB32(), 0xFF00D9FF);
    });
  });
}
