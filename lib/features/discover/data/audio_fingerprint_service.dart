import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 使用 WebView 执行 CeruMusic 的 AFP WASM 模块生成音频指纹
///
/// 核心思路：
/// 1. 创建不可见的 WebView，加载包含 afp.js 的 HTML
/// 2. 将 WASM 二进制数据通过 base64 传入 JS，设置 window.WASM_BINARY
/// 3. WebView 有完整的 WebAssembly 支持，可以正确执行 Embind 绑定的 WASM
/// 4. 通过 runJavaScript 调用 GenerateFP(pcmData)，通过 JS channel 接收结果
/// 5. 对标 CeruMusic: afp.js 的 GenerateFP(Float32Array) -> base64 指纹
class AudioFingerprintService {
  WebViewController? _controller;
  bool _initialized = false;
  bool _initializing = false;
  Completer<bool>? _initCompleter;

  /// 当前请求 ID，用于匹配请求和响应
  int _requestId = 0;
  final Map<int, Completer<String?>> _pendingRequests = {};

  /// 缓存的 WASM base64 数据（避免重复读取）
  String? _wasmBase64;

  /// 缓存的 afp.js 内容
  String? _afpJsContent;

  /// 初始化 WebView 和 AFP WASM 模块
  Future<bool> initialize() async {
    if (_initialized) return true;
    if (_initializing) {
      return await _initCompleter!.future;
    }

    _initializing = true;
    _initCompleter = Completer<bool>();

    try {
      // 预加载资源
      await _preloadAssets();

      // 构建精简的 HTML 页面
      // afp.js 太大不能内联，通过 loadFlutterAsset 加载
      // 改用 data URI 方式：先加载一个轻量 HTML，再通过 JS 注入 afp.js
      final htmlContent = '''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body>
<script>
// b64decode/b64encode 辅助函数（对标 CeruMusic afp.js 中的定义）
globalThis.b64decode = function(data) {
  return Uint8Array.from(atob(data), function(c) { return c.charCodeAt(0); });
};
globalThis.b64encode = function(data) {
  return btoa(String.fromCharCode.apply(null, data));
};

// WASM 二进制数据占位，由 Dart 端注入
window.WASM_BINARY = null;

// AFP 运行时代码占位，由 Dart 端注入
// AudioFingerprintRuntime 和 GenerateFP 将在注入后可用

// 桥接函数：接收 PCM 数据，生成指纹，通过 channel 返回
window.generateFingerprint = function(requestId, pcmBase64) {
  try {
    var binaryStr = atob(pcmBase64);
    var bytes = new Uint8Array(binaryStr.length);
    for (var i = 0; i < binaryStr.length; i++) {
      bytes[i] = binaryStr.charCodeAt(i);
    }
    var pcmData = new Float32Array(bytes.buffer);

    if (typeof GenerateFP === 'function') {
      GenerateFP(pcmData).then(function(fp) {
        FpChannel.postMessage(JSON.stringify({
          requestId: requestId,
          fingerprint: fp,
          error: null
        }));
      }).catch(function(err) {
        FpChannel.postMessage(JSON.stringify({
          requestId: requestId,
          fingerprint: null,
          error: err.toString()
        }));
      });
    } else {
      FpChannel.postMessage(JSON.stringify({
        requestId: requestId,
        fingerprint: null,
        error: 'GenerateFP not available'
      }));
    }
  } catch (e) {
    FpChannel.postMessage(JSON.stringify({
      requestId: requestId,
      fingerprint: null,
      error: e.toString()
    }));
  }
};

// 通知 HTML 加载完成
FpChannel.postMessage(JSON.stringify({ type: 'html_loaded' }));
</script>
</body>
</html>
''';

      final uri = Uri.dataFromString(
        htmlContent,
        mimeType: 'text/html',
        encoding: Encoding.getByName('utf-8'),
      );

      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..addJavaScriptChannel(
          'FpChannel',
          onMessageReceived: (JavaScriptMessage message) {
            _onJsMessage(message.message);
          },
        )
        ..loadRequest(uri);

      // 等待 HTML 加载完成
      var htmlLoaded = false;
      for (var i = 0; i < 30; i++) {
        await Future.delayed(const Duration(milliseconds: 200));
        try {
          final result = await _controller!.runJavaScriptReturningResult(
            'document.readyState',
          );
          if (result.toString() == '"complete"') {
            htmlLoaded = true;
            break;
          }
        } catch (_) {}
      }

      if (!htmlLoaded) {
        debugPrint('[AFP] HTML 加载超时');
        _completeInit(false);
        return false;
      }

      // 注入 WASM 二进制数据
      debugPrint('[AFP] 注入 WASM 数据, base64 length: ${_wasmBase64!.length}');
      await _controller!.runJavaScript('''
window.WASM_BINARY = "${_wasmBase64!}";
''');

      // 注入 afp.js 运行时代码
      // afp.js 中的反引号和特殊字符需要转义
      final escapedAfpJs = _escapeJsForInjection(_afpJsContent!);
      debugPrint('[AFP] 注入 afp.js, length: ${_afpJsContent!.length}');
      await _controller!.runJavaScript('''
$escapedAfpJs
''');

      // 等待 GenerateFP 可用
      debugPrint('[AFP] 等待 GenerateFP 初始化...');
      for (var i = 0; i < 60; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        try {
          final result = await _controller!.runJavaScriptReturningResult(
            'typeof GenerateFP === "function" ? "ready" : "not_ready"',
          );
          final status = result.toString();
          debugPrint('[AFP] GenerateFP status: $status');
          if (status == '"ready"') {
            _initialized = true;
            debugPrint('[AFP] WebView 初始化成功，GenerateFP 可用');
            _completeInit(true);
            return true;
          }
        } catch (e) {
          debugPrint('[AFP] 检查 GenerateFP 失败: $e');
        }
      }

      debugPrint('[AFP] GenerateFP 初始化超时');
      _completeInit(false);
      return false;
    } catch (e) {
      debugPrint('[AFP] 初始化失败: $e');
      _completeInit(false);
      return false;
    }
  }

