package com.europa.janus_client_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 통화가 시작/종료될 때 Dart 쪽에서 서비스를 켜고 끈다.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "janus/call_service",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    CallForegroundService.start(this, call.argument<String>("peer"))
                    result.success(null)
                }
                "stop" -> {
                    CallForegroundService.stop(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
