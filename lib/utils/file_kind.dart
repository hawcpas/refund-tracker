import 'package:flutter/material.dart';

/// ============================
/// FILE KIND ENUM
/// ============================

enum FileKind {
  pdf,
  word,
  excel,
  powerpoint,
  accounting,
  image,
  text,
  archive,
  audio,
  video,
  code,
  data,
  email,
  cad,
  threeD,
  link,
  executable, // ✅ ADD
  unknown,
}

/// ============================
/// FILE KIND META
/// ============================

class FileKindMeta {
  final IconData icon;
  final Color color;
  final String badge;
  final String tooltip;
  final bool isImage;

  const FileKindMeta({
    required this.icon,
    required this.color,
    required this.badge,
    required this.tooltip,
    this.isImage = false,
  });
}

const _royalBlue = Color(0xFF1D4ED8);
const _pdfRed = Color(0xFFE11D2E);
const _excelGreen = Color(0xFF107C41);
const _quickBooksGreen = Color(0xFF66CC00);
const _imageCyan = Color(0xFF00DBF1);
const _wordBlue = Color(0xFF3262A9);
const _powerPointOrange = Color(0xFFEC603D);
const _executableBlack = Color(0xFF000000);

const Map<FileKind, FileKindMeta> fileKindMeta = {
  FileKind.pdf: FileKindMeta(
    icon: Icons.picture_as_pdf,
    color: _pdfRed,
    badge: 'PDF',
    tooltip: 'PDF document',
  ),
  FileKind.word: FileKindMeta(
    icon: Icons.description_outlined,
    color: _wordBlue,
    badge: 'DOC',
    tooltip: 'Word document',
  ),
  FileKind.excel: FileKindMeta(
    icon: Icons.table_chart_outlined,
    color: _excelGreen,
    badge: 'XLS',
    tooltip: 'Spreadsheet',
  ),
  FileKind.powerpoint: FileKindMeta(
    icon: Icons.slideshow_outlined,
    color: _powerPointOrange,
    badge: 'PPT',
    tooltip: 'Presentation',
  ),
  FileKind.accounting: FileKindMeta(
    icon: Icons.account_balance_wallet_outlined,
    color: _quickBooksGreen,
    badge: 'QB',
    tooltip: 'Accounting file (QuickBooks / Quicken)',
  ),
  FileKind.image: FileKindMeta(
    icon: Icons.image_outlined,
    color: _imageCyan,
    badge: 'IMG',
    tooltip: 'Image file',
    isImage: true,
  ),
  FileKind.text: FileKindMeta(
    icon: Icons.article_outlined,
    color: _royalBlue,
    badge: 'TXT',
    tooltip: 'Text file',
  ),
  FileKind.archive: FileKindMeta(
    icon: Icons.archive_outlined,
    color: _royalBlue,
    badge: 'ZIP',
    tooltip: 'Archive',
  ),
  FileKind.audio: FileKindMeta(
    icon: Icons.audiotrack_outlined,
    color: _royalBlue,
    badge: 'AUD',
    tooltip: 'Audio file',
  ),
  FileKind.video: FileKindMeta(
    icon: Icons.movie_outlined,
    color: _royalBlue,
    badge: 'VID',
    tooltip: 'Video file',
  ),

  FileKind.code: FileKindMeta(
    icon: Icons.code_outlined,
    color: _royalBlue,
    badge: 'CODE',
    tooltip: 'Source code',
  ),

  FileKind.data: FileKindMeta(
    icon: Icons.data_object_outlined,
    color: _royalBlue,
    badge: 'DATA',
    tooltip: 'Data file',
  ),

  FileKind.email: FileKindMeta(
    icon: Icons.mail_outline,
    color: _royalBlue,
    badge: 'MAIL',
    tooltip: 'Email message',
  ),

  FileKind.cad: FileKindMeta(
    icon: Icons.architecture_outlined,
    color: _royalBlue,
    badge: 'CAD',
    tooltip: 'CAD file',
  ),

  FileKind.threeD: FileKindMeta(
    icon: Icons.view_in_ar_outlined,
    color: _royalBlue,
    badge: '3D',
    tooltip: '3D model',
  ),

  FileKind.executable: FileKindMeta(
    icon: Icons.apps_outlined,
    color: _executableBlack,
    badge: 'EXE',
    tooltip: 'Executable file',
  ),

  FileKind.link: FileKindMeta(
    icon: Icons.link_outlined,
    color: _royalBlue,
    badge: 'URL',
    tooltip: 'Web link',
  ),

  FileKind.unknown: FileKindMeta(
    icon: Icons.insert_drive_file_outlined,
    color: _royalBlue,
    badge: 'FILE',
    tooltip: 'File',
  ),
};

/// ============================
/// EXTENSION SETS
/// ============================
String _normalizeFileName(String name) {
  return name.trim().split('?').first.split('#').first;
}

String _ext(String name) {
  final clean = _normalizeFileName(name);
  final i = clean.lastIndexOf('.');
  return (i == -1) ? '' : clean.substring(i + 1).toLowerCase();
}

