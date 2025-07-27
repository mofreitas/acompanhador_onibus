import 'dart:convert';

import 'package:acompanhador_onibus_congresso/dominio/usuario.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalData{

  static final String _keyUsuarioLogado = "usuario_logado";
  static final String _keyUUID = "uuid";
  static final String _keyPermissaoNotificacoesNegada = "permissao_notificacoes_negada";
  static final String _keyPermissaoNotificacoes = "permissao_notificacoes";

  static Future<Usuario?> getUsuarioLogado() async {
    final prefs = await SharedPreferences.getInstance();
    String? usuarioLogadoJson = prefs.getString(_keyUsuarioLogado);

    if(usuarioLogadoJson != null) {
      Map usuarioLogadoMap = jsonDecode(usuarioLogadoJson);
      return Usuario.fromJson(usuarioLogadoMap);
    }

    return null;
  }

  static Future salvarUsuarioLogado(Usuario usuarioLogado) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString(_keyUsuarioLogado, jsonEncode(usuarioLogado.toJson()));
  }

  static Future limparDados() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUsuarioLogado);
  }

  static Future<String?> getUuid() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUUID);
  }

  static Future salvarUuid(String uuid) async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString(_keyUUID, uuid);
  }

  static Future<bool> getPermissoesNotificacoesNegada() async {
    final prefs = await SharedPreferences.getInstance();
    return bool.parse(prefs.getString(_keyPermissaoNotificacoesNegada) ?? 'false');
  }

  static Future salvarPermissoesNotificacoesNegada() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString(_keyPermissaoNotificacoesNegada, "true");
  }

  static Future<bool> getPermissoesNotificacoesExibida() async {
    final prefs = await SharedPreferences.getInstance();
    return bool.parse(prefs.getString(_keyPermissaoNotificacoes) ?? 'false');
  }

  static Future salvarPermissoesNotificacoesExibida() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString(_keyPermissaoNotificacoes, "true");
  }
}