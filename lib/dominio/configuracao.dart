import 'package:acompanhador_onibus_congresso/dominio/contatos.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
//import 'package:latlong2/latlong.dart';

class Config {

  static final String ENVIO_ATIVO = "envio_ativo";
  static final String CONTATOS_ADMIN = "contato_admin";
  static final String LOCALIZACAO_CENTRO = "loc_centro";
  static final String TEMPO_ATUALIZACAO_ETA = "ta_eta";
  static final String TEMPO_ATUALIZACAO_LOCALIZACAO = "ta_loc";
  static final String DISTANCIA_MINIMA_FUNCIONAMENTO = "dm_func";
  static final String TEMPO_INATIVACAO = "tempo_inat";
  static final String TEMPO_DIVERGENCIA = "tempo_divergencia";

  bool envioAtivo;
  List<Contato> contatosAdmin;
  LatLng localizacaoCentro;
  Duration tempoAtualizacaoEta;
  Duration tempoAtualizacaoLocalizacao;
  int distanciaMinimaFuncionamento;
  Duration tempoInativacao;
  Duration tempoDivergencia;

  Config({this.envioAtivo = false,
    this.contatosAdmin = const [],
    this.localizacaoCentro = const LatLng(0,0),
    this.distanciaMinimaFuncionamento = 200,
    int tempoInativacao = 1800,
    int tempoAtualizacaoEta = 300,
    int tempoAtualizacaoLocalizacao = 30,
    int tempoDivergencia = 600}) :
        tempoAtualizacaoEta = Duration(seconds: tempoAtualizacaoEta),
        tempoAtualizacaoLocalizacao = Duration(seconds: tempoAtualizacaoLocalizacao),
        tempoInativacao = Duration(seconds: tempoInativacao),
        tempoDivergencia = Duration(seconds: tempoDivergencia);
}