const _accountingExt = {'qbo', 'qbx', 'qbb', 'qbw', 'qif', 'ofx', 'qfx', 'iif'};
const _exeExt = {
  'exe', // Windows
  'msi', // Windows installer
  'bat',
  'cmd',
  'app', // macOS bundle
  'sh', // scripts (optional, if you want)
};

const _wordExt = {'doc', 'docx', 'docm'};
const _excelExt = {'xls', 'xlsx', 'xlsm', 'csv'};
const _pptExt = {'ppt', 'pptx', 'pptm'};
const _imageExt = {
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'bmp',
  'tif',
  'tiff',
  'heic',
};
const _linkExt = {
  'url', // Windows Internet Shortcut
  'lnk', // Windows shortcut (optional)
};
const _textExt = {'txt', 'log', 'md'};
const _archiveExt = {'zip', '7z', 'rar', 'tar', 'gz', 'tgz', 'bz2'};
const _audioExt = {'mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg'};
const _videoExt = {'mp4', 'mov', 'mkv', 'avi', 'webm'};
const _codeExt = {
  'dart',
  'js',
  'ts',
  'json',
  'yaml',
  'yml',
  'xml',
  'html',
  'css',
  'ps1',
  'sh',
};
const _emailExt = {'eml', 'msg'};
const _cadExt = {'dwg', 'dxf'};
const _threeDExt = {'stl', 'obj', 'fbx', 'glb', 'gltf'};
const _dataExt = {'sql', 'db', 'sqlite', 'sqlite3', 'parquet', 'avro', 'orc'};

/// ============================
/// PUBLIC API
/// ============================

FileKind detectFileKind({
  required String fileName,
  required String contentType,
}) {
  final type = contentType.toLowerCase().trim();
  final ext = _ext(fileName);

  // ✅ PDFs
  if (type == 'application/pdf') return FileKind.pdf;

  // ✅ Windows executables (browser MIME variants)
  if (type == 'application/x-msdownload' ||
      type == 'application/x-ms-installer') {
    return FileKind.executable;
  }

  // ✅ Office & media MIME
  if (type.contains('word')) return FileKind.word;
  if (type.contains('excel') || type.contains('spreadsheet')) {
    return FileKind.excel;
  }
  if (type.contains('powerpoint')) return FileKind.powerpoint;
  if (type.startsWith('image/')) return FileKind.image;
  if (type.startsWith('audio/')) return FileKind.audio;
  if (type.startsWith('video/')) return FileKind.video;
  if (type.contains('json')) return FileKind.code;
  if (type.contains('xml')) return FileKind.code;
  if (type.contains('html')) return FileKind.code;

  // ✅ Extension fallback (ordered!)
  if (_accountingExt.contains(ext)) return FileKind.accounting;
  if (_dataExt.contains(ext)) return FileKind.data;
  if (_wordExt.contains(ext)) return FileKind.word;
  if (_excelExt.contains(ext)) return FileKind.excel;
  if (_pptExt.contains(ext)) return FileKind.powerpoint;
  if (_imageExt.contains(ext)) return FileKind.image;
  if (_textExt.contains(ext)) return FileKind.text;
  if (_archiveExt.contains(ext)) return FileKind.archive;
  if (_audioExt.contains(ext)) return FileKind.audio;
  if (_videoExt.contains(ext)) return FileKind.video;
  if (_emailExt.contains(ext)) return FileKind.email;
  if (_cadExt.contains(ext)) return FileKind.cad;
  if (_threeDExt.contains(ext)) return FileKind.threeD;
  if (_codeExt.contains(ext)) return FileKind.code;
  if (_linkExt.contains(ext)) return FileKind.link;
  if (_exeExt.contains(ext)) return FileKind.executable;

  return FileKind.unknown;
}

FileKindMeta resolveFileMeta({
  required String fileName,
  required String contentType,
}) {
  final kind = detectFileKind(fileName: fileName, contentType: contentType);

  final meta = fileKindMeta[kind]!;

  // ✅ Links: force URL badge
  if (kind == FileKind.link) {
    return meta.copyWith(badge: 'URL');
  }

  // ✅ Accounting: show actual extension (QBO, QBX, etc.)
  if (kind == FileKind.accounting) {
    final ext = _ext(fileName).toUpperCase();
    return meta.copyWith(
      badge: ext.isNotEmpty && ext.length <= 4 ? ext : meta.badge,
    );
  }

  // ✅ Executables: show actual extension (EXE, MSI, BAT, APP)
  if (kind == FileKind.executable) {
    final ext = _ext(fileName).toUpperCase();
    return meta.copyWith(
      badge: ext.isNotEmpty && ext.length <= 4 ? ext : meta.badge,
    );
  }

  return meta;
}

extension on FileKindMeta {
  FileKindMeta copyWith({String? badge}) => FileKindMeta(
    icon: icon,
    color: color,
    badge: badge ?? this.badge,
    tooltip: tooltip,
    isImage: isImage,
  );
}
