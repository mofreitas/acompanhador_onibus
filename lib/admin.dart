import 'dart:async';
import 'dart:collection';

import 'package:acompanhador_onibus_congresso/confirmacao.dart';
import 'package:acompanhador_onibus_congresso/dominio/configuracao.dart';
import 'package:acompanhador_onibus_congresso/dominio/grupos.dart';
import 'package:acompanhador_onibus_congresso/loading_screen.dart';
import 'package:acompanhador_onibus_congresso/service/local_data.dart';
import 'package:acompanhador_onibus_congresso/main.dart';
import 'package:acompanhador_onibus_congresso/dominio/onibus_congregacao.dart';
import 'package:acompanhador_onibus_congresso/provider.dart';
import 'package:acompanhador_onibus_congresso/service/repository.dart';
import 'package:acompanhador_onibus_congresso/snackbar_global.dart';
import 'package:acompanhador_onibus_congresso/dominio/usuario.dart';
import 'package:acompanhador_onibus_congresso/utils/map_tooltip.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:synchronized/synchronized.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:widget_to_marker/widget_to_marker.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;

class AdminApp extends StatefulWidget {
  final Usuario usuario;

  const AdminApp(this.usuario, {super.key});

  @override
  State<AdminApp> createState() => _AdminAppState();
}

class _AdminAppState extends State<AdminApp> {
  late Repository _repository;
  late Future<ConfigProvider> _futureConfigProvider;

  @override
  void initState() {
    _repository = Repository();
    _futureConfigProvider = _repository.getConfiguracoesProvider();
    super.initState();
  }


  @override
  void dispose() {
    _repository.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
        canPop: false,
        child:
          FutureBuilder<dynamic>(
          future: _futureConfigProvider,
          builder: (BuildContext context, AsyncSnapshot<dynamic> snapshot) {
            if (snapshot.connectionState == ConnectionState.done) {
              if (snapshot.hasError) {
                SnackbarGlobal.show(snapshot.error.toString());
                LocalData.limparDados();
                return RouterHandler();
              } else {
                ConfigProvider configProvider = snapshot.data;
                return Scaffold(
                  appBar: AppBar(
                    automaticallyImplyLeading: false,
                    title: const Text('Admin'),
                    backgroundColor:  Theme.of(context).colorScheme.onSecondary,
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.logout),
                        tooltip: 'Sair',
                        onPressed: () async {
                          await LocalData.limparDados();
                          if(context.mounted) {
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(
                              builder: (context) => RouterHandler()), (_) => false,
                            );
                          }
                        },
                      )
                    ]
                  ),
                  body: ListenableBuilder(
                    listenable: configProvider,
                    builder: (context, widget){
                      return MapaOnibusWidget(
                        configProvider.config,
                        _repository
                      );
                    }
                  ),
                );
              }
            } else {
              return LoadingScreen();
            }
          },
    ));
  }
}

class MapaOnibusWidget extends StatefulWidget {
  final Config _config;
  final Repository _repository;

  const MapaOnibusWidget(
      this._config, this._repository, {super.key});

  @override
  State<MapaOnibusWidget> createState() => _MapaOnibusWidget();
}

class _MapaOnibusWidget extends State<MapaOnibusWidget> {
  late StreamSubscription<List<OnibusCongregacao>> _streamOnibusCongregacao;
  late StreamSubscription<InternetStatus>? _connectionListener;

  late GoogleMapController _mapController;
  late ScrollController _scrollController;
  Set<Marker> _marcadoresOnibus = {};
  List<OnibusCongregacao> _onibusCongregacoes = [];

  int _zIndex = 0;

  Lock lock = Lock();

  final Size tamanhoMarker = kIsWeb && !(defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS) ? const Size(220, 110) : const Size(500, 300);
  late StreamOnibus _streamOnibus;

