class Grupo implements Comparable<Grupo> {
  double hue;
  String horario;

  Grupo(this.hue, this.horario);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Grupo && runtimeType == other.runtimeType && horario == other.horario;

  @override
  int get hashCode => horario.hashCode;

  @override
  int compareTo(Grupo other) {
    return horario.compareTo(other.horario);
  }


}