import 'dart:async';

import 'package:acompanhador_onibus_congresso/dominio/configuracao.dart';
import 'package:acompanhador_onibus_congresso/confirmacao.dart';
import 'package:acompanhador_onibus_congresso/geolocalizacao.dart';
import 'package:acompanhador_onibus_congresso/loading_screen.dart';
import 'package:acompanhador_onibus_congresso/service/local_data.dart';
import 'package:acompanhador_onibus_congresso/main.dart';
import 'package:acompanhador_onibus_congresso/provider.dart';
import 'package:acompanhador_onibus_congresso/service/repository.dart';
import 'package:acompanhador_onibus_congresso/service/routes_service.dart';
import 'package:acompanhador_onibus_congresso/snackbar_global.dart';
import 'package:acompanhador_onibus_congresso/dominio/usuario.dart';
import 'package:acompanhador_onibus_congresso/utils/exception.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class UserApp extends StatefulWidget {
  final Usuario usuario;

  const UserApp(this.usuario, {super.key});


  @override
  State createState() => _UserApp();
}

class _UserApp extends State<UserApp> {
  late Repository _repository;
  late Future<ConfigProvider> _futureConfigProvider;
  late Future<String> _futureUuid;
  late Future<UsuarioOnibusProvider> _futureUsuarioOnibusProvider;
  late Future<StatusOnibusProvider> _futureStatusOnibusProvider;
  late Future<HoraPrevistaOnibusProvider> _futureHoraPrevistaOnibusProvider;

  @override
  void initState() {
    _repository = Repository();
    _futureConfigProvider = _repository.getConfiguracoesProvider();
    _futureUuid = _repository.getUuid();
    _futureUsuarioOnibusProvider = _repository.getUsuarioOnibusProvider(widget.usuario.numero);
    _futureStatusOnibusProvider = _repository.getSituacaoOnibusProvider(widget.usuario);
    _futureHoraPrevistaOnibusProvider = _repository.getHoraPrevistaOnibusProvider(widget.usuario);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
        canPop: false,
        child: FutureBuilder(
        future: Future.wait([
          _futureConfigProvider,
          _futureUuid,
          _futureUsuarioOnibusProvider,
          _futureStatusOnibusProvider,
          _futureHoraPrevistaOnibusProvider
        ]),
        builder: (context, snapshot) {
          if(snapshot.connectionState == ConnectionState.done) {
            ConfigProvider configProvider = snapshot.data?[0] as ConfigProvider;
            String uuid = snapshot.data?[1] as String;
            UsuarioOnibusProvider usuarioOnibusLogadoProvider = snapshot.data?[2] as UsuarioOnibusProvider;
            StatusOnibusProvider statusOnibusProvider = snapshot.data?[3] as StatusOnibusProvider;
            HoraPrevistaOnibusProvider horaPrevistaOnibusProvider = snapshot.data?[4] as HoraPrevistaOnibusProvider;
            return UserWidget(widget.usuario, configProvider, uuid, usuarioOnibusLogadoProvider, statusOnibusProvider, horaPrevistaOnibusProvider);
          }
          else{
            return LoadingScreen();
          }
        }
    ));
  }

  @override
  void dispose() {
    _repository.close();
    super.dispose();
  }
}

class UserWidget extends StatefulWidget {
  final Usuario usuario;
  final ConfigProvider configProvider;
  final String uuid;
  final UsuarioOnibusProvider usuarioOnibusProvider;
  final StatusOnibusProvider statusOnibusProvider;
  final HoraPrevistaOnibusProvider horaPrevistaOnibusProvider;

  const UserWidget(this.usuario, this.configProvider, this.uuid, this.usuarioOnibusProvider, this.statusOnibusProvider, this.horaPrevistaOnibusProvider, {super.key});

  @override
  State<UserWidget> createState() => _UserWidgetState();
}