  void _completeInit(bool success) {
    _initCompleter?.complete(success);
    _initializing = false;
  }

  /// 预加载资源文件
  Future<void> _preloadAssets() async {
    if (_wasmBase64 != null && _afpJsContent != null) return;

    // 读取 WASM 二进制并转为 base64
    final wasmData = await rootBundle.load('assets/afp/afp.wasm');
    final wasmBytes = wasmData.buffer.asUint8List();
    _wasmBase64 = base64.encode(wasmBytes);

    // 读取 afp.js
    _afpJsContent = await rootBundle.loadString('assets/afp/afp.js');
  }

  /// 转义 JS 代码以便通过 runJavaScript 注入
  /// 需要处理反引号模板字符串、反斜杠等
  String _escapeJsForInjection(String js) {
    // afp.js 不包含模板字符串，主要是普通字符串
    // 主要需要处理的是反斜杠和换行
    // 但 runJavaScript 直接执行 JS，不需要额外转义
    return js;
  }

  /// 处理 JS Channel 消息
  void _onJsMessage(String message) {
    try {
      final data = jsonDecode(message) as Map<String, dynamic>;

      final type = data['type'] as String?;
      if (type == 'html_loaded') {
        debugPrint('[AFP] HTML 加载完成');
        return;
      }
      if (type == 'init') {
        debugPrint('[AFP] JS init message: ${data['status']}');
        return;
      }

      final requestId = data['requestId'] as int?;
      if (requestId != null && _pendingRequests.containsKey(requestId)) {
        final completer = _pendingRequests.remove(requestId)!;
        final error = data['error'] as String?;
        final fingerprint = data['fingerprint'] as String?;

        if (error != null && error.isNotEmpty) {
          debugPrint('[AFP] JS generateFingerprint error: $error');
          completer.complete(null);
        } else if (fingerprint != null) {
          debugPrint('[AFP] 指纹生成成功, base64 length: ${fingerprint.length}');
          completer.complete(fingerprint);
        } else {
          debugPrint('[AFP] JS 返回空结果');
          completer.complete(null);
        }
      }
    } catch (e) {
      debugPrint('[AFP] 解析 JS 消息失败: $e');
    }
  }

  /// 从 8kHz 单声道 PCM 数据生成音频指纹
  ///
  /// 对标 CeruMusic: GenerateFP(Float32Array) -> base64 string
  Future<String?> generateFingerprint(Float32List pcm8k) async {
    if (!_initialized) {
      final ok = await initialize();
      if (!ok) return null;
    }

    try {
      final requestId = ++_requestId;
      final completer = Completer<String?>();
      _pendingRequests[requestId] = completer;

      // 将 Float32List 编码为 base64 传给 JS
      final pcmBytes = pcm8k.buffer.asUint8List();
      final pcmBase64 = base64.encode(pcmBytes);

      debugPrint('[AFP] 发送 PCM 数据: ${pcm8k.length} samples, base64 len: ${pcmBase64.length}');

      // 调用 JS 的 generateFingerprint 函数
      await _controller!.runJavaScript(
        'window.generateFingerprint($requestId, "$pcmBase64")',
      );

      // 等待结果，设置超时
      final result = await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          debugPrint('[AFP] 指纹生成超时');
          _pendingRequests.remove(requestId);
          return null;
        },
      );

      return result;
    } catch (e) {
      debugPrint('[AFP] 指纹生成失败: $e');
      return null;
    }
  }

  void dispose() {
    _controller = null;
    _initialized = false;
    _initializing = false;
    _pendingRequests.clear();
  }
}
