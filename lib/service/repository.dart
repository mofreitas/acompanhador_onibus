import 'dart:async';
import 'dart:convert';
import 'package:acompanhador_onibus_congresso/dominio/configuracao.dart';
import 'package:acompanhador_onibus_congresso/dominio/contatos.dart';
import 'package:acompanhador_onibus_congresso/service/routes_service.dart';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:acompanhador_onibus_congresso/dominio/onibus_congregacao.dart';
import 'package:acompanhador_onibus_congresso/provider.dart';
import 'package:acompanhador_onibus_congresso/firebase_options.dart';
import 'package:acompanhador_onibus_congresso/service/local_data.dart';
import 'package:acompanhador_onibus_congresso/dominio/usuario.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class Repository{

  Repository();

  StreamSubscription<DatabaseEvent>? _streamAddOnibus;
  StreamSubscription<DatabaseEvent>? _streamUpdateOnibus;
  StreamSubscription<DatabaseEvent>? _streamRemoveOnibus;
  StreamSubscription<DatabaseEvent>? _streamAtualizaConfig;
  StreamSubscription<DatabaseEvent>? _streamUsuarioLogadoOnibus;
  StreamSubscription<DatabaseEvent>? _streamConectividadeInternet;
  StreamSubscription<DatabaseEvent>? _streamAtualizaStatusOnibus;
  StreamSubscription<DatabaseEvent>? _streamAtualizaHoraPrevistaOnibus;

  //Throttler? _throttlerFirebase;

  static Future iniciaFirebase() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  Future<String> getUuid() async {
    String? localUuid = await LocalData.getUuid();
    if(localUuid != null){
      return localUuid;
    }

    localUuid = Uuid().v4();
    await LocalData.salvarUuid(localUuid);
    return localUuid;
  }

  Future<Usuario?> efetuaLogin(String numeroCongregacao, String senha) async {
      var congregacaoBanco = await FirebaseDatabase.instance.ref("congregacoes_login").orderByChild("senha").equalTo(_getHashSenha(senha)).get();

      if(congregacaoBanco.hasChild(numeroCongregacao)){
        DataSnapshot snapshot = congregacaoBanco.child(numeroCongregacao);
        String numero = snapshot.key.toString();
        String nome = snapshot.child(Usuario.NOME).value.toString();

        Usuario usuarioLogado = Usuario(nome, numero);
        await LocalData.salvarUsuarioLogado(usuarioLogado);

        String uuid  = await getUuid();
        if(!usuarioLogado.isAdmin()) {
          await FirebaseDatabase.instance.ref(
              "onibus/$numero/usuario_logado").set(uuid);
        }

        return usuarioLogado;
      }

      return null;
  }

  Future atualizaSituacaoOnibus(String numeroOnibus, bool situacao) async {
    await FirebaseDatabase.instance.ref(
        "onibus/$numeroOnibus/ativo").set(situacao);
  }

  Future<Usuario?> getUsuarioLogado() async {
    return LocalData.getUsuarioLogado();
  }

  Future<List<Usuario>> getCongregacoes() async {
    DataSnapshot congregacoesBanco = await FirebaseDatabase.instance.ref().child("congregacoes_nomes").orderByKey().get().timeout(Duration(seconds: 20));
    return congregacoesBanco.children.map((element) {
      String nome = element.value.toString();
      String numero = element.key.toString();

      return Usuario(nome, numero);
    }).toList();
  }

  Future<UsuarioOnibusProvider> getUsuarioOnibusProvider(String numeroOnibus) async {
    UsuarioOnibusProvider usuarioOnibusProvider = UsuarioOnibusProvider();
    _streamUsuarioLogadoOnibus?.cancel();

    final Completer<UsuarioOnibusProvider> valorPreenchido = Completer<UsuarioOnibusProvider>();

    _streamUsuarioLogadoOnibus = FirebaseDatabase.instance.ref("onibus/$numeroOnibus/usuario_logado").onValue.listen((DatabaseEvent event){
      usuarioOnibusProvider.usuarioLogadoOnibusUuid = event.snapshot.value?.toString() ?? "";

      if(!valorPreenchido.isCompleted){
        valorPreenchido.complete(usuarioOnibusProvider);
      }
    });

    return valorPreenchido.future;
  }

  Future<ConfigProvider> getConfiguracoesProvider() async {
    final ConfigProvider configProvider = ConfigProvider();
    _streamAtualizaConfig?.cancel();

    final Completer<ConfigProvider> primeiroValorRecebido = Completer<ConfigProvider>();

    _streamAtualizaConfig = FirebaseDatabase.instance.ref("conf").onValue.listen((DatabaseEvent event) {
      DataSnapshot configSnapshot = event.snapshot;

      String localizacaoCentroString = configSnapshot.child(Config.LOCALIZACAO_CENTRO).value
          .toString();
      List<String> coordenadas = localizacaoCentroString.split(",");
      double latitude = double.parse(coordenadas[0]);
      double longitude = double.parse(coordenadas[1]);
      LatLng localizacaoCentro = LatLng(latitude, longitude);

      bool envioAtivo = bool.parse(configSnapshot.child(Config.ENVIO_ATIVO).value.toString());
      int tempoAtualizacaoETA = int.parse(configSnapshot.child(Config.TEMPO_ATUALIZACAO_ETA).value.toString());
      int tempoAtualizacaoLocalizacao = int.parse(configSnapshot.child(Config.TEMPO_ATUALIZACAO_LOCALIZACAO).value.toString());
      int distanciaMinimaFuncionamento = int.parse(
          configSnapshot.child(Config.DISTANCIA_MINIMA_FUNCIONAMENTO).value.toString());
      int tempoInativacao = int.parse(configSnapshot.child(Config.TEMPO_INATIVACAO).value.toString());
      int tempoDivergencia = int.parse(configSnapshot.child(Config.TEMPO_DIVERGENCIA).value.toString());

      List<Contato> contatosList = [];
      for (DataSnapshot contatoSnapshot in configSnapshot.child(Config.CONTATOS_ADMIN).children) {
        Contato contato = Contato(
            contatoSnapshot.key!, contatoSnapshot.value!.toString());
        contatosList.add(contato);
      }

      configProvider.config =
          Config(envioAtivo: envioAtivo,
              contatosAdmin: contatosList,
              localizacaoCentro: localizacaoCentro,
              distanciaMinimaFuncionamento: distanciaMinimaFuncionamento,
              tempoInativacao: tempoInativacao,
              tempoAtualizacaoEta: tempoAtualizacaoETA,
              tempoAtualizacaoLocalizacao: tempoAtualizacaoLocalizacao,
              tempoDivergencia: tempoDivergencia);

      if(!primeiroValorRecebido.isCompleted){
        primeiroValorRecebido.complete(configProvider);
      }
    });

    return primeiroValorRecebido.future;
  }

  Future enviaLocalizacaoAtual(Usuario usuario, LatLng localizacaoOnibus, bool? chegouCentro, RouteResponse? response) async {
    var posicionamentoString = "${localizacaoOnibus.latitude}, ${localizacaoOnibus.longitude}";

    Map<String, Object?> requestBody = {
      OnibusCongregacao.LOCALIZACAO : posicionamentoString,
      OnibusCongregacao.ULTIMA_ATUALIZACAO_LOCALIZACAO : ServerValue.timestamp
    };

    if(response != null) {
      requestBody.addAll({
        OnibusCongregacao.ETA: response.eta,
        //"distancia": response.distancia,
        OnibusCongregacao.ULTIMA_ATUALIZACAO_ETA: ServerValue.timestamp
      });
    }

    if(chegouCentro != null){
      requestBody.addAll({
        OnibusCongregacao.CHEGOU_CENTRO: chegouCentro
      });
    }

    return FirebaseDatabase.instance.ref("onibus")
        .child(usuario.numero)
        .update(requestBody);
  }

  Future atualizaLocalizacaoTodosOnibus(bool valor) async {
    await FirebaseDatabase.instance.ref("conf").update({"envio_ativo": valor});
  }

  Future<StatusOnibusProvider> getSituacaoOnibusProvider(Usuario usuarioLogado){
    StatusOnibusProvider statusOnibusProvider = StatusOnibusProvider();
    _streamAtualizaStatusOnibus?.cancel();

    final Completer<StatusOnibusProvider> primeiroValorRecebido = Completer<StatusOnibusProvider>();

    _streamAtualizaStatusOnibus = FirebaseDatabase.instance.ref("onibus/${usuarioLogado.numero}/ativo").onValue.listen((DatabaseEvent event) {
      DataSnapshot snapshot = event.snapshot;
      bool ativo = bool.parse(snapshot.value?.toString() ?? "false");

      statusOnibusProvider.ativo = ativo;

      if(!primeiroValorRecebido.isCompleted){
        primeiroValorRecebido.complete(statusOnibusProvider);
      }
    });

    return primeiroValorRecebido.future;
  }

  Future<HoraPrevistaOnibusProvider> getHoraPrevistaOnibusProvider(Usuario usuarioLogado){
    HoraPrevistaOnibusProvider horaPrevistaOnibusProvider = HoraPrevistaOnibusProvider();
    _streamAtualizaHoraPrevistaOnibus?.cancel();

    final Completer<HoraPrevistaOnibusProvider> primeiroValorRecebido = Completer<HoraPrevistaOnibusProvider>();

    _streamAtualizaHoraPrevistaOnibus = FirebaseDatabase.instance.ref("onibus/${usuarioLogado.numero}/hr_prevista").onValue.listen((DatabaseEvent event) {
      DataSnapshot snapshot = event.snapshot;
      String? horaPrevistaString = snapshot.value?.toString();

      DateTime horaPrevista = DateTime.now();
      if(horaPrevistaString != null) {
        List<String> horaPrevistaList = horaPrevistaString.split(":");
        int hora = int.parse(horaPrevistaList[0]);
        int minuto = int.parse(horaPrevistaList[1]);

        DateTime horaAtual = DateTime.now();
        horaPrevista = DateTime(
            horaAtual.year, horaAtual.month, horaAtual.day, hora, minuto);
      }

      horaPrevistaOnibusProvider.horaPrevista = horaPrevista;

      if(!primeiroValorRecebido.isCompleted){
        primeiroValorRecebido.complete(horaPrevistaOnibusProvider);
      }
    });

    return primeiroValorRecebido.future;
  }

  String _getHashSenha(String senha){
    String salt = '';//dotenv.env['PASS_SALT'] ?? '';
    var bytes = utf8.encode(senha + salt);
    var digest = sha1.convert(bytes);
    return digest.toString();
  }

  close(){
    _streamAddOnibus?.cancel();
    _streamUpdateOnibus?.cancel();
    _streamRemoveOnibus?.cancel();
    _streamAtualizaConfig?.cancel();
    _streamUsuarioLogadoOnibus?.cancel();
    _streamConectividadeInternet?.cancel();
    _streamAtualizaStatusOnibus?.cancel();
    _streamAtualizaHoraPrevistaOnibus?.cancel();
  }
}

