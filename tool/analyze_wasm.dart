import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 分析 afp.wasm.js 中的 WASM_BINARY，提取 WASM 二进制并分析导入/导出
void main() async {
  // 读取 afp.wasm.js
  final wasmJsFile = File('assets/afp/afp.wasm.js');
  final content = await wasmJsFile.readAsString();

  // 提取 base64 编码的 WASM_BINARY（跨多行）
  final match = RegExp(r"const WASM_BINARY\s*=\s*'([A-Za-z0-9+/=\s]+)'", dotAll: true).firstMatch(content);
  if (match == null) {
    print('ERROR: Could not find WASM_BINARY in afp.wasm.js');
    return;
  }

  final base64Str = match.group(1)!.replaceAll(RegExp(r'\s'), '');
  print('WASM_BINARY base64 length: ${base64Str.length}');

  // 解码 base64
  final wasmBytes = base64Decode(base64Str);
  print('WASM binary size: ${wasmBytes.length} bytes');

  // 保存为 .wasm 文件
  final wasmFile = File('assets/afp/afp.wasm');
  await wasmFile.writeAsBytes(wasmBytes);
  print('Saved to assets/afp/afp.wasm');

  // 简单解析 WASM 头部
  if (wasmBytes.length >= 8) {
    final magic = String.fromCharCodes(wasmBytes.sublist(0, 4));
    final version = wasmBytes.sublist(4, 8);
    print('Magic: $magic (expected: \\0asm)');
    print('Version: ${version[0]}.${version[1]}.${version[2]}.${version[3]}');
  }

  // 解析 WASM sections 来找导入和导出
  _parseWasmSections(wasmBytes);
}

void _parseWasmSections(Uint8List bytes) {
  int offset = 8; // skip magic + version

  while (offset < bytes.length) {
    final sectionId = bytes[offset++];
    final (size, newOffset) = _readLEB128(bytes, offset);
    offset = newOffset;

    switch (sectionId) {
      case 2: // Import section
        print('\n=== IMPORT SECTION (size: $size) ===');
        _parseImports(bytes, offset, offset + size);
        break;
      case 7: // Export section
        print('\n=== EXPORT SECTION (size: $size) ===');
        _parseExports(bytes, offset, offset + size);
        break;
      case 1: // Type section
        print('\n=== TYPE SECTION (size: $size) ===');
        _parseTypes(bytes, offset, offset + size);
        break;
      case 3: // Function section
        print('\n=== FUNCTION SECTION (size: $size) ===');
        _parseFunctionSection(bytes, offset, offset + size);
        break;
      default:
        print('\n=== SECTION $sectionId (size: $size) - skipped ===');
        break;
    }
    offset += size;
  }
}

void _parseTypes(Uint8List bytes, int start, int end) {
  int offset = start;
  final (count, newOffset) = _readLEB128(bytes, offset);
  offset = newOffset;
  print('Type count: $count');

  for (int i = 0; i < count && offset < end; i++) {
    final form = bytes[offset++];
    if (form == 0x60) { // func type
      final (paramCount, p) = _readLEB128(bytes, offset);
      offset = p;
      final params = <int>[];
      for (int j = 0; j < paramCount; j++) {
        params.add(bytes[offset++]);
      }
      final (resultCount, r) = _readLEB128(bytes, offset);
      offset = r;
      final results = <int>[];
      for (int j = 0; j < resultCount; j++) {
        results.add(bytes[offset++]);
      }
      if (i < 30 || params.length > 0 || results.length > 0) {
        print('  [$i] func(${_valueTypes(params)}) -> ${_valueTypes(results)}');
      }
    }
  }
}

String _valueTypes(List<int> types) {
  return types.map((t) {
    switch (t) {
      case 0x7F: return 'i32';
      case 0x7E: return 'i64';
      case 0x7D: return 'f32';
      case 0x7C: return 'f64';
      case 0x70: return 'funcref';
      case 0x6F: return 'externref';
      default: return '0x${t.toRadixString(16)}';
    }
  }).join(', ');
}

