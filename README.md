# acompanhador_onibus_congresso

Um projeto para acompanhar os ônibus que se dirigem ao um local específico.

O aplicativo dá para ser acessado como admin e usuário.

## Admin

![Imagem tela Admin](https://github.com/mofreitas/acompanhador_onibus/readme_images/ss1.jpg)

O Admin tem a capacidade de acompanhar todos os ônibus. Além disso, ele tm o possibilidade de saber o tempo estimado até o local

## Usuário

![Imagem tela Usuário](https://github.com/mofreitas/acompanhador_onibus/readme_images/ss3.jpg)

O usuário envia sua localização para os administradores. Ele tem a estimativa de chegada com base em sua localização atual.  

# Stack

Este projeto utiliza:
* Google Maps
* Firebase
* Google Routes API 

O aplicativo foi disponibilizado para android e WEB

## Para efetuar o deploy

### Deploy versão android 
```bash
flutter build appbundle --release
```

### Deploy na web
```bash
flutter build web
firebase deploy  
#firebase hosting:disable 
```