class _UserWidgetState extends State<UserWidget>  with SingleTickerProviderStateMixin {
  final QUANTIDADE_VEZES_SEGUIDAS_CENTRO = 2;
  final DateFormat formatter = DateFormat('HH:mm');
  final Image imagemWhatsapp = Image(width: 32, image: AssetImage('assets/image.png'));
  final RoutesService routesService = RoutesService();

  late StreamSubscription<Position>? positionStream;
  late Animation<double> animation;
  late AnimationController controller;
  late Repository repository;
  late StreamSubscription<InternetStatus> _connectionListener;
  late bool _conectado;
  DateTime? _horaChegadaEstimada;

  late bool _servicoLocalizacaoAtivo;
  late bool _permissaoServicoLocalizacao;


  DateTime _ultimoEnvioEta = DateTime.fromMillisecondsSinceEpoch(0);
  bool _chegouCentroVezPassada = false;
  int _qtdChegouCentroSeguidas = 0;
  bool _chegouCentro = false;

  bool isChegouCentro(LatLng? localizacaoOnibus, Config config, bool primeiroEnvio){
    bool chegouCentro = false;
    if(localizacaoOnibus != null) {
      double distancia = Geolocator.distanceBetween(localizacaoOnibus.latitude, localizacaoOnibus.longitude,
          config.localizacaoCentro.latitude, config.localizacaoCentro.longitude);

      if(distancia < config.distanciaMinimaFuncionamento){
        chegouCentro = true;
      }
    }

    if((_chegouCentroVezPassada || primeiroEnvio) && chegouCentro){
      _qtdChegouCentroSeguidas++;
      if(_qtdChegouCentroSeguidas >= QUANTIDADE_VEZES_SEGUIDAS_CENTRO || primeiroEnvio) {
        return true;
      }
    }

    _chegouCentroVezPassada = chegouCentro;
    _qtdChegouCentroSeguidas = chegouCentro ? _qtdChegouCentroSeguidas : 0;

    return false;
  }

  bool isDeveRequisitarEta(DateTime ultimoEnvio, Config config){
    return DateTime.now().difference(ultimoEnvio).compareTo(config.tempoAtualizacaoEta) > 0;
  }

  Future<void> sair() async {
    finalizaStream();
    await LocalData.limparDados();

    if(mounted) {
      Navigator.pushAndRemoveUntil(context,
          MaterialPageRoute(
              builder: (context) => RouterHandler()), (_) => false);
      widget.configProvider.config = Config();
    }
  }

