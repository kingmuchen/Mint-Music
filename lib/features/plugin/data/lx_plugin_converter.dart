import 'dart:convert';

class LxPluginConverter {
  String convert(String originalCode) {
    final info = _parseScriptInfo(originalCode);
    final pluginInfoJson = jsonEncode(info);

    return '''
var __lxInitError = null;
var __lxInitDone = false;
var __lxInitReported = false;
var __lxRequestHandler = null;
var __lxUpdateAlertSent = false;
var __lxFallbackTimerIdCounter = 0;

var pluginInfo = $pluginInfoJson;
// The original LX source is executed by PluginHost in a separate evaluate()
// call. Keeping it out of this adapter avoids a large string literal and a
// nested new Function compilation inside QuickJS.
var originalPluginCode = '';
var sources = {};
var sourceActions = {};

// Some LX scripts validate the runtime metadata against their canonical name
// instead of the display name in the file header (for example, YNX-Pro).
function __lxCanonicalScriptName(value) {
  var name = String(value || '').replace(/^\\uFEFF/, '').trim();
  // Keep this ASCII-only so generated code is not affected by source encoding.
  return name.replace(/-pro${r'$'}/i, '');
}

var __lxRuntimeScriptName = __lxCanonicalScriptName(pluginInfo.name);

var EVENT_NAMES = {
  request: 'request',
  inited: 'inited',
  updateAlert: 'updateAlert'
};

function __lxSafeError(error) {
  if (!error) return 'failed';
  return error.message || String(error);
}

function __lxParseBody(value) {
  if (typeof value !== 'string') return value;
  try { return JSON.parse(value); } catch(e) { return value; }
}

function __lxBytesFromString(text) {
  if (typeof __stringToBytes === 'function') return __stringToBytes(String(text || ''));
  var arr = [];
  text = String(text || '');
  for (var i = 0; i < text.length; i++) arr.push(text.charCodeAt(i) & 0xff);
  return arr;
}

function __lxEncodeForm(form) {
  if (!form || typeof form !== 'object') return form;
  var parts = [];
  Object.keys(form).forEach(function(key) {
    var value = form[key];
    if (value == null) value = '';
    parts.push(encodeURIComponent(key) + '=' + encodeURIComponent(String(value)));
  });
  return parts.join('&');
}

function __lxNormalizeSources(data) {
  var nextSources = data && data.sources ? data.sources : data;
  if (!nextSources || typeof nextSources !== 'object') return;
  Object.keys(sources).forEach(function(k) { delete sources[k]; });
  Object.keys(sourceActions).forEach(function(k) { delete sourceActions[k]; });
  Object.keys(nextSources).forEach(function(sourceId) {
    var item = nextSources[sourceId] || {};
    var qualities = item.qualitys || item.qualities || item.types || ['128k', '320k', 'flac'];
    var actions = item.actions || ['musicUrl'];
    sources[sourceId] = {
      name: item.name || sourceId,
      type: item.type || 'music',
      qualitys: qualities,
      qualities: qualities,
      actions: actions
    };
     sourceActions[sourceId] = (actions.slice ? actions.slice() : ['musicUrl'])
       .map(function(action) { return String(action).toLowerCase(); });
  });
}

function __lxEventName(value) {
  return String(value || '').replace(/^lx[._:-]/i, '').toLowerCase();
}

function __lxHasAction(source, action) {
  var actions = sourceActions[source];
  if (!actions && sources[source]) return action === 'musicUrl';
  if (!actions) return false;
  return actions.indexOf(action) !== -1 || actions.indexOf(String(action).toLowerCase()) !== -1;
}

function __lxNormalizeMusicUrlResult(response, payload) {
  if (typeof response === 'string') {
    response = response.trim();
    if (/^https?:\\/\\//i.test(response)) {
      return { source: payload.source, action: payload.action, data: { type: payload.info.type, url: response } };
    }
    try { response = JSON.parse(response); } catch(e) {}
  }

  function parseNested(value) {
    if (typeof value !== 'string') return value;
    var text = value.trim();
    if (!text) return text;
    try { return JSON.parse(text); } catch(e) { return text; }
  }

  function findUrl(value) {
    value = parseNested(value);
    if (typeof value === 'string') {
      return /^https?:\\/\\//i.test(value.trim()) ? value.trim() : '';
    }
    if (!value || typeof value !== 'object') return '';
    var directKeys = ['url', 'src', 'playUrl', 'play_url', 'location', 'audioUrl', 'audio_url'];
    for (var i = 0; i < directKeys.length; i++) {
      var direct = findUrl(value[directKeys[i]]);
      if (direct) return direct;
    }
    var nestedKeys = ['data', 'body', 'result', 'response'];
    for (var j = 0; j < nestedKeys.length; j++) {
      var nested = findUrl(value[nestedKeys[j]]);
      if (nested) return nested;
    }
    if (Array.isArray(value)) {
      for (var k = 0; k < value.length; k++) {
        var item = findUrl(value[k]);
        if (item) return item;
      }
    }
    return '';
  }

  function findValue(value, keys) {
    value = parseNested(value);
    if (!value || typeof value !== 'object') return '';
    for (var i = 0; i < keys.length; i++) {
      if (typeof value[keys[i]] === 'string' && value[keys[i]].trim()) return value[keys[i]].trim();
    }
    var nestedKeys = ['data', 'body', 'result', 'response'];
    for (var j = 0; j < nestedKeys.length; j++) {
      var nested = findValue(value[nestedKeys[j]], keys);
      if (nested) return nested;
    }
    return '';
  }

  function findHeaders(value) {
    value = parseNested(value);
    var headers = {};
    if (!value || typeof value !== 'object') return headers;
    ['requestHeaders', 'httpHeaders', 'headers'].forEach(function(key) {
      var current = value[key];
      if (current && typeof current === 'object' && !Array.isArray(current)) {
        Object.keys(current).forEach(function(header) {
          if (current[header] != null && String(current[header]).trim()) headers[header] = String(current[header]);
        });
      }
    });
    ['data', 'body', 'result', 'response'].forEach(function(key) {
      var nested = findHeaders(value[key]);
      Object.keys(nested).forEach(function(header) { headers[header] = nested[header]; });
    });
    return headers;
  }

  if (response && typeof response === 'object') {
    var url = findUrl(response);
    var type = findValue(response, ['quality', 'type', 'format', 'level']) || payload.info.type;
    if (url) {
      var normalized = { source: payload.source, action: payload.action, data: { type: type, url: url } };
      var headers = findHeaders(response);
      if (Object.keys(headers).length) normalized.headers = headers;
      return normalized;
    }
  }
  throw new Error('failed');
}

function __lxNormalizeSearchResult(response, limit) {
  if (typeof response === 'string') {
    try { response = JSON.parse(response); } catch(e) { return { list: [], total: 0, isEnd: true }; }
  }
  if (!response) return { list: [], total: 0, isEnd: true };
  if (Array.isArray(response)) return { list: response, total: response.length, isEnd: response.length < limit };
  var data = response.data || {};
  var list = response.list || response.lists || data.list || data.lists || data.data || [];
  if (!Array.isArray(list)) list = [];
  var total = response.total || response.totalCount || data.total || list.length;
  return { list: list, total: total, isEnd: response.isEnd === true || list.length < limit };
}

function __lxNormalizeLyricResult(response) {
  if (typeof response === 'string') {
    try { return JSON.parse(response); } catch(e) { return response; }
  }
  if (!response) return null;
  if (response.body && typeof response.body === 'object') return response.body;
  return response;
}

function __lxNormalizePicResult(response) {
  if (typeof response === 'string') return response;
  if (!response) return null;
  var data = response.data || response.body || {};
  return response.url || response.pic || response.img || data.url || data.pic || data.img || null;
}

function __lxRequest(url, options, callback) {
  if (typeof options === 'function') {
    callback = options;
    options = {};
  }
  options = options || {};
  var headers = {};
  var optionHeaders = options.headers || {};
  Object.keys(optionHeaders).forEach(function(key) { headers[key] = optionHeaders[key]; });
  var body = options.body;
  if (options.form) {
    if (!headers['content-type'] && !headers['Content-Type']) headers['content-type'] = 'application/x-www-form-urlencoded;charset=UTF-8';
    body = __lxEncodeForm(options.form);
  } else if (options.formData && body == null) {
    body = options.formData;
  }

  var cancelled = false;
  var requestOptions = {
    method: options.method || 'GET',
    headers: headers,
    body: body,
    timeout: typeof options.timeout === 'number' ? options.timeout : 20000,
    follow_max: typeof options.follow_max === 'number' ? options.follow_max : 5
  };

  // Use the two-argument form of then(). Some Android flutter_js builds expose
  // Promise.then() but do not expose Promise.prototype.catch() as a callable.
  var promise = cerumusic.request(url, requestOptions).then(function(result) {
    try {
      // Keep this response bridge self-contained. A few LX scripts modify
      // shared built-ins while bootstrapping, which can turn a converter
      // helper or Object.prototype method into a non-callable value.
      var statusCode = result && (result.statusCode || result.status)
        ? (result.statusCode || result.status) : 200;
      var headers = result && typeof result.headers === 'object' && result.headers
        ? result.headers : {};
      var bodyText = result && typeof result.body !== 'undefined' ? result.body : result;
      var body = bodyText;
      if (typeof bodyText === 'string') {
        try { body = JSON.parse(bodyText); } catch(e) { body = bodyText; }
      }
      var raw = Array.isArray(result && result.raw) ? result.raw : [];
      if (!raw.length && result && typeof result.bodyBase64 === 'string') {
        var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
        var lookup = {};
        for (var ci = 0; ci < chars.length; ci++) lookup[chars[ci]] = ci;
        var encoded = result.bodyBase64;
        for (var bi = 0; bi < encoded.length; bi += 4) {
          var ba = lookup[encoded[bi]] || 0;
          var bb = lookup[encoded[bi + 1]] || 0;
          var bc = lookup[encoded[bi + 2]] || 0;
          var bd = lookup[encoded[bi + 3]] || 0;
          raw.push((ba << 2) | (bb >> 4));
          if (encoded[bi + 2] !== '=') raw.push(((bb & 15) << 4) | (bc >> 2));
          if (encoded[bi + 3] !== '=') raw.push(((bc & 3) << 6) | bd);
        }
      }
      var resp = {
        statusCode: statusCode,
        statusMessage: result && result.statusMessage ? result.statusMessage : String(statusCode),
        headers: headers,
        bytes: raw.length || 0,
        raw: raw,
        body: body
      };
      if (!cancelled && typeof callback === 'function') callback(null, resp, body);
      return resp;
    } catch (error) {
      if (!cancelled && typeof callback === 'function') {
        callback(error instanceof Error ? error : new Error(String(error)), null, null);
        return null;
      }
      throw error;
    }
  }, function(error) {
    if (!cancelled && typeof callback === 'function') {
      callback(error instanceof Error ? error : new Error(__lxSafeError(error)), null, null);
      return null;
    }
    throw error;
  });

  if (callback) {
    return function() { cancelled = true; };
  }
  return promise;
}

  var mockLx = {
  EVENT_NAMES: EVENT_NAMES,
  request: __lxRequest,
  send: function(eventName, data) {
    var normalizedEvent = __lxEventName(eventName);
    if (normalizedEvent === 'inited' || normalizedEvent === 'initialized') {
      // Keep the lifecycle side effect synchronous, but return the Promise
      // required by the mobile LX contract for callers that await or chain it.
      if (__lxInitReported) return Promise.resolve();
      __lxInitReported = true;
      __lxNormalizeSources(data);
      return Promise.resolve();
    }
    if (normalizedEvent === 'updatealert' || normalizedEvent === 'update') {
      if (!__lxUpdateAlertSent) {
        __lxUpdateAlertSent = true;
        try {
          console.log('[LX Adapter] updateAlert received, data type=' + typeof data + ', data=' + JSON.stringify(data));
          cerumusic.NoticeCenter('update', data);
          console.log('[LX Adapter] updateAlert NoticeCenter sent successfully');
        } catch(e) {
          console.log('[LX Adapter] updateAlert error: ' + e);
        }
      }
      return Promise.resolve();
    }
    return Promise.reject(new Error('The event is not supported: ' + eventName));
  },
  on: function(eventName, handler) {
    var normalizedEvent = __lxEventName(eventName);
    if ((normalizedEvent === 'request' || normalizedEvent === 'req') && typeof handler === 'function') {
      __lxRequestHandler = handler;
      // Older LX-compatible hosts look up requestHandler as a global. Keep
      // that alias in sync while the converter uses its private reference.
      try {
        var runtimeGlobal = Function('return this')();
        runtimeGlobal.requestHandler = handler;
      } catch(e) {}
      return Promise.resolve();
    }
    return Promise.reject(new Error('The event is not supported: ' + eventName));
  },
  utils: {
    crypto: {
      aesEncrypt: function(buffer, mode, key, iv) { return cerumusic.utils.crypto.aesEncrypt(buffer, mode, key, iv); },
      rsaEncrypt: function(buffer, key) { return cerumusic.utils.crypto.rsaEncrypt(buffer, key); },
      randomBytes: function(size) { return cerumusic.utils.crypto.randomBytes(size); },
      md5: function(value) { return __md5Hash(String(value)); }
    },
    buffer: {
      from: function(value, encodingOrOffset, length) { return Buffer.from(value, encodingOrOffset, length); },
      bufToString: function(buf, format) { return cerumusic.utils.buffer.bufToString(buf, format); }
    },
    zlib: {
      inflate: function(buf) { return cerumusic.utils.zlib.inflate(buf); },
      deflate: function(data) { return cerumusic.utils.zlib.deflate(data); }
    }
  },
  currentScriptInfo: {
    name: __lxRuntimeScriptName,
    version: pluginInfo.version,
    author: pluginInfo.author,
    description: pluginInfo.description || '',
    homepage: pluginInfo.homepage || '',
    rawScript: originalPluginCode
  },
  // Match the API contract used by CeruMusic and LX Music desktop plugins.
  version: '2.0.0',
  apiVersion: '2.0.0',
  env: 'mobile'
};

var lx = mockLx;
try {
  var __realGlobal = Function('return this')();
  __realGlobal.lx = mockLx;
  __realGlobal.window = __realGlobal;
  __realGlobal.self = __realGlobal;
  __realGlobal.globalThis = __realGlobal;
} catch(e) {}

function __lxEnsureReady(action) {
  if (!__lxInitDone) throw new Error('LX 音源尚未完成初始化');
  // A number of legacy scripts register request before a non-critical
  // background check throws. CeruMusic keeps those handlers usable; only a
  // missing handler means the script cannot serve requests.
  if (__lxInitError && !__lxRequestHandler) {
    throw new Error('LX 音源初始化失败: ' + __lxInitError);
  }
  if (!__lxRequestHandler) throw new Error('LX 音源未注册 request 事件');
  if (action && action.source && action.action && !__lxHasAction(action.source, action.action)) {
    throw new Error('LX 音源不支持 ' + action.source + '/' + action.action);
  }
}

function __lxCallRequest(payload) {
  __lxEnsureReady(payload);
  return Promise.resolve(__lxRequestHandler(payload));
}

function musicUrl(source, musicInfo, quality) {
  var payload = { source: source, action: 'musicUrl', info: { type: quality || '320k', musicInfo: musicInfo || {} } };
  return __lxCallRequest(payload).then(function(result) { return __lxNormalizeMusicUrlResult(result, payload); });
}

function search(source, keyword, page, limit) {
  limit = limit || 30;
  var payload = { source: source, action: 'musicSearch', info: { keyword: keyword, page: page || 1, limit: limit, pagesize: limit } };
  if (!__lxHasAction(source, 'musicSearch')) return Promise.resolve({ list: [], total: 0, isEnd: true });
  return __lxCallRequest(payload).then(function(result) { return __lxNormalizeSearchResult(result, limit); }, function() {
    return { list: [], total: 0, isEnd: true };
  });
}

function getPic(source, musicInfo) {
  var action = __lxHasAction(source, 'musicPic') ? 'musicPic' : (__lxHasAction(source, 'pic') ? 'pic' : null);
  if (!action) return Promise.resolve(null);
  return __lxCallRequest({ source: source, action: action, info: { musicInfo: musicInfo || {} } }).then(__lxNormalizePicResult, function() { return null; });
}

function getLyricResult(source, musicInfo) {
  var action = __lxHasAction(source, 'lyric') ? 'lyric' : (__lxHasAction(source, 'musicLyric') ? 'musicLyric' : null);
  if (!action) return Promise.resolve(null);
  return __lxCallRequest({ source: source, action: action, info: { musicInfo: musicInfo || {} } }).then(__lxNormalizeLyricResult, function() { return null; });
}

function getLyric(source, musicInfo) {
  return getLyricResult(source, musicInfo).then(function(result) {
    if (!result) return null;
    if (typeof result === 'string') return result;
    return result.crlyric || result.lxlyric || result.yrc || result.qrc || result.krc || result.mrc || result.lrcx || result.lyric || result.lrc || null;
  });
}

function initializePluginEnvironment() {
  try {
    // Keep the plugin in a small sandbox. Some Android flutter_js builds expose
    // timer names as non-callable host values on the real global object.
    var __runtimeGlobal = {};
    try { __runtimeGlobal = Function('return this')(); } catch(e) {}
    // Reuse the host's Dart-backed timer bridge. The native flutter_js timer
    // entrypoint is unsafe on some Android/Windows builds and must never be
    // called for a converted LX plugin.
    var __mintSetTimeout = typeof __mintSafeSetTimeout === 'function'
      ? __mintSafeSetTimeout : null;
    var __mintClearTimeout = typeof __mintSafeClearTimeout === 'function'
      ? __mintSafeClearTimeout : null;
    var __mintSetInterval = typeof __mintSafeSetInterval === 'function'
      ? __mintSafeSetInterval : null;
    var __mintClearInterval = typeof __mintSafeClearInterval === 'function'
      ? __mintSafeClearInterval : null;
    var __nativeSetTimeout = __runtimeGlobal && typeof __runtimeGlobal.setTimeout === 'function'
      ? __runtimeGlobal.setTimeout : null;
    var __nativeClearTimeout = __runtimeGlobal && typeof __runtimeGlobal.clearTimeout === 'function'
      ? __runtimeGlobal.clearTimeout : null;
    var __nativeSetInterval = __runtimeGlobal && typeof __runtimeGlobal.setInterval === 'function'
      ? __runtimeGlobal.setInterval : null;
    var __nativeClearInterval = __runtimeGlobal && typeof __runtimeGlobal.clearInterval === 'function'
      ? __runtimeGlobal.clearInterval : null;

    var __lxSetTimeout = function(callback, delay) {
      if (__mintSetTimeout) {
        try { return __mintSetTimeout.apply(null, arguments); } catch(e) {}
      }
      if (__nativeSetTimeout) {
        try { return __nativeSetTimeout.call(__runtimeGlobal, callback, delay); } catch(e) {}
      }
      // There is no asynchronous timer primitive in some flutter_js Android
      // builds. Do not invoke a timeout callback synchronously: that would
      // reject network requests before the Dart HTTP bridge can respond.
      var timerId = ++__lxFallbackTimerIdCounter;
      return timerId;
    };
    var __lxClearTimeout = function(timerId) {
      if (__mintClearTimeout) {
        try { __mintClearTimeout(timerId); return; } catch(e) {}
      }
      if (__nativeClearTimeout) {
        try { __nativeClearTimeout.call(__runtimeGlobal, timerId); } catch(e) {}
      }
    };
    var __lxSetInterval = function(callback, delay) {
      if (__mintSetInterval) {
        try { return __mintSetInterval.apply(null, arguments); } catch(e) {}
      }
      if (__nativeSetInterval) {
        try { return __nativeSetInterval.call(__runtimeGlobal, callback, delay); } catch(e) {}
      }
      var timerId = ++__lxFallbackTimerIdCounter;
      return timerId;
    };
    var __lxClearInterval = function(timerId) {
      if (__mintClearInterval) {
        try { __mintClearInterval(timerId); return; } catch(e) {}
      }
      if (__nativeClearInterval) {
        try { __nativeClearInterval.call(__runtimeGlobal, timerId); } catch(e) {}
      }
    };
    // The original script is evaluated by the host after this environment is
    // ready. Expose the same globals that the former Function wrapper passed
    // as parameters, without compiling the large source as a nested function.
    __runtimeGlobal = Function('return this')();
    __runtimeGlobal.lx = mockLx;
    __runtimeGlobal.setTimeout = __lxSetTimeout;
    __runtimeGlobal.clearTimeout = __lxClearTimeout;
    __runtimeGlobal.setInterval = __lxSetInterval;
    __runtimeGlobal.clearInterval = __lxClearInterval;
    __runtimeGlobal.Buffer = Buffer;
    __runtimeGlobal.process = { env: { NODE_ENV: 'production' } };
    __runtimeGlobal.require = function() { return {}; };
  } catch(error) {
    __lxInitError = __lxSafeError(error);
    __lxInitDone = true;
    console.log('[LX] 初始化失败: ' + __lxInitError);
  }
}

function __lxFinalizePluginInitialization() {
  __lxInitDone = true;
}

initializePluginEnvironment();

module.exports = {
  pluginInfo: pluginInfo,
  sources: sources,
  sourceActions: sourceActions,
  musicUrl: musicUrl,
  search: search,
  getPic: getPic,
  getLyric: getLyric,
  getLyricResult: getLyricResult
};
''';
  }

