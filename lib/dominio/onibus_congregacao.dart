import 'dart:core';
import 'dart:math';
import 'package:acompanhador_onibus_congresso/dominio/configuracao.dart';
import 'package:acompanhador_onibus_congresso/dominio/tipo_veiculo.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import 'package:firebase_database/firebase_database.dart';

class OnibusCongregacao implements Comparable<OnibusCongregacao> {

  static final String ATIVO = "ativo";
  static final String ETA = "eta";
  static final String LOCALIZACAO = "localizacao";
  static final String CONTATO = "contato";
  static final String ULTIMA_ATUALIZACAO_LOCALIZACAO = "ua_localizacao";
  static final String ULTIMA_ATUALIZACAO_ETA = "ua_eta";
  static final String CHEGOU_CENTRO = "chegou_centro";
  static final String TIPO_VEICULO = "tipo";
  static final String CIDADE = "cidade";
  static final String NOME_CONGREGACAO = "nome";
  static final String HORA_CHEGADA_PREVISTA = "hr_prevista";
  static final String NOME_CAPITAO = "nome_capitao";

  static final DateFormat formatter = DateFormat('HH:mm');

  final String nomeCongregacao;
  final String? cidade;
  final String? contato;
  final TipoVeiculo tipoVeiculo;
  final String _numeroOnibus;
  final String? nomeCapitao;
  DateTime eta = DateTime(0);
  LatLng? localizacao;
  DateTime ultimaAtualizacao = DateTime(0);
  DateTime ultimaAtualizacaoEta = DateTime(0);
  DateTime horaPrevista = DateTime(0);
  bool ativo = true;
  bool inativoTempo = false;
  bool chegouCentro = false;
  Marker? marcador;
  int hueIdentificadorGrupo = 0;
  int zIndex = 0;

  OnibusCongregacao(this._numeroOnibus, this.cidade, this.nomeCongregacao, this.nomeCapitao, this.contato, this.tipoVeiculo);

  factory OnibusCongregacao.fromSnapshot(DataSnapshot snapshot){
    String numeroOnibus = snapshot.key.toString();
    String? contato = snapshot.child(CONTATO).value?.toString();
    int eta = int.parse(snapshot.child(ETA).value?.toString() ?? "0");
    bool ativo = bool.parse(snapshot.child(ATIVO).value?.toString() ?? "false");
    int ultimaAtualizacao = int.parse(snapshot.child(ULTIMA_ATUALIZACAO_LOCALIZACAO).value?.toString() ?? "0");
    int ultimaAtualizacaoEta = int.parse(snapshot.child(ULTIMA_ATUALIZACAO_ETA).value?.toString() ?? "0");
    String? coordenadasString = snapshot.child(LOCALIZACAO).value?.toString();
    bool chegouCentro = bool.parse(snapshot.child(CHEGOU_CENTRO).value?.toString() ?? "false");
    TipoVeiculo tipoVeiculo = TipoVeiculo.values[int.parse(snapshot.child(TIPO_VEICULO).value?.toString() ?? "0")];
    String nomeCongregacao = snapshot.child(NOME_CONGREGACAO).value.toString();
    String? nomeCapitao = snapshot.child(NOME_CAPITAO).value?.toString();
    String? cidade = snapshot.child(CIDADE).value?.toString();
    String? horaPrevistaString = snapshot.child(HORA_CHEGADA_PREVISTA).value?.toString();
    int hueIdentificadorGrupo = 0;

    DateTime horaPrevista = DateTime.now();
    if(horaPrevistaString != null) {
      List<String> horaPrevistaList = horaPrevistaString.split(":");
      int hora = int.parse(horaPrevistaList[0]);
      int minuto = int.parse(horaPrevistaList[1]);

      DateTime horaAtual = DateTime.now();
      horaPrevista = DateTime(horaAtual.year, horaAtual.month, horaAtual.day, hora, minuto);
    }

    LatLng? localizacao;
    if(coordenadasString != null) {
      List<String> coordenadasList = coordenadasString.split(",");
      double latitude = double.parse(coordenadasList[0]);
      double longitude = double.parse(coordenadasList[1]);

      localizacao = LatLng(latitude, longitude);
    }

    if(horaPrevistaString != null ) {
      hueIdentificadorGrupo =
          Random(int.tryParse(horaPrevistaString.replaceAll(RegExp(r'\D'), "")) ?? 0).nextInt(360);
    }

    OnibusCongregacao onibus = OnibusCongregacao(numeroOnibus, cidade, nomeCongregacao, nomeCapitao, contato, tipoVeiculo);
    onibus.localizacao = localizacao;
    onibus.ativo = ativo;
    onibus.ultimaAtualizacao = DateTime.fromMillisecondsSinceEpoch(ultimaAtualizacao);
    onibus.ultimaAtualizacaoEta = DateTime.fromMillisecondsSinceEpoch(ultimaAtualizacaoEta);
    onibus.eta = onibus.ultimaAtualizacaoEta.add(Duration(seconds: eta));
    onibus.chegouCentro = chegouCentro;
    onibus.horaPrevista = horaPrevista;
    onibus.hueIdentificadorGrupo = hueIdentificadorGrupo;

    return onibus;
  }
  
  String get numeroOnibus => _numeroOnibus.toString().padLeft(3, "0");

  Map toJson(){
    return {
      "nome_congregacao": nomeCongregacao,
      "contato": contato
    };
  }

  String getHoraChegadaString() {
    return formatter.format(eta);
  }

  String getHoraPrevistaString() {
    return formatter.format(horaPrevista);
  }

  String descricaoCongregacaoTipoOnibus(){
    return "$nomeCongregacao ${cidade != "" ? '- $cidade' : ''}(${tipoVeiculo.nome})";
  }

  String descricaoCongregacaoCompleta(){
    return "$nomeCongregacao ${cidade != "" ? '- $cidade' : ''}(Nº $_numeroOnibus)";
  }

  String descricaoCongregacaoCidade(){
    return "$nomeCongregacao${cidade != "" ? ' - $cidade' : ''}";
  }

  String descricaoCongregacaoNumero(){
    return "$nomeCongregacao - $_numeroOnibus";
  }

  bool isAtrasado(Config config){
    return eta.difference(horaPrevista).compareTo(config.tempoDivergencia) > 0;
  }

  bool isAdiantado(Config config){
    return horaPrevista.difference(eta).compareTo(config.tempoDivergencia) > 0;
  }

  void setInativoTempoTimeout(Config config){
    inativoTempo = ativo && !inativoTempo &&
        DateTime.now().difference(ultimaAtualizacao).compareTo(config.tempoInativacao) > 0;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is OnibusCongregacao
              && runtimeType == other.runtimeType
              && _numeroOnibus == other._numeroOnibus;

  @override
  int get hashCode => _numeroOnibus.hashCode;

  @override
  int compareTo(OnibusCongregacao other) {
    int orderThis = 0;
    int orderOther = 0;

    orderThis += ativo == false ? 150 : 0;
    orderThis += inativoTempo == true ? 100 : 0;
    orderThis += chegouCentro ? 25 : 0;

    orderOther += other.ativo == false ? 150 : 0;
    orderOther += other.inativoTempo == true ? 100 : 0;
    orderOther += other.chegouCentro ? 25 : 0;

    if(orderOther != orderThis){
      return orderThis - orderOther;
    }
    else if (!ativo || inativoTempo || chegouCentro){
      return nomeCongregacao.compareTo(other.nomeCongregacao);
    }
    else{
      return eta.compareTo(other.eta);
    }
  }
}