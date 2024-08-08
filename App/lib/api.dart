import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http_parser/http_parser.dart';

class Api {
  final Dio _dio = Dio();

  // for gpt backend
  static var oldBaseURL = "https://jashaws.chickenkiller.com/api1/";
  static var baseURL = "https://jashaws.chickenkiller.com/api2/";

  // endpoints(routes):
  static final loginRoute = "${baseURL}login";
  static final signupRoute = "${baseURL}register";
  static final uploadImageRoute = "${oldBaseURL}upload";
  static final getDescriptionsRoute = "${baseURL}description";
  static final getAnswerRoute = "${baseURL}ask";

  void setBaseURL(String url) {
    baseURL = url;
  }

  Future login(String email, String password) async {
    try {
      final response = await _dio.post(loginRoute, data: {
        "email": email,
        "password": password,
      });
      return response.data;
    } catch (e) {
      // print(e);
    }
  }

  Future<String> getDescription(
      String imageUrl, String latitude, String longitude) async {
    try {
      final response = await _dio.post(getDescriptionsRoute, data: {
        "image_url": imageUrl,
        "latitude": latitude,
        "longitude": longitude
      });
      // print(response);
      return response.data['description'];
    } catch (e) {
      if (kDebugMode) {
        print(e);
      }
      return "";
    }
  }

  Future<String> getAnswer(String question, String imageUrl, messages) async {
    // print("Here");
    try {
      final response = await _dio.post(getAnswerRoute, data: {
        "question": question,
        "image_url": imageUrl,
        "chats": messages
      });
      // print(response);
      return response.data['answer'];
    } catch (e) {
      if (kDebugMode) {
        print(e);
      }
      return "";
    }
  }

  Future<Map> uploadImage(
      String imagePath, String latitude, String longitude) async {
    try {
      // print('Uploading image: $imagePath');
      // final response = await _dio.post(uploadImageRoute, data: {
      //   'file': imagePath,
      // });
      // send the file as FormData
      // print("calling api");
      FormData formData = FormData.fromMap({
        "file": await MultipartFile.fromFile(imagePath,
            filename: "image.jpg", contentType: MediaType('image', 'jpg')),
        "caption": "",
        "latitude": latitude,
        "longitude": longitude,
        "saveData": "false",
      });

      final response = await _dio.post(uploadImageRoute, data: formData);
      // print('Response from upload: ${response.data}');
      // return response.data;
      if (response.statusCode == 200) {
        if (kDebugMode) {
          // print("Image saved successfully");
          // print("Response: $response");
        }
        final description = await getDescription(
            response.data['data']['image_url'], latitude, longitude);
        return {
          "image_url": response.data['data']['image_url'],
          "description": description
        };
      } else {
        return {};
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error uploading image: $e');
      }
      return {};
    }
  }
}
