# 洛雪音源适配说明

## 目标

本项目的洛雪音源宿主需要尽量对齐 Sollin-Music 的实现方式，让用户导入的 LX 音源脚本可以稳定使用搜索、播放地址、封面与歌词能力。

参考源码：

- `D:\软件\下载\Sollin-Music-Desktop-main\Sollin-Music-Desktop-main\electron\lxSourcePreload.ts`
- `D:\软件\下载\Sollin-Music-Desktop-main\Sollin-Music-Desktop-main\electron\lxSourceRuntime.ts`
- `D:\软件\下载\Sollin-Music-Desktop-main\Sollin-Music-Desktop-main\electron\lxSourceShared.ts`
- `D:\软件\下载\Sollin-Music-Desktop-main\Sollin-Music-Desktop-main\src\services\lxSource.ts`

## 宿主契约

`lx_plugin_converter.dart` 现在按 Sollin 的 `lx` 全局对象形态注入：

- `lx.request(url, options, callback)` 支持洛雪常用回调签名 `(err, resp, body)`，同时兼容 Promise 调用。
- `lx.send('inited', { sources })` 使用单次初始化守卫，重复初始化会拒绝。
- `lx.on('request', handler)` 保存音源脚本注册的请求处理器。
- `lx.EVENT_NAMES`、`lx.currentScriptInfo`、`lx.version`、`lx.apiVersion`、`lx.env` 均已补齐。
- `lx.utils.buffer`、`lx.utils.crypto`、`lx.utils.zlib` 对齐洛雪脚本常用工具入口。

## 请求与结果归一化

洛雪脚本的 `musicUrl` 请求统一转为：

```json
{
  "source": "tx",
  "action": "musicUrl",
  "info": {
    "type": "320k",
    "musicInfo": {}
  }
}
```

播放地址结果兼容以下形态：

- 裸字符串：`https://...`
- `{ "url": "https://..." }`
- `{ "data": { "url": "https://..." } }`
- `{ "body": { "data": { "url": "https://..." } } }`

## 歌曲元数据

`Song.lx` 用于保存插件搜索结果里的平台特定字段，后续获取播放地址、歌词、封面时会完整回传给脚本。重点字段包括：

- `songmid`、`songId`、`hash`
- `albumId`、`albumMid`、`strMediaMid`
- `copyrightId`、`interval`
- `types`、`_types`、`typeUrl`
- `lrcUrl`、`mrcUrl`、`trcUrl`

这样可以避免“搜索能搜到，但播放地址或歌词拿不到”的问题。

## 原生桥接

`js_engine_service.dart` 提供以下桥接能力：

- HTTP：统一返回 `body`、`statusCode`、`headers`。
- MD5：JS 侧同步实现，避免洛雪脚本把 Promise 当字符串使用。
- AES：Dart 侧用 `pointycastle` 实现 CBC/ECB + PKCS7。
- RSA：Dart 侧解析 PEM 公钥并按 `RSA_NO_PADDING` 左填充到密钥长度后加密。
- zlib：Dart 侧用 `archive` 实现 inflate/deflate，JS 侧以字节数组返回。

## 已知边界

Flutter JS 通道本身是异步模型，因此 AES、RSA、zlib 通过 Promise 返回。大多数洛雪脚本在网络与加密流程中本来就是异步链路；如果遇到极少数脚本同步调用 AES/RSA 并立即 `.toString()`，后续需要补纯 JS AES/RSA 实现。
