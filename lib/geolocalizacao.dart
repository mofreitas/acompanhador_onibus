import 'package:acompanhador_onibus_congresso/utils/exception.dart';
import 'package:geolocator/geolocator.dart';

class Geolocalizacao{

  static Future requisitaPermissao() async {
    LocationPermission permission;
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        // Permissions are denied, next time you could try
        // requesting permissions again (this is also where
        // Android's shouldShowRequestPermissionRationale
        // returned true. According to Android guidelines
        // your App should show an explanatory UI now.
        return false;
      }
    }
    return true;
  }

  static Future isPermissaoServicoLocalizacao() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if(permission == LocationPermission.deniedForever){
      throw ErroMensagem(
          'Permissão de localização está permanente bloqueado pelo seu celular. Por favor, habilite novamente nas configurações.');
    }

    return permission != LocationPermission.denied;
  }

  static Future isServicoLocalizacaoHabilitado() async {
    return await Geolocator.isLocationServiceEnabled();
  }
}