  @override
  void initState() {
    final GoogleMapsFlutterPlatform mapsImplementation = GoogleMapsFlutterPlatform.instance;
    if (mapsImplementation is GoogleMapsFlutterAndroid) {
      mapsImplementation.useAndroidViewSurface = true;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connectionListener = InternetConnection().onStatusChange.listen((InternetStatus status) {
        if(mounted) {
          switch (status) {
            case InternetStatus.disconnected:
              SnackbarGlobal.showFixedSnackbar(SnackbarGlobal.snackbarInternet, "Não conectado à internet");
              break;
            case InternetStatus.connected:
              SnackbarGlobal.hideFixedSnackbar(SnackbarGlobal.snackbarInternet);
              break;
          }
        }
      });

      //_preencheMarcadorExecutor = PreencheMarcadorExecutor();

      _streamOnibus = StreamOnibus(widget._config);
      _streamOnibusCongregacao = _streamOnibus.stream.listen((List<OnibusCongregacao> onibusCongregacoes) async {
        await lock.synchronized(() async {
          _onibusCongregacoes = List.from(onibusCongregacoes);

          await Future.wait(_inicializaMarcadores(
              _onibusCongregacoes /*, _onibusSelecionado*/));

          if (!mounted) return;

          _marcadoresOnibus = _onibusCongregacoes
              .where((item) =>
          item.ativo && !item.chegouCentro && item.marcador != null &&
              !item.inativoTempo)
              .map((item) => item.marcador!)
              .toSet();

          _marcadoresOnibus.add(
              Marker(
                  markerId: MarkerId("centro"),
                  position: widget._config.localizacaoCentro,
                  zIndexInt: 2100000000,
                  onTap: () {
                    _atualizaOnibusSelecionado(null, false);
                  }
              ));

          setState(() {});
        });
      });
    });

