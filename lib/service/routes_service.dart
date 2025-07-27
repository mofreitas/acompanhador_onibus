
import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class RoutesService{
  RoutesService();

  Future<RouteResponse?> requestInformacoesRota(LatLng localizacaoCentro, LatLng localizacaoOnibus) async {
    RouteRequest routeRequest = RouteRequest(localizacaoCentro, localizacaoOnibus);
    return _requestInformacoesRota(routeRequest);
  }

  Future<RouteResponse?> _requestInformacoesRota(RouteRequest requestBody) async {
    final response = await http.post(
      Uri.parse('https://routes.googleapis.com/directions/v2:computeRoutes'),
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": dotenv.env['GOOGLE_ROUTES_API_KEY'] ?? '',
        "X-Goog-FieldMask": "routes.duration,routes.distanceMeters",
        "X-Android-Package": "com.mathe.acompanhador_onibus_congresso",
        "X-Android-Cert": dotenv.env['GOOGLE_CERT'] ?? ''
      },
      body: jsonEncode(requestBody.toJson())
    );

    if(response.statusCode == 200){
      var responseBody = response.body;
      try{
        return RouteResponse.fromJson(jsonDecode(responseBody));
      }
      on Error catch (e){
        return null;
      }
    }
    return null;
  }
}


class RouteRequest{
  final LatLng localizacaoOnibus;
  final LatLng localizacaoCentro;

  RouteRequest(this.localizacaoCentro, this.localizacaoOnibus);

  Map toJson(){
    return{
      "origin": {
        "location": {
          "latLng": {
            "latitude": localizacaoOnibus.latitude,
            "longitude": localizacaoOnibus.longitude
          }
        }
      },
      "destination": {
        "location": {
          "latLng": {
            "latitude": localizacaoCentro.latitude,
            "longitude": localizacaoCentro.longitude
          }
        }
      },
      "travelMode": "DRIVE",
      "routingPreference": "TRAFFIC_AWARE",
      "computeAlternativeRoutes": false,
      "languageCode": "pt-BR",
      "units": "METRIC"
    };
  }
}


class RouteResponse{
  final int eta;
  final int distancia;

  RouteResponse.fromJson(Map json) :
        eta = int.parse(json['routes'][0]["duration"].toString().replaceAll("s", "")),
        distancia = int.parse(json['routes'][0]['distanceMeters'].toString());

  RouteResponse() : eta = 0, distancia = 0;

}