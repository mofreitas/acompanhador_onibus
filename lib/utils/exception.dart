class ErroMensagem implements Exception {
  final String message;
  ErroMensagem(this.message);

  @override
  String toString() => message;
}
