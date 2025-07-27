import 'dart:async';
import 'dart:collection';

import 'package:acompanhador_onibus_congresso/dominio/onibus_congregacao.dart';

class PreencheMarcadorExecutor {
  final Queue<Execucao> _queue = Queue();
  final Future<void> Function(List<OnibusCongregacao>, OnibusCongregacao?) callbackPreencheMarcador;

  Completer<void>? _notifier;
  bool _isClosed = false;

  PreencheMarcadorExecutor(this.callbackPreencheMarcador) {
    _startProcessingLoop();
  }

  void run(List<OnibusCongregacao> onibusCongregacoes, OnibusCongregacao? onibusSelecionado, bool opcional) async {
    final exec = Execucao(onibusCongregacoes, onibusSelecionado, opcional);

    if (opcional) {
      _queue.removeWhere((e) => e.opcional); // keep only newest optional
    }

    _queue.add(exec);
    _notifier?.complete(); // Wake up the processor
  }

  void _startProcessingLoop() async {
    while (!_isClosed) {
      if (_queue.isEmpty) {
        _notifier = Completer<void>();
        await _notifier!.future;
        _notifier = null;
        if (_isClosed) break;
      }

      while (_queue.isNotEmpty) {
        final exec = _queue.removeFirst();
        await callbackPreencheMarcador(exec.onibusCongregacoes, exec.onibusSelecionado);
      }
    }
  }

  void close() {
    _isClosed = true;
    _notifier?.complete();
  }
}

class Execucao {
  List<OnibusCongregacao> onibusCongregacoes;
  OnibusCongregacao? onibusSelecionado;
  bool opcional;

  Execucao(this.onibusCongregacoes, this.onibusSelecionado, this.opcional);
}