void _parseFunctionSection(Uint8List bytes, int start, int end) {
  int offset = start;
  final (count, newOffset) = _readLEB128(bytes, offset);
  offset = newOffset;
  print('Function count: $count');
  // Just list first few
  for (int i = 0; i < count && offset < end && i < 20; i++) {
    final (typeIdx, p) = _readLEB128(bytes, offset);
    offset = p;
    print('  func[$i] type=$typeIdx');
  }
  if (count > 20) print('  ... and ${count - 20} more');
}

(int, int) _readLEB128(Uint8List bytes, int offset) {
  int result = 0;
  int shift = 0;
  while (true) {
    final byte = bytes[offset++];
    result |= (byte & 0x7F) << shift;
    if ((byte & 0x80) == 0) break;
    shift += 7;
  }
  return (result, offset);
}

String _readName(Uint8List bytes, int offset) {
  final (len, newOffset) = _readLEB128(bytes, offset);
  final name = String.fromCharCodes(bytes.sublist(newOffset, newOffset + len));
  return name;
}

void _parseImports(Uint8List bytes, int start, int end) {
  int offset = start;
  final (count, newOffset) = _readLEB128(bytes, offset);
  offset = newOffset;
  print('Import count: $count');

  for (int i = 0; i < count && offset < end; i++) {
    final (modLen, modStart) = _readLEB128(bytes, offset);
    final mod = String.fromCharCodes(bytes.sublist(modStart, modStart + modLen));
    offset = modStart + modLen;

    final (nameLen, nameStart) = _readLEB128(bytes, offset);
    final name = String.fromCharCodes(bytes.sublist(nameStart, nameStart + nameLen));
    offset = nameStart + nameLen;

    final kind = bytes[offset++];
    String kindStr;
    switch (kind) {
      case 0: // Function
        final (typeIdx, p) = _readLEB128(bytes, offset);
        offset = p;
        kindStr = 'func (type: $typeIdx)';
        break;
      case 1: // Table
        final elemType = bytes[offset++];
        final (min, p) = _readLEB128(bytes, offset);
        offset = p;
        final hasMax = bytes[offset++];
        if (hasMax != 0) {
          final (max, p2) = _readLEB128(bytes, offset);
          offset = p2;
          kindStr = 'table (elem: ${_valType(elemType)}, min: $min, max: $max)';
        } else {
          kindStr = 'table (elem: ${_valType(elemType)}, min: $min)';
        }
        break;
      case 2: // Memory
        final flags = bytes[offset++];
        final (min, p) = _readLEB128(bytes, offset);
        offset = p;
        if (flags & 1 != 0) {
          final (max, p2) = _readLEB128(bytes, offset);
          offset = p2;
          kindStr = 'memory (min: $min, max: $max)';
        } else {
          kindStr = 'memory (min: $min)';
        }
        break;
      case 3: // Global
        final valType = bytes[offset++];
        final mutable = bytes[offset++];
        kindStr = 'global (type: ${_valType(valType)}, mutable: $mutable)';
        break;
      default:
        kindStr = 'unknown ($kind)';
    }
    print('  [$i] "$mod"."$name" -> $kindStr');
  }
}

void _parseExports(Uint8List bytes, int start, int end) {
  int offset = start;
  final (count, newOffset) = _readLEB128(bytes, offset);
  offset = newOffset;
  print('Export count: $count');

  for (int i = 0; i < count && offset < end; i++) {
    final (nameLen, nameStart) = _readLEB128(bytes, offset);
    final name = String.fromCharCodes(bytes.sublist(nameStart, nameStart + nameLen));
    offset = nameStart + nameLen;

    final kind = bytes[offset++];
    final (idx, p) = _readLEB128(bytes, offset);
    offset = p;

    String kindStr;
    switch (kind) {
      case 0: kindStr = 'func'; break;
      case 1: kindStr = 'table'; break;
      case 2: kindStr = 'memory'; break;
      case 3: kindStr = 'global'; break;
      default: kindStr = 'unknown($kind)';
    }
    print('  [$i] "$name" -> $kindStr #$idx');
  }
}

String _valType(int t) {
  switch (t) {
    case 0x7F: return 'i32';
    case 0x7E: return 'i64';
    case 0x7D: return 'f32';
    case 0x7C: return 'f64';
    case 0x70: return 'funcref';
    case 0x6F: return 'externref';
    default: return '0x${t.toRadixString(16)}';
  }
}