    super.initState();
  }

  @override
  void dispose() {
    _streamOnibusCongregacao.cancel();
    _connectionListener?.cancel();
    SnackbarGlobal.removeSnackBar();
    super.dispose();
  }

  void _onScrollControllerCreated(ScrollController scrollController){
    _scrollController = scrollController;
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  void _moveCameraCentro() {
    _mapController.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
            target: widget._config.localizacaoCentro,
            zoom: 15.0
        ),
      ),
    );
  }

  double _calculaPosicaoLista(int index){
    return (72.0) * index;
  }

  Future _preencheMarcadorOnibus(int index, OnibusCongregacao onibusCongregacao) async {

    Marker marcadorOnibus = Marker(
      markerId: MarkerId(onibusCongregacao.numeroOnibus),
      position: onibusCongregacao.localizacao!,
      icon: await CustomMarkerIcon(numeroCongregacao: onibusCongregacao.numeroOnibus, nomeCongregacao: onibusCongregacao.nomeCongregacao, hue: onibusCongregacao.hueIdentificadorGrupo.toDouble(),)
          .toBitmapDescriptor(logicalSize: const Size(200, 100), imageSize: tamanhoMarker),
      zIndexInt: onibusCongregacao.zIndex,
      onTap: () {
        _atualizaOnibusSelecionado(onibusCongregacao, false);
        _scrollController.animateTo(_calculaPosicaoLista(index), duration: Duration(milliseconds: 500), curve: Curves.linear);
      }
    );

    onibusCongregacao.marcador = marcadorOnibus;
  }

  Iterable<Future<void>> _inicializaMarcadores(List<OnibusCongregacao> onibusCongregacoes) {
    return _onibusCongregacoes
        .indexed
        .where((item) {
          return item.$2.ativo && !item.$2.chegouCentro && !item.$2.inativoTempo && item.$2.marcador == null;
        }).map((item) {
          return _preencheMarcadorOnibus(item.$1, item.$2);
        });
  }

  TipoLayout defineTipoLayout(){
    double width = MediaQuery.of(context).size.width;
    if(width > 1000){
      return TipoLayout.Horizontal;
    }
    return TipoLayout.Vertical;
  }

  void _atualizaSituacaoOnibusBanco(OnibusCongregacao onibusCongregacao, bool novaSituacao){
      widget._repository.atualizaSituacaoOnibus(onibusCongregacao.numeroOnibus, novaSituacao);
  }

  void _atualizaOnibusSelecionado(OnibusCongregacao? onibusSelecionado, bool fromListagem) async {
    await lock.synchronized(() async {
      if (!mounted) return;
      //TODO: corrigir funcionamento admin celular
      onibusSelecionado?.marcador = null;
      onibusSelecionado?.zIndex = ++_zIndex;

      await Future.wait(_inicializaMarcadores(_onibusCongregacoes));

      if (mounted) {
        _marcadoresOnibus = _onibusCongregacoes
            .where((item) =>
        item.ativo && !item.chegouCentro && item.marcador != null &&
            !item.inativoTempo)
            .map((item) => item.marcador!)
            .toSet();

        _marcadoresOnibus.add(
            Marker(
                zIndexInt: 2100000000,
                markerId: MarkerId("centro"),
                position: widget._config.localizacaoCentro,
                onTap: () {
                  _atualizaOnibusSelecionado(null, false);
                }
            ));

        setState(() {});

        if (fromListagem && onibusSelecionado != null) {
          _mapController.moveCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                  target: onibusSelecionado.localizacao!,
                  zoom: 15.0
              ),
            ),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
      TipoLayout tipoLayout = defineTipoLayout();

      Set<Grupo> grupoSet = SplayTreeSet();
      for(var onibus in _onibusCongregacoes){
        grupoSet.add(Grupo(onibus.hueIdentificadorGrupo.toDouble(), onibus.getHoraPrevistaString()));
      }

      if(!widget._config.envioAtivo) {
        _marcadoresOnibus = {
          Marker(
              markerId: MarkerId("centro"),
              position: widget._config.localizacaoCentro,
              onTap: () {
                _atualizaOnibusSelecionado(null, false);
              }
          )};
      }

      return Stack(
        children: [
          MapContainer(widget._config, tipoLayout, _marcadoresOnibus, _onMapCreated, _moveCameraCentro, grupoSet.toList()),
          tipoLayout == TipoLayout.Vertical ?
            ListViewVerticalContainer(
                widget._config,
                _onibusCongregacoes,
                _onScrollControllerCreated,
                _atualizaOnibusSelecionado,
                _atualizaSituacaoOnibusBanco
          ) :
          ListViewHorizontalContainer(
              widget._config,
              _onibusCongregacoes,
              _onScrollControllerCreated,
              _atualizaOnibusSelecionado,
              _atualizaSituacaoOnibusBanco
          )
        ],
      );
  }
}

class ListViewOnibus extends StatelessWidget{
  final Config _config;
  final ScrollController _scrollController;
  final List<OnibusCongregacao> _onibusCongregacoes;
  final Function(OnibusCongregacao onibusSelecionado, bool fromListagem) _atualizaOnibusSelecionado;
  final Function(OnibusCongregacao onibusSelecionado, bool novaSituacao) _atualizaSituacaoOnibusBanco;

  const ListViewOnibus(this._config, this._scrollController, this._onibusCongregacoes,
      this._atualizaOnibusSelecionado, this._atualizaSituacaoOnibusBanco, {super.key});

  Future _actionMensagemWhatsapp(BuildContext context, OnibusCongregacao onibusCongregacao) async {
    if(onibusCongregacao.contato == null){
      await showMensagem(context, "Aviso", "O ônibus ${onibusCongregacao.descricaoCongregacaoCompleta()} não possui contato. Tente verificar com outro ônibus da cidade.");
      return;
    }

    bool confirma = await showConfirmacao(context, "Enviar Mensagem", "Deseja mandar mensagem para ${onibusCongregacao.nomeCapitao ?? onibusCongregacao.contato} do ônibus de ${onibusCongregacao.descricaoCongregacaoCompleta()}?") ?? false;
    if(confirma && context.mounted){
      String androidUrl = "https://wa.me/${onibusCongregacao.contato}";
      if(await canLaunchUrl(Uri.parse(androidUrl))){
        await launchUrl(Uri.parse(androidUrl));
      }
      else if (context.mounted){
        SnackbarGlobal.show("Não foi possível mandar mensagem para ${onibusCongregacao.nomeCapitao}");
      }
    }
  }



  Future _actionAlteraSituacaoOnibus(BuildContext context, OnibusCongregacao onibusCongregacao, bool novaSituacao) async {
    bool confirma = await showConfirmacao(context, "Alterar Situação",
        "Deseja ${onibusCongregacao.ativo ? "desativar" : "ativar"} a localização do veículo ${onibusCongregacao.descricaoCongregacaoCompleta()}?") ?? false;
    if(confirma && context.mounted){
      _atualizaSituacaoOnibusBanco(onibusCongregacao, novaSituacao);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(0,25,0,0),
      controller: _scrollController,
      itemCount: _onibusCongregacoes.length,
      prototypeItem: ListTile(
        leading: Text("000", style: TextStyle(color:Colors.black38, height: 3.0, inherit: true)),
        title: Text("aaa"),
        subtitle: Text("aaa"),
        trailing: Switch(value: false, onChanged: null)
      ),
      itemBuilder: (context, index) {
        OnibusCongregacao onibusCongregacao = _onibusCongregacoes[index];

        if(!_config.envioAtivo || !onibusCongregacao.ativo){
          return ListTile(
            leading: Text(onibusCongregacao.numeroOnibus.toString(), style: TextStyle(fontSize: 20, fontFamily: 'monospace', color:Colors.black38, height: 3.0, inherit: true)),
            title: Text(onibusCongregacao.descricaoCongregacaoCidade()),
            titleTextStyle: TextStyle(color:Colors.black38, inherit: true),
            subtitleTextStyle: TextStyle(color:Colors.black38, inherit: true),
            subtitle: Text('Inativado por admin'),
            onLongPress: () async {
              await _actionMensagemWhatsapp(context, onibusCongregacao);
            },
            trailing: Switch(
              value: onibusCongregacao.ativo,
              onChanged: _config.envioAtivo ? (bool novoValor) async {
                await _actionAlteraSituacaoOnibus(context, onibusCongregacao, novoValor);
              } : null,
            ),
          );
        }
        else if(onibusCongregacao.inativoTempo){
          return ListTile(
              leading: Text(onibusCongregacao.numeroOnibus.toString(), style: TextStyle(fontSize: 20, fontFamily: 'monospace', color:Colors.black38, inherit: true, height: 3.0)),
              title: Text(onibusCongregacao.descricaoCongregacaoCidade()),
              titleTextStyle: TextStyle(color:Colors.black38, inherit: true),
              subtitleTextStyle: TextStyle(color:Colors.black38, inherit: true),
              subtitle: Text('Inativado pelo tempo'),
              onLongPress: () async {
                await _actionMensagemWhatsapp(context, onibusCongregacao);
              },
              trailing: Switch(
                value: onibusCongregacao.ativo,
                onChanged: _config.envioAtivo ? (bool novoValor) async {
                  await _actionAlteraSituacaoOnibus(context, onibusCongregacao, novoValor);
                } : null,
              )
          );
        }
        else if (onibusCongregacao.chegouCentro){
          return ListTile(
              leading: Text(onibusCongregacao.numeroOnibus.toString(), style: TextStyle(fontSize: 20, fontFamily: 'monospace', color:Colors.black, inherit: true, height: 3.0)),//Icon(Icons.check_circle_outline, size: 35.0, color: Colors.green),
              title: Text(onibusCongregacao.descricaoCongregacaoCidade()),
              titleTextStyle: TextStyle(color: Colors.black, inherit: true),
              subtitleTextStyle: TextStyle(color:Colors.green, inherit: true),
              subtitle: Text('Chegou Centro'),
              onLongPress: () async {
                await _actionMensagemWhatsapp(context, onibusCongregacao);
              },
              trailing: Switch(
                value: onibusCongregacao.ativo,
                onChanged:  _config.envioAtivo ? (bool novoValor) async {
                  await _actionAlteraSituacaoOnibus(context, onibusCongregacao, novoValor);
                } : null,
              )
          );
        }
        else {
          return Material(
            child: ListTile(
              leading: Text(onibusCongregacao.numeroOnibus.toString(), style: TextStyle(fontSize: 20, fontFamily: 'monospace', color: Colors.black, inherit: true, height: 3.0)),
              titleTextStyle: TextStyle(color: Colors.black, inherit: true),
              subtitleTextStyle: TextStyle(color: Colors.black, inherit: true),
              title: Text(onibusCongregacao.descricaoCongregacaoTipoOnibus()),
              subtitle: Text('Previsão: ${onibusCongregacao.getHoraChegadaString()} (Meta: ${onibusCongregacao.getHoraPrevistaString()})'),
              tileColor: onibusCongregacao.isAtrasado(_config) ? Colors.redAccent :
                            onibusCongregacao.isAdiantado(_config) ? Colors.yellow : null,
              onLongPress: () async {
                await _actionMensagemWhatsapp(context, onibusCongregacao);
              },
              trailing: Switch(
                value: onibusCongregacao.ativo,
                onChanged:  _config.envioAtivo ? (bool novoValor) async {
                  await _actionAlteraSituacaoOnibus(context, onibusCongregacao, novoValor);
                } : null,
              ),
              onTap: () {
                if (onibusCongregacao.localizacao != null) {
                  _atualizaOnibusSelecionado(onibusCongregacao, true);
                }
              },
            )
          );
        }
      }
  );
  }
}

class BarraNavegacaoListView extends StatelessWidget{
  const BarraNavegacaoListView({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
        child: Container(
            color: Theme.of(context).canvasColor,
            height: 25,
            child: Row(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    height: 5,
                    width: 50,
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: Colors.grey
                    ),
                  )
                ]
            )
        )
    );
  }

}

