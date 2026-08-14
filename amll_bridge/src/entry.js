/**
 * AMLL Lyric Player WebView Bridge Entry
 *
 * Builds a standalone JS bundle that can run in a Flutter WebView.
 * Only includes the lyric player (no Pixi background renderer).
 */

import { LyricPlayer, LayoutAlignAnchor, MaskObsceneWordsMode } from '@applemusic-like-lyrics/core'

let player = null

// == Initialization ==
function initLyricPlayer(containerId) {
  const container = document.getElementById(containerId)
  if (!container) throw new Error('Container #' + containerId + ' not found')

  player = new LyricPlayer()
  container.appendChild(player.getElement())

  // dispatch line-click events back to Flutter
  player.addEventListener('line-click', function (e) {
    try {
      // 方法1: 从事件对象获取
      var startTime = e.line ? e.line.startTime : -1
      
      // 方法2: 通过 lineIndex 从歌词数据回溯（更可靠）
      if ((startTime === undefined || startTime === null || startTime < 0) && e.lineIndex >= 0 && player.currentLyricLines) {
        var dataLine = player.currentLyricLines[e.lineIndex]
        if (dataLine && typeof dataLine.startTime === 'number') {
          startTime = dataLine.startTime
        }
      }
      
      // 兜底: 如果还是没有，用 0
      if (startTime === undefined || startTime === null || startTime < 0) startTime = 0
      
      const detail = {
        type: 'line-click',
        lineIndex: e.lineIndex,
        startTime: startTime
      }
      // flutter_inappwebview bridge
      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler('AmllChannel', JSON.stringify(detail))
      }
    } catch (ex) {
      console.warn('[AmllBridge] line-click handler error:', ex)
    }
  })

  return true
}

// == Set lyric lines ==
function setLyricLines(jsonStr) {
  if (!player) return
  try {
    const lines = JSON.parse(jsonStr)
    player.setLyricLines(lines)
  } catch (ex) {
    console.warn('[AmllBridge] setLyricLines error:', ex)
  }
}

// == Update playback position (ms) ==
let _lastTime = -1
function setCurrentTime(ms) {
  if (!player) return
  _lastTime = ms
  player.setCurrentTime(ms)
}

// == Play / Pause ==
function setPlaying(playing) {
  if (!player) return
  if (playing) player.resume()
  else player.pause()
}

// == Update visual config ==
function setConfig(jsonStr) {
  if (!player) return
  try {
    const cfg = JSON.parse(jsonStr)
    if (cfg.enableBlur !== undefined) player.setEnableBlur(cfg.enableBlur)
    if (cfg.enableScale !== undefined) player.setEnableScale(cfg.enableScale)
    if (cfg.enableSpring !== undefined) player.setEnableSpring(cfg.enableSpring)
    if (cfg.alignPosition !== undefined) player.setAlignPosition(cfg.alignPosition)
    if (cfg.wordFadeWidth !== undefined) player.setWordFadeWidth(cfg.wordFadeWidth)
    if (cfg.hidePassedLines !== undefined) player.setHidePassedLines(cfg.hidePassedLines)
    // 字体配置（参照 CeruMusic: 通过 CSS 变量控制 AMLL LyricPlayer 字体）
    const el = player.getElement()
    if (el) {
      // fontFamily: 空字符串或 'system' 使用默认字体，其他直接应用
      if (cfg.fontFamily !== undefined) {
        var ff = (cfg.fontFamily || '').trim()
        if (!ff || ff === 'system') {
          ff = 'sans-serif'
        }
        el.style.fontFamily = ff
      }
      // fontSizeRate: 调整 --amll-lp-font-size 的倍率
      if (cfg.fontSizeRate !== undefined && cfg.fontSizeRate !== 1.0) {
        var base = 'calc(min(clamp(30px,2.5vw,50px),5vh) * ' + cfg.fontSizeRate + ')'
        el.style.setProperty('--amll-lp-font-size', base)
      } else if (cfg.fontSizeRate !== undefined) {
        el.style.setProperty('--amll-lp-font-size', 'calc(min(clamp(30px,2.5vw,50px),5vh))')
      }
      // fontWeight
      if (cfg.fontWeight !== undefined) {
        el.style.fontWeight = String(cfg.fontWeight)
      }
    }
  } catch (ex) {
    console.warn('[AmllBridge] setConfig error:', ex)
  }
}

// == Dispose ==
function dispose() {
  if (player) {
    player.dispose()
    player = null
  }
}

// == Per-frame animation update (called from requestAnimationFrame) ==
let _rafId = null
let _lastRafTime = 0

function _startAnimationLoop() {
  if (_rafId) return
  _lastRafTime = performance.now()
  function tick(now) {
    const delta = now - _lastRafTime
    _lastRafTime = now
    if (player) {
      player.update(delta)
    }
    _rafId = requestAnimationFrame(tick)
  }
  _rafId = requestAnimationFrame(tick)
}

function _stopAnimationLoop() {
  if (_rafId) {
    cancelAnimationFrame(_rafId)
    _rafId = null
  }
}

// == Expose public API ==
window.AmllBridge = {
  init: initLyricPlayer,
  setLyricLines: setLyricLines,
  setCurrentTime: setCurrentTime,
  setPlaying: setPlaying,
  setConfig: setConfig,
  dispose: dispose,
  startAnimation: _startAnimationLoop,
  stopAnimation: _stopAnimationLoop,
}

// Auto-start animation when bridge is ready
document.addEventListener('DOMContentLoaded', function () {
  _startAnimationLoop()
})
