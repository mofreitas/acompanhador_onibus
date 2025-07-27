class Usuario {
  static final String NOME = "nome";

  String nome;
  String numero;

  Usuario(this.nome, this.numero);

  Usuario.fromJson(Map json) : this.nome = json['nome'], this.numero = json['numero'];

  String getDescricaoUsuario(){
    return "$nome - $numero";
  }

  bool isAdmin(){
    return int.parse(numero) == 0;
  }

  Map toJson(){
    return {
      "nome": this.nome,
      "numero": this.numero
    };
  }
}