class MapContainer extends StatelessWidget{
  final Config _config;
  final Set<Marker> _marcadoresOnibus;
  final List<Grupo> _grupoOnibus;
  final Function(GoogleMapController controller) _mapControllerCallback;
  final Function() _moveCameraCentroCallback;
  final TipoLayout tipoLayout;

  const MapContainer(this._config, this.tipoLayout,
      this._marcadoresOnibus, this._mapControllerCallback,
      this._moveCameraCentroCallback, this._grupoOnibus);

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
        alignment: Alignment.topLeft,
        heightFactor: tipoLayout == TipoLayout.Vertical ? 0.70 : 1,
        widthFactor: tipoLayout == TipoLayout.Horizontal ? 0.70 : 1,
        child:Stack(
            children: [
              GoogleMap(
                onMapCreated: _mapControllerCallback,
                initialCameraPosition: CameraPosition(
                  target: _config.localizacaoCentro,
                  zoom: 15.0,
                ),
                markers: _marcadoresOnibus
              ),
              LegendaWidget(grupos: _grupoOnibus),
              SideFloatingButtonList(_config, _moveCameraCentroCallback)
            ]
          ),

    );
  }
}

class ListViewVerticalContainer extends StatelessWidget{
  final Config _config;
  final List<OnibusCongregacao> _onibusCongregacoes;
  final Function(ScrollController scrollController) _setScrollControllerCallback;
  final Function(OnibusCongregacao onibusSelecionado, bool fromListagem) _setOnibusSelecionadoCallback;
  final Function(OnibusCongregacao onibusCongregacao, bool novaSituacao) _atualizaSituacaoOnibusBancoCallback;

