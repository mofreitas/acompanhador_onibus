import 'package:acompanhador_onibus_congresso/dominio/configuracao.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';


class ConfigProvider extends ChangeNotifier {
  Config _config = Config();

  Config get config => _config;

  set config(Config config) {
    _config = config;
    notifyListeners();
  }
}


class UsuarioOnibusProvider {
  String usuarioLogadoOnibusUuid = "";
}

class AdminOnibusProvider extends ChangeNotifier {
  bool _adminLogado = false;

  set adminLogado(bool admLogado) {
    _adminLogado = admLogado;

    notifyListeners();
  }

  bool get adminLogado => _adminLogado;
}

class ConectividadeProvider extends ChangeNotifier {
  bool _conectado = true;

  set conectado(bool conectado) {
    _conectado = conectado;
    notifyListeners();
  }

  bool get conectado => _conectado;
}

class StatusOnibusProvider extends ChangeNotifier {
  bool _ativo = true;

  set ativo(bool ativo) {
    _ativo = ativo;
    notifyListeners();
  }

  bool get ativo => _ativo;
}

class HoraPrevistaOnibusProvider extends ChangeNotifier {

  static final DateFormat formatter = DateFormat('HH:mm');

  DateTime? _horaPrevista;

  set horaPrevista(DateTime? horaPrevista) {
    _horaPrevista = horaPrevista;
    notifyListeners();
  }

  DateTime? get horaPrevista => _horaPrevista;

  String? getHoraPrevistaString() {
    return _horaPrevista == null ? null : formatter.format(_horaPrevista!);
  }

  bool isAtrasado(DateTime eta, Config config){
    if(_horaPrevista == null) return false;
    return eta.difference(horaPrevista!).compareTo(config.tempoDivergencia) > 0;
  }

  bool isAdiantado(DateTime eta, Config config){
    if(_horaPrevista == null) return false;
    return horaPrevista!.difference(eta).compareTo(config.tempoDivergencia) > 0;
  }
}