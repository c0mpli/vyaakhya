import 'package:flutter/material.dart';
import 'package:get/get.dart';

void customSnackbar(String title, String message) {
  Get.snackbar(
    title,
    message,
    snackPosition: SnackPosition.BOTTOM,
    backgroundColor: Colors.red,
    colorText: Colors.white,
    padding: const EdgeInsets.all(16),
  );
}

void customDialog(String title, String message) {
  Get.defaultDialog(
    title: title,
    middleText: message,
    backgroundColor: Colors.white,
    titleStyle: const TextStyle(color: Colors.black),
    middleTextStyle: const TextStyle(color: Colors.black),
    confirm: ElevatedButton(
      onPressed: () {
        Get.back();
        Get.back();
      },
      child: const Text('OK'),
    ),
  );
}

void customLoadingOverlay(String title) {
  Get.dialog(
    barrierDismissible: false,
    barrierColor: Colors.black.withOpacity(0.5),
    PopScope(
      canPop: false,
      child: Material(
        color: Colors.black.withOpacity(0.5),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Focus(
                autofocus: true,
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    // background: Paint()..color = Colors.black,
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    ),
  );
}