  const ListViewVerticalContainer(this._config, this._onibusCongregacoes,
      this._setScrollControllerCallback, this._setOnibusSelecionadoCallback,
      this._atualizaSituacaoOnibusBancoCallback);

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.3, // Initial height (30% of screen)
      minChildSize: 0.3, // Minimum height (20% of screen)
      maxChildSize: 0.7, // Maximum height (80% of screen)
      snap: true,
      builder: (context, scrollController) {
        _setScrollControllerCallback(scrollController);
        return Container(
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              color: Theme.of(context).canvasColor,
            ),
            child: Stack(
                children: [
                  Builder(
                    builder: (_) {
                      if (_onibusCongregacoes.isEmpty) {
                        return SingleChildScrollView(
                            controller: scrollController,
                            padding: EdgeInsets.fromLTRB(0,25,0,0),
                            child: Align(
                              alignment: Alignment.center,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                spacing: 10,
                                children: [
                                  Icon(Icons.highlight_remove, color: Colors.grey, size: 48,),
                                  Text("Nenhum Veículo Encontrado"),
                                ],
                              ),
                            )
                        );
                      }

                      return ListViewOnibus(
                          _config,
                          scrollController,
                          _onibusCongregacoes,
                          _setOnibusSelecionadoCallback,
                          _atualizaSituacaoOnibusBancoCallback);
                    },
                  ),
                  BarraNavegacaoListView()
                ]
            )
        );
      },
    );
  }
}

class ListViewHorizontalContainer extends StatelessWidget{
  final Config _config;
  final ScrollController _scrollController = ScrollController();
  final List<OnibusCongregacao> _onibusCongregacoes;
  final Function(ScrollController scrollController) _setScrollControllerCallback;
  final Function(OnibusCongregacao onibusSelecionado, bool fromListagem) _setOnibusSelecionadoCallback;
  final Function(OnibusCongregacao onibusCongregacao, bool novaSituacao) _atualizaSituacaoOnibusBancoCallback;