class Throttler {
  final Duration _timeout;
  Timer? _timer;
  Function? _callback;

  Throttler(this._timeout);

  void run(Function() callback){
    _callback = callback;

    _timer ??= Timer.periodic(_timeout, (timer) {
      if(_callback != null){
        _callback!();
      }
      else {
        cancel();
      }
      _callback = null;
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}

class StreamOnibus {
  final List<OnibusCongregacao> _onibusCongregacoes = [];

  late StreamController<List<OnibusCongregacao>> _controller;
  StreamSubscription<DatabaseEvent>? _streamAddOnibus;
  StreamSubscription<DatabaseEvent>? _streamUpdateOnibus;
  StreamSubscription<DatabaseEvent>? _streamRemoveOnibus;
  final Throttler _throttler = Throttler(Duration(seconds: 30));

  final DatabaseReference _databaseReferenceOnibus;

  final Config _config;
  Timer? _timer;

  StreamOnibus(this._config) :
        _databaseReferenceOnibus = FirebaseDatabase.instance.ref("onibus")
  {
    void timerTick(_){
      bool algumInativado = false;
      for (var item in _onibusCongregacoes) {
        if(item.ativo && !item.inativoTempo &&
            DateTime.now().difference(item.ultimaAtualizacao).compareTo(_config.tempoInativacao) > 0) {
          item.inativoTempo = true;
          algumInativado = true;
        }
      }

      if(algumInativado){
        _throttler.run(() {
          _onibusCongregacoes.sort();
          _controller.add(_onibusCongregacoes);
        });
      }
    }

    void iniciaStreams(){
      _streamAddOnibus = _databaseReferenceOnibus.onChildAdded.listen((DatabaseEvent event) async {
        DataSnapshot snapshot = event.snapshot;
        OnibusCongregacao onibusCongregacao = OnibusCongregacao.fromSnapshot(snapshot);
        onibusCongregacao.setInativoTempoTimeout(_config);

        _onibusCongregacoes.add(onibusCongregacao);

        _throttler.run(() {
          _onibusCongregacoes.sort();
          _controller.add(_onibusCongregacoes);
        });
      });
      _streamUpdateOnibus = _databaseReferenceOnibus.onChildChanged.listen((DatabaseEvent event) async {
        DataSnapshot snapshot = event.snapshot;
        OnibusCongregacao onibusCongregacao = OnibusCongregacao.fromSnapshot(snapshot);
        onibusCongregacao.setInativoTempoTimeout(_config);

        int indexRemocao = _onibusCongregacoes.indexWhere((item) => item.numeroOnibus == onibusCongregacao.numeroOnibus);
        onibusCongregacao.zIndex = _onibusCongregacoes[indexRemocao].zIndex;
        _onibusCongregacoes.removeAt(indexRemocao);
        _onibusCongregacoes.add(onibusCongregacao);

        _throttler.run(() {
          _onibusCongregacoes.sort();
          _controller.add(_onibusCongregacoes);
        });
      });
      _streamRemoveOnibus = _databaseReferenceOnibus.onChildRemoved.listen((DatabaseEvent event) async {
        DataSnapshot snapshot = event.snapshot;
        OnibusCongregacao onibusCongregacao = OnibusCongregacao.fromSnapshot(snapshot);
        _onibusCongregacoes.removeWhere((item) => item.numeroOnibus == onibusCongregacao.numeroOnibus);

        _throttler.run(() {
          _controller.add(_onibusCongregacoes);
        });
      });

      _timer = Timer.periodic(Duration(seconds: 10), timerTick);
    }

    void pauseStreams(){
      _streamAddOnibus?.pause();
      _streamUpdateOnibus?.pause();
      _streamRemoveOnibus?.pause();
      _throttler.cancel();
      _timer?.cancel();
    }

    void resumeStreams(){
      _streamAddOnibus?.resume();
      _streamUpdateOnibus?.resume();
      _streamRemoveOnibus?.resume();
      _timer = Timer.periodic(Duration(seconds: 10), timerTick);
    }

    void cancelStreams(){
      _streamAddOnibus?.cancel();
      _streamUpdateOnibus?.cancel();
      _streamRemoveOnibus?.cancel();
      _throttler.cancel();
      _timer?.cancel();
    }

    _controller = StreamController<List<OnibusCongregacao>>(
        onListen: iniciaStreams,
        onPause: pauseStreams,
        onCancel: cancelStreams,
        onResume: resumeStreams
    );
  }

  Stream<List<OnibusCongregacao>> get stream => _controller.stream;
}