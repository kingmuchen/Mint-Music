class PluginSource {
  final String name;
  final List<String> qualities;

  const PluginSource({
    required this.name,
    required this.qualities,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'qualities': qualities,
      };

  factory PluginSource.fromJson(Map<String, dynamic> json) {
    return PluginSource(
      name: json['name'] as String,
      qualities: List<String>.from(json['qualities'] as List),
    );
  }
}

class PluginInfo {
  final String id;
  final String name;
  final String version;
  final String author;
  final String description;
  final String type;
  final bool isEnabled;
  final DateTime installTime;
  final List<PluginSource> supportedSources;
  final String? filePath;
  final String? updateUrl;

  const PluginInfo({
    required this.id,
    required this.name,
    required this.version,
    required this.author,
    this.description = '',
    this.type = 'cr',
    this.isEnabled = true,
    required this.installTime,
    this.supportedSources = const [],
    this.filePath,
    this.updateUrl,
  });

  PluginInfo copyWith({
    String? id,
    String? name,
    String? version,
    String? author,
    String? description,
    String? type,
    bool? isEnabled,
    DateTime? installTime,
    List<PluginSource>? supportedSources,
    String? filePath,
    String? updateUrl,
  }) {
    return PluginInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      version: version ?? this.version,
      author: author ?? this.author,
      description: description ?? this.description,
      type: type ?? this.type,
      isEnabled: isEnabled ?? this.isEnabled,
      installTime: installTime ?? this.installTime,
      supportedSources: supportedSources ?? this.supportedSources,
      filePath: filePath ?? this.filePath,
      updateUrl: updateUrl ?? this.updateUrl,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'version': version,
      'author': author,
      'description': description,
      'type': type,
      'isEnabled': isEnabled,
      'installTime': installTime.toIso8601String(),
      'supportedSources': supportedSources.map((s) => s.toJson()).toList(),
      'filePath': filePath,
      if (updateUrl != null) 'updateUrl': updateUrl,
    };
  }

  factory PluginInfo.fromJson(Map<String, dynamic> json) {
    return PluginInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      version: json['version'] as String,
      author: json['author'] as String,
      description: json['description'] as String? ?? '',
      type: json['type'] as String? ?? 'cr',
      isEnabled: json['isEnabled'] as bool? ?? true,
      installTime: DateTime.parse(json['installTime'] as String),
      supportedSources: (json['supportedSources'] as List<dynamic>?)
              ?.map((e) => PluginSource.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      filePath: json['filePath'] as String?,
      updateUrl: json['updateUrl'] as String?,
    );
  }
}