  ListViewHorizontalContainer(this._config, this._onibusCongregacoes,
      this._setScrollControllerCallback, this._setOnibusSelecionadoCallback,
      this._atualizaSituacaoOnibusBancoCallback);

  @override
  Widget build(BuildContext context) {
    _setScrollControllerCallback(_scrollController);
    return SizedBox.expand(child: FractionallySizedBox(
        alignment: Alignment.topRight,
        widthFactor: 0.3,
        child: ListViewOnibus(
                _config,
                _scrollController,
                _onibusCongregacoes,
                _setOnibusSelecionadoCallback,
                _atualizaSituacaoOnibusBancoCallback)
    ));
  }
}

class SideFloatingButtonList extends StatefulWidget{
  final Config _config;
  final Function() _moveCameraCentroCallback;

  SideFloatingButtonList(this._config, this._moveCameraCentroCallback);

  @override
  State<StatefulWidget> createState() => SideFloatingButtonListState();
}

class SideFloatingButtonListState extends State<SideFloatingButtonList>{
  bool envioPendente = false;
  late Repository _repository;
  late StreamSubscription<InternetStatus> _connectionListener;
  bool _conectado = true;

  @override
  void initState() {
    super.initState();
    _repository = Repository();

    _connectionListener = InternetConnection().onStatusChange.listen((InternetStatus status) {
      if(mounted) {
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
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.bottomStart,
      child:
      Container(
        margin: EdgeInsets.fromLTRB(10, 0, 0, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FloatingActionButton(
                heroTag: "fab1",
                mini: true,
                onPressed: widget._moveCameraCentroCallback,
            tooltip: "Centro de Convenções",
                child: Icon(Icons.my_location)
            ),
            SizedBox(height: 8),
            FloatingActionButton(
              heroTag: "fab2",
              onPressed: envioPendente || !_conectado ? null : () async {
                if(context.mounted) {
                  setState(() {
                    envioPendente = true;
                  });
                }

                bool resultadoConfirmacao = await showConfirmacao(context, "Alterar Situação", "Deseja ${widget._config.envioAtivo ? 'desativar' : 'ativar'} a localização para todos os usuários?") ?? false;
                if(context.mounted) {
                  if (resultadoConfirmacao) {
                    await _repository.atualizaLocalizacaoTodosOnibus(!widget._config.envioAtivo);
                  }
                }

                if(context.mounted){
                  if (!widget._config.envioAtivo) {
                    SnackbarGlobal.showFixedSnackbar(SnackbarGlobal.snackbarAtivacaoGeral,
                        "Envio de localização geral inativado");
                  }
                  else {
                    SnackbarGlobal.hideFixedSnackbar(SnackbarGlobal.snackbarAtivacaoGeral);
                    SnackbarGlobal.show(
                        "Envio de localização geral ativado");
                  }

                  setState(() {
                    envioPendente = false;
                  });
                }
              },
              mini: true,
              tooltip: "${widget._config.envioAtivo ? 'Desativa' : 'Ativa'} Localização",
              child: widget._config.envioAtivo ? Icon(Icons.location_off) : Icon(Icons.location_on)
            ),
            SizedBox(height: 8),
          ],
        )
      )
    );
  }

  @override
  void dispose() {
    _connectionListener.cancel();
    _repository.close();
    super.dispose();
  }

}

class LegendaWidget extends StatelessWidget {

  final List<Grupo> grupos;

  const LegendaWidget({super.key, required this.grupos});

  @override
  Widget build(BuildContext context) {
    return Align(
        alignment: AlignmentDirectional.topStart,
        child: Container(
        margin: EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        width: 100,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10)
        ),
        //margin: EdgeInsets.fromLTRB(10, 0, right, bottom),
        child: SingleChildScrollView (
          child: Column(
            children: [
              Text("Horários", style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center,),
              ...grupos.map((item) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: HSVColor.fromAHSV(1, item.hue, 0.77, 0.93).toColor(),
                        borderRadius: BorderRadius.circular(2),

                      ),
                    ),
                    SizedBox(width: 10,),
                    Text(item.horario),
                  ]
                );
              })
            ]
          )
        )
    ));
  }

}

enum TipoLayout{Vertical, Horizontal}


