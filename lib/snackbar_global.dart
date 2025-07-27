
import 'package:flutter/material.dart';

class SnackbarGlobal {
  static int snackbarInternet = 1;
  static int snackbarAtivacaoGeral = 2;

  static final Set<int> _snackBarsFixasAtivas = {};

  static GlobalKey<ScaffoldMessengerState> key =
  GlobalKey<ScaffoldMessengerState>();

  static void show(String message) {
    if(_snackBarsFixasAtivas.isEmpty) {
      key.currentState!
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  static void showFixedSnackbar(int tipo, String message) {
    if(!_snackBarsFixasAtivas.contains(tipo)) {
      key.currentState!
          .showSnackBar(SnackBar(content: Text(message),
        behavior: SnackBarBehavior.fixed,
        duration: Duration(days: 365),));

      _snackBarsFixasAtivas.add(tipo);
    }
  }

  static void hideFixedSnackbar(int tipo) {
    key.currentState!.hideCurrentSnackBar();
    _snackBarsFixasAtivas.remove(tipo);
  }

  static void removeSnackBar() {
    key.currentState!.clearSnackBars();
    _snackBarsFixasAtivas.clear();
  }
}