  @override
  void initState() {
    _conectado = true;
    _permissaoServicoLocalizacao = true;
    _servicoLocalizacaoAtivo = true;

    inicializaStream();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if(kIsWeb){
        WakelockPlus.enable();
      }
      _connectionListener =
          InternetConnection().onStatusChange.listen((InternetStatus status) {
            if (mounted) {
              if (status == InternetStatus.disconnected) {
                setState(() {
                  _conectado = false;
                });
              }
              else if (status == InternetStatus.connected) {
                setState(() {
                  _conectado = true;
                });
              }
            }
          });
    });

    repository = Repository();
    controller =
        AnimationController(duration: const Duration(seconds: 2), vsync: this)
          ..forward()
          ..addStatusListener((status) {
            if(mounted) {
              if (status == AnimationStatus.completed) {
                controller.reverse();
              } else if (status == AnimationStatus.dismissed) {
                controller.forward();
              }
            }
          });
    animation = Tween<double>(begin: 60, end: 80).animate(controller);

    super.initState();
  }

  void inicializaStream(){
    LocationSettings locationSettings;
    if(kIsWeb){
      locationSettings = WebSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: widget.configProvider.config.distanciaMinimaFuncionamento,
      );
    }
    else {
      locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.high,
          //TODO: HOBILITAR
          distanceFilter: widget.configProvider.config.distanciaMinimaFuncionamento,
          //forceLocationManager: true,
          intervalDuration: widget.configProvider.config
              .tempoAtualizacaoLocalizacao,
          foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationText: "Enviando Localização atual",
              notificationTitle: "Ônibus Congresso",
              enableWakeLock: true,
              setOngoing: true
          )
      );
    }

    positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position? position) async {
      _permissaoServicoLocalizacao = true;
      _servicoLocalizacaoAtivo = true;

      if(!mounted) {
        return;
      }

     if(widget.usuarioOnibusProvider.usuarioLogadoOnibusUuid != widget.uuid){
        SnackbarGlobal.show("Outro usuário já está logado na mesma conta");
        await sair();
        return;
      }

      if(!widget.configProvider.config.envioAtivo){
        finalizaStream();
        return;
      }

     bool primeiroEnvio = _ultimoEnvioEta == DateTime.fromMillisecondsSinceEpoch(0);

      if(position != null) {
        LatLng localizacaoOnibus = LatLng(position.latitude, position.longitude);

        RouteResponse? response;
        if(isDeveRequisitarEta(_ultimoEnvioEta, widget.configProvider.config)) {
          response = await routesService.requestInformacoesRota(
              widget.configProvider.config.localizacaoCentro, localizacaoOnibus);

          if(mounted) {
            if(response != null){
              _ultimoEnvioEta = DateTime.now();
              setState(() {
                _horaChegadaEstimada = _ultimoEnvioEta.add(Duration(seconds: response!.eta));
              });
            }
          }
        }

        bool chegouCentro = isChegouCentro(localizacaoOnibus, widget.configProvider.config, primeiroEnvio);
        if(!chegouCentro || !primeiroEnvio) {
          await repository.enviaLocalizacaoAtual(
              widget.usuario, localizacaoOnibus,
              chegouCentro || primeiroEnvio ? chegouCentro : null,
              response);
        }

        if(mounted) {
          if (chegouCentro) {
            setState(() {
              _chegouCentro = chegouCentro;
            });
            finalizaStream();
          }
        }
      }
    }, onError: (e) async {
      if(e is PermissionDeniedException){

        bool servicoLocalizacaoAtivo = await Geolocalizacao.isServicoLocalizacaoHabilitado();
        if(!servicoLocalizacaoAtivo && _servicoLocalizacaoAtivo) {
          if(mounted) {
            setState(() {
              _servicoLocalizacaoAtivo = servicoLocalizacaoAtivo;
            });
          }
          return;
        }

        try {
          bool permissaoServicoLocalizacao = await Geolocalizacao.isPermissaoServicoLocalizacao();
          if (!permissaoServicoLocalizacao && _permissaoServicoLocalizacao) {
            if (mounted) {
              setState(() {
                _permissaoServicoLocalizacao = permissaoServicoLocalizacao;
              });
            }
            return;
          }
        } on ErroMensagem catch (_){
          if (mounted) {
            setState(() {
              _permissaoServicoLocalizacao = false;
            });
          }
          return;
        }
      }
    });
  }

  void finalizaStream(){
    positionStream?.cancel();
    positionStream = null;
  }

  @override
  void dispose() {
    if(kIsWeb){
      WakelockPlus.disable();
    }

    finalizaStream();
    _connectionListener.cancel();
    repository.close();
    controller.dispose();
    super.dispose();
  }

  Widget informacaoAtraso(DateTime? horaChegadaEstimada){
    if(horaChegadaEstimada == null || widget.horaPrevistaOnibusProvider.horaPrevista == null){
      return SizedBox(height: 0, width: 0,);
    }

    if(widget.horaPrevistaOnibusProvider.isAdiantado(horaChegadaEstimada, widget.configProvider.config)){
      return Text("Você está adiantado!", style: TextStyle(fontSize: 20, color: Colors.amber, fontWeight: FontWeight.bold), textAlign: TextAlign.center,);
    }

    if(widget.horaPrevistaOnibusProvider.isAtrasado(horaChegadaEstimada, widget.configProvider.config)){
      return Text("Você está atrasado!", style: TextStyle(fontSize: 20, color: Colors.red, fontWeight: FontWeight.bold), textAlign: TextAlign.center,);
    }
    else{
      return SizedBox(height: 0, width: 0,);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
        listenable: Listenable.merge([
          widget.configProvider,
          widget.statusOnibusProvider,
          widget.horaPrevistaOnibusProvider
        ]),
        builder: (ctx, wgt) {

          if(positionStream == null) {
            inicializaStream();
          }

          return Scaffold(
              appBar: AppBar(
                automaticallyImplyLeading: false,
                title: Text(widget.usuario.getDescricaoUsuario()),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.logout),
                    tooltip: 'Sair',
                    onPressed: () async {
                      await sair();
                    },
                  ),
                ],
              ),
              body: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 10,
                children: [
                  Center(
                  child: LayoutBuilder(
                    builder: (context, constraints){
                      if(!_servicoLocalizacaoAtivo){
                        return Column(
                            mainAxisSize: MainAxisSize.min, // Adjusts the column size to its children
                            spacing: 10,
                            children: [
                              Icon(Icons.location_disabled, size: 60),
                              Text("Localização Desabilitada", style: TextStyle(fontSize: 25, color: Colors.red, fontWeight: FontWeight.bold), textAlign: TextAlign.center,),
                              Text("Meta de horário: ${widget.horaPrevistaOnibusProvider.getHoraPrevistaString() ?? "Aguandando ativação"}",
                                style: TextStyle(fontSize: 20, color: Colors.black, fontWeight: FontWeight.bold), textAlign: TextAlign.center,),
                              Text("Hora de chegada estimada: ${_horaChegadaEstimada == null ? "Aguardando ativação" : formatter.format(_horaChegadaEstimada!)}", style: TextStyle(fontSize: 20, color: Colors.black, fontWeight: FontWeight.bold), textAlign: TextAlign.center,),
                              informacaoAtraso(_horaChegadaEstimada),
                              Text("Por favor, ative a localização e reinicie do aplicativo", style: TextStyle(fontSize: 20, color: Colors.black38), textAlign: TextAlign.center,)
                            ]
                        );
                      }
                      if(!_permissaoServicoLocalizacao){
                        return Column(
                            mainAxisSize: MainAxisSize.min, // Adjusts the column size to its children
                            spacing: 10,
                            children: [
                              Icon(Icons.location_disabled, size: 60),
                              Text("Localização Desabilitada", style: TextStyle(fontSize: 25, color: Colors.red, fontWeight: FontWeight.bold), textAlign: TextAlign.center,),
                              Text("Meta de horário: ${widget.horaPrevistaOnibusProvider.getHoraPrevistaString() ?? "Aguandando concessão de permissão"}",
                                style: TextStyle(fontSize: 20, color: Colors.black, fontWeight: FontWeight.bold), textAlign: TextAlign.center,),
                              Text("Hora de chegada estimada: ${_horaChegadaEstimada == null ? "Aguandando concessão de permissão" : formatter.format(_horaChegadaEstimada!)}", style: TextStyle(fontSize: 20, color: Colors.black, fontWeight: FontWeight.bold), textAlign: TextAlign.center,),
                              informacaoAtraso(_horaChegadaEstimada),
                              Text("Por favor, conceda a permissão e reinicie o aplicativo", style: TextStyle(fontSize: 20, color: Colors.black38), textAlign: TextAlign.center,)
                            ]
                        );
                      }
                      if(!_conectado){
                        return Column(
                            mainAxisSize: MainAxisSize.min, // Adjusts the column size to its children
                            spacing: 10,
                            children: [
                              Icon(Icons.wifi_off, size: 60),
                              Text("Sem sinal de internet", style: TextStyle(fontSize: 25, color: Colors.red, fontWeight: FontWeight.bold), textAlign: TextAlign.center,),
                              Text("Meta de horário: ${widget.horaPrevistaOnibusProvider.getHoraPrevistaString() ?? "Aguandando conexão"}",
                                  style: TextStyle(fontSize: 20, color: Colors.black, fontWeight: FontWeight.bold), textAlign: TextAlign.center,),
                              Text("Hora de chegada estimada: ${_horaChegadaEstimada == null ? "Aguardando Sinal" : formatter.format(_horaChegadaEstimada!)}", style: TextStyle(fontSize: 20, color: Colors.black, fontWeight: FontWeight.bold), textAlign: TextAlign.center,),
                              informacaoAtraso(_horaChegadaEstimada),
                              Text("Aguarde o retorno do sinal", style: TextStyle(fontSize: 20, color: Colors.black38), textAlign: TextAlign.center,)
                            ]
                        );
                      }
                      if(!widget.configProvider.config.envioAtivo || !widget.statusOnibusProvider.ativo){
                        return Column(
                          mainAxisSize: MainAxisSize.min, // Adjusts the column size to its children
                          spacing: 10,
                          children: [
                            Icon(Icons.location_disabled, size: 60),
                            Text("Envio de localização bloqueado pelo administrador temporariamente", style: TextStyle(fontSize: 25, color: Colors.red, fontWeight: FontWeight.bold), textAlign: TextAlign.center,),
                            Text("O aplicativo pode ser fechado", style: TextStyle(fontSize: 20, color: Colors.black38), textAlign: TextAlign.center,)
                          ]
                        );
                      }
                      if(_chegouCentro){
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          spacing: 10,
                          children: [
                            Icon(Icons.location_disabled, size: 60),
                            Text("Você chegou ao seu destino!", style: TextStyle(fontSize: 25, color: Colors.green, fontWeight: FontWeight.bold), textAlign: TextAlign.center,),
                            Text("O aplicativo pode ser fechado", style: TextStyle(fontSize: 20, color: Colors.black38), textAlign: TextAlign.center,)
                          ]
                        );
                      }
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 10,
                        children: [
                          AnimatedLocalizationLogo(animation: animation),
                          Text("Enviando Localização", style: TextStyle(fontSize: 25)),
                          Text("Meta de horário: ${widget.horaPrevistaOnibusProvider.getHoraPrevistaString() ?? "Calculando"}",
                            style: TextStyle(fontSize: 20, color: Colors.black, fontWeight: FontWeight.bold), textAlign: TextAlign.center,),
                          Text("Hora de chegada estimada: ${_horaChegadaEstimada == null ? "Calculando" : formatter.format(_horaChegadaEstimada!)}", style: TextStyle(fontSize: 20, color: Colors.black, fontWeight: FontWeight.bold), textAlign: TextAlign.center,),
                          informacaoAtraso(_horaChegadaEstimada)
                        ]
                      );
                    })
                  ),
                  Container( padding: EdgeInsets.symmetric(horizontal: 10), child: Text( "Contatos: ", textAlign: TextAlign.left)),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      children: widget.configProvider.config.contatosAdmin.map((item) {
                        return Card(child: ListTile(
                          leading: imagemWhatsapp,
                          onTap: () async {
                            bool? autoriza = await showConfirmacao(ctx, "Enviar Mensagem", "Deseja mandar mensagem para ${item.nome}?");
                            String androidUrl = "https://wa.me/${item.telefone}";
                            if(autoriza != null && autoriza){
                              if(await canLaunchUrl(Uri.parse(androidUrl))){
                                await launchUrl(Uri.parse(androidUrl));
                              }
                              else{
                                SnackbarGlobal.show("Não foi possível mandar mensagem para ${item.nome}");
                              }
                            }
                          },
                          title: Text(item.nome)
                        ));
                      }).toList(),
                    )
                  )
                ])
          );
        }
    );
  }
}



class AnimatedLocalizationLogo extends AnimatedWidget {
  const AnimatedLocalizationLogo({super.key, required Animation<double> animation})
      : super(listenable: animation);

  @override
  Widget build(BuildContext context) {
    final animation = listenable as Animation<double>;
    return SizedBox(
        height: 80,
        width: 80,
        child: Icon(Icons.my_location, size: animation.value)
    );
  }
}


