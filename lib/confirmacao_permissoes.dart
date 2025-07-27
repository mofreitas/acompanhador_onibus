
import 'package:acompanhador_onibus_congresso/dominio/usuario.dart';
import 'package:acompanhador_onibus_congresso/geolocalizacao.dart';
import 'package:acompanhador_onibus_congresso/loading_screen.dart';
import 'package:acompanhador_onibus_congresso/main.dart';
import 'package:acompanhador_onibus_congresso/service/local_data.dart';
import 'package:acompanhador_onibus_congresso/snackbar_global.dart';
import 'package:acompanhador_onibus_congresso/user.dart';
import 'package:acompanhador_onibus_congresso/utils/exception.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionChain {
  static Future<Widget> widgetPermissionChain(Usuario usuarioLogado) async {
    bool servicoLocalizacaoAtivado = await Geolocalizacao
        .isServicoLocalizacaoHabilitado();
    if (!servicoLocalizacaoAtivado) {
      throw ErroMensagem("A localização do dispositivo deve estar habilitada!");
    }

    Widget? infoNotificacao;
    Widget? infoLocalizacao;
    Widget telaUsuario = UserApp(usuarioLogado);

    if(!kIsWeb) {
      var statusPermissaoNotificacao = Permission.notification.status;
      bool deveExibirPermissaoNotificacao = await statusPermissaoNotificacao
          .isDenied
          && !await LocalData.getPermissoesNotificacoesExibida() &&
          !await LocalData.getPermissoesNotificacoesNegada();
      if (deveExibirPermissaoNotificacao) {
        infoNotificacao = InfoNotificacao(
            nextWidget: telaUsuario, usuarioLogado: usuarioLogado);
      }
    }

    bool permissaoLocalizacao = await Geolocalizacao
        .isPermissaoServicoLocalizacao();
    if (!permissaoLocalizacao) {
      infoLocalizacao = InfoLocalizacao(
          nextWidget: infoNotificacao ?? telaUsuario,
          usuarioLogado: usuarioLogado);
    }

    return infoLocalizacao ?? infoNotificacao ?? telaUsuario;
  }
}

abstract class StatefulWidgetPermissionHandler extends StatefulWidget {
  final Widget? nextWidget;
  final Usuario usuarioLogado;

  const StatefulWidgetPermissionHandler({required this.nextWidget, required this.usuarioLogado, super.key});

  void next(BuildContext context){
    if(nextWidget != null){
      Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => nextWidget!)
      );
    }
    else{
      SnackbarGlobal.show("Ocorreu um erro. Por favor, tente novamente.");
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) =>
            RouterHandler()),
            (_) => false,
      );
    }
  }
}

class InfoLocalizacao extends StatefulWidgetPermissionHandler {
  const InfoLocalizacao({super.key, required super.nextWidget, required super.usuarioLogado});

  @override
  State<StatefulWidget> createState() => _InfoLocalizacaoState();
}

class _InfoLocalizacaoState extends State<InfoLocalizacao> {
  bool _carregando = false;

  @override
  Widget build(BuildContext context) {
   if(_carregando){
     return LoadingScreen();
   }

   return PopScope(
     canPop: false,
       child: Material (
          child: Padding(padding: EdgeInsets.all(10),
            child: Column(
            spacing: 10,
            children: [
              Expanded(child: Column(
                      mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.location_on_outlined, size: 40,),
                        Text("Uso da localização.", style: TextStyle(fontSize: 22), textAlign: TextAlign.center,),
                        Text("Este aplicativo coleta os dados de sua localização para compatilhá-los com os coordenadores do setor mesmo quando o aplicativo está fechado ou não está em uso.", style: TextStyle(fontSize: 18), textAlign: TextAlign.center,),
                        Text("A não habilitação desse recurso impede o funcionamento adequado do aplicativo.", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center,),
                      ],
                    ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ElevatedButton(
                      onPressed: () async {
                        await LocalData.limparDados();

                        if(context.mounted) {
                          SnackbarGlobal.show("O aplicativo precisa da permissão para funcionar");
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(builder: (context) =>
                                RouterHandler()),
                                (_) => false,
                          );
                        }
                      },
                      child: Text("Não aceito")
                  ),
                  Spacer(),
                  ElevatedButton(
                      onPressed: () async {
                        setState(() {
                          _carregando = true;
                        });

                        bool permissaoLocalizacaoConcedida = await Geolocalizacao.requisitaPermissao();
                        if(permissaoLocalizacaoConcedida) {
                          if(context.mounted) {
                            widget.next(context);
                          }
                        } else{
                          await LocalData.limparDados();
                          if(context.mounted) {
                            SnackbarGlobal.show("O aplicativo precisa da permissão para funcionar.");
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(builder: (context) =>
                                  RouterHandler()),
                                  (_) => false,
                            );
                          }
                        }
                      },
                      child: Text("Confirmo uso")
                  ),
                ]),
            ])
       ))
    );
  }
}

class InfoNotificacao extends StatefulWidgetPermissionHandler {
  const InfoNotificacao({super.key, required super.nextWidget, required super.usuarioLogado});

  @override
  State<StatefulWidget> createState() => _InfoNotificacaoState();
}

class _InfoNotificacaoState extends State<InfoNotificacao> {
  bool _carregando = false;

  @override
  Widget build(BuildContext context) {
    if(_carregando){
      return LoadingScreen();
    }

    return PopScope(
        canPop: false,
        child: Material (
            child: Padding(padding: EdgeInsets.all(10),
                child: Column(
                    spacing: 10,
                    children: [
                      Expanded(child: Column(
                        mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.notifications, size: 40,),
                          Text("Envio de Notificações.", style: TextStyle(fontSize: 22), textAlign: TextAlign.center,),
                          Text("Este aplicativo envia notificações para informar se o serviço de localização está ativo", style: TextStyle(fontSize: 18), textAlign: TextAlign.center,),
                        ],
                      ),
                      ),
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            ElevatedButton(
                                onPressed: () async {
                                  setState(() {
                                    _carregando = true;
                                  });

                                  await LocalData.salvarPermissoesNotificacoesNegada();

                                  if(context.mounted) {
                                    widget.next(context);
                                  }
                                },
                                child: Text("Não aceito")
                            ),
                            Spacer(),
                            ElevatedButton(
                                onPressed: () async {
                                  setState(() {
                                    _carregando = true;
                                  });

                                  await Permission.notification.request();
                                  if(context.mounted) {
                                    widget.next(context);
                                  }
                                },
                                child: Text("Confirmo uso")
                            ),
                          ]),
                    ])
            ))
    );
  }
}