  Map<String, String> _parseScriptInfo(String code) {
    final comment = RegExp(r'^/\*[\s\S]+?\*/').firstMatch(code)?.group(0) ?? '';
    final values = <String, String>{
      'name': '',
      'version': '',
      'author': '',
      'description': '',
      'homepage': '',
    };

    final matcher = RegExp(r'^\s?\*\s?@(\w+)\s(.+)$');
    for (final rawLine in comment.split(RegExp(r'\r?\n'))) {
      final match = matcher.firstMatch(rawLine);
      if (match == null) continue;
      final key = match.group(1);
      if (key == null || !values.containsKey(key)) continue;
      values[key] = match.group(2)?.trim() ?? '';
    }

    values['name'] = _limit(
      values['name']!.isEmpty ? 'LX 音源' : values['name']!,
      24,
    );
    values['version'] = _limit(
      values['version']!.isEmpty ? '1.0.0' : values['version']!,
      36,
    );
    values['author'] = _limit(
      values['author']!.isEmpty ? 'Unknown' : values['author']!,
      56,
    );
    values['description'] = _limit(values['description']!, 36);
    values['homepage'] = _limit(values['homepage']!, 1024);
    return values;
  }

  String _limit(String value, int maxLength) {
    return value.length > maxLength
        ? '${value.substring(0, maxLength)}...'
        : value;
  }
}
