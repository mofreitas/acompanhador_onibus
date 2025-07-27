import 'dart:async';

import 'package:acompanhador_onibus_congresso/admin.dart';
import 'package:acompanhador_onibus_congresso/confirmacao_permissoes.dart';
import 'package:acompanhador_onibus_congresso/loading_screen.dart';
import 'package:acompanhador_onibus_congresso/service/local_data.dart';
import 'package:acompanhador_onibus_congresso/service/repository.dart';
import 'package:acompanhador_onibus_congresso/snackbar_global.dart';
import 'package:acompanhador_onibus_congresso/splash_screen.dart';
import 'package:acompanhador_onibus_congresso/dominio/usuario.dart';
import 'package:acompanhador_onibus_congresso/utils/exception.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env");
  await Repository.iniciaFirebase();

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: SnackbarGlobal.key,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
      ),
      home: SafeArea(child: RouterHandler()),
    );
  }
}

class RouterHandler extends StatefulWidget {
  const RouterHandler({super.key});

  @override
  State<StatefulWidget> createState() => _RouterHandlerState();
}

class _RouterHandlerState extends State<RouterHandler> {
  late Repository _repository;
  late Future<Widget> _futureWidgetProximaTela;

  @override
  void initState() {
    _repository = Repository();
    _futureWidgetProximaTela = _repository.getUsuarioLogado().then((usuario) async {
      if (usuario == null) {
        return LoginPage();
      } else if (usuario.isAdmin()) {
        return AdminApp(usuario);
      } else {
        return await PermissionChain.widgetPermissionChain(usuario);
      }
    }).onError((_, __) async {
      await LocalData.limparDados();
      return RouterHandler();
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _futureWidgetProximaTela,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          Widget widget = snapshot.data!;
          return widget;
        } else {
          return SplashScreen();
        }
      },
    );
  }

  @override
  void dispose() {
    _repository.close();
    super.dispose();
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _botaoEntrarCarregando = false;
  Usuario? _usuarioSelecionado;
  late Repository _repository;
  final TextEditingController _senhaTextController = TextEditingController();
  final TextEditingController _congregacaoController = TextEditingController();
  late Future _futureNomesCongregacoesList;
  late StreamSubscription<InternetStatus> _connectionListener;
  bool _bloqueiaFormulario = false;
  List<DropdownMenuEntry<Usuario>> _listaCongregacoesDropDown = [];

  DropdownMenuEntry<Usuario> gerarListItemFromNome(Usuario usuario){
    return DropdownMenuEntry<Usuario>(
      value: usuario,
      label: usuario.nome,
    );
  }

  Future _futureListaNomesCongregacoes() async {
    List<DropdownMenuEntry<Usuario>> congregacaoDropList = [];
    if(mounted) {
      List<Usuario> congregacoes = await _repository.getCongregacoes();
      if(mounted) {
        congregacaoDropList = congregacoes.map((congregacao) =>
            gerarListItemFromNome(congregacao)).toList();
      }
    }
    _listaCongregacoesDropDown = congregacaoDropList;
  }

  @override
  void initState() {
    super.initState();

    _repository = Repository();
    _futureNomesCongregacoesList = _futureListaNomesCongregacoes();
    _botaoEntrarCarregando = false;
    _bloqueiaFormulario = false;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connectionListener =
          InternetConnection().onStatusChange.listen((InternetStatus status) async {
            if (mounted) {
              if (status == InternetStatus.disconnected) {
                SnackbarGlobal.showFixedSnackbar(SnackbarGlobal.snackbarInternet, "Não conectado à Internet");
                setState(() {
                  _bloqueiaFormulario = true;
                });
              }
              else if (status == InternetStatus.connected) {
                SnackbarGlobal.hideFixedSnackbar(SnackbarGlobal.snackbarInternet);
                if(_listaCongregacoesDropDown.isEmpty) {
                  await _futureListaNomesCongregacoes();
                }
                if(mounted) {
                  setState(() {
                    _bloqueiaFormulario = false;
                  });
                }
              }
            }
          });
    });
  }

  @override
  void dispose() {
    _connectionListener.cancel();
    _repository.close();
    super.dispose();
  }

  Future<Usuario> _login() async {
    if (_usuarioSelecionado == null) {
      throw ErroMensagem("Nenhuma congregação selecionada");
    }

    Usuario? usuarioLogado = await _repository.efetuaLogin(
      _usuarioSelecionado!.numero,
      _senhaTextController.text,
    );

    if (usuarioLogado == null) {
      throw ErroMensagem("Senha incorreta");
    }

    return usuarioLogado;
  }

  Future _redirecionaTelaPermissoes(BuildContext context) async {
    Usuario usuarioLogado = await _login();
    if (usuarioLogado.isAdmin()) {
      if (context.mounted) {
        Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => AdminApp(usuarioLogado))
        );
      }
    }
    else {
      try{
        Widget proximaTela = await PermissionChain.widgetPermissionChain(usuarioLogado);
        if (context.mounted) {
          Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => proximaTela)
          );
        }

      }
      on ErroMensagem catch(e){
        if (context.mounted) {
          SnackbarGlobal.show(e.toString());
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Acompanhador Ônibus"),
      ),
      body: FutureBuilder(
      future: _futureNomesCongregacoesList,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return LoadingScreen();
        } else {
          return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                  child: const Text('Entrar', style: TextStyle(fontSize: 20)),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                  child: DropdownMenu<Usuario>(
                    enableFilter: false,
                    enableSearch: false,
                    requestFocusOnTap: false,
                    controller: _congregacaoController,
                    menuHeight: 200,
                    label: Container(padding: const EdgeInsets.fromLTRB(0, 0, 0, 0), child: Text("Congregação"), ),
                    width: double.infinity,
                    dropdownMenuEntries: _listaCongregacoesDropDown,
                    inputDecorationTheme: const InputDecorationTheme(
                      filled: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 5.0, horizontal: 10),
                    ),
                    enabled: !_botaoEntrarCarregando && !_bloqueiaFormulario,
                    onSelected: (Usuario? usuario) {
                      setState(() {
                        _usuarioSelecionado = usuario;
                      });
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                  child: TextField(
                    enabled: !_botaoEntrarCarregando && !_bloqueiaFormulario,
                    obscureText: true,
                    controller: _senhaTextController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Senha',
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                  child: ElevatedButton(
                    onPressed:
                    _botaoEntrarCarregando || _bloqueiaFormulario ? null
                        : () async {
                      setState(() {
                        _botaoEntrarCarregando = true;
                      });
                      try {
                        await _redirecionaTelaPermissoes(context);
                      } on ErroMensagem catch (e){
                        if(context.mounted) {
                          SnackbarGlobal.show(e.toString());
                        }
                      }

                      if(context.mounted) {
                        setState(() {
                          _botaoEntrarCarregando = false;
                        });
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      minimumSize: Size.fromHeight(40),
                    ),
                    child: Builder(
                      builder: (context) {
                        if (!_botaoEntrarCarregando) {
                          return const Text('Entrar');
                        } else {
                          return CircularProgressIndicator(
                            padding: EdgeInsets.symmetric(
                              vertical: 2.0,
                              horizontal: 2.0,
                            ),
                          );
                        }
                      },
                    ),
                  ),
                ),
              ],
            );
        }
      }),
    );
  }
}
