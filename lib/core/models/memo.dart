import 'package:flutter/foundation.dart';

/// 备忘录条目。
class Memo {
  Memo({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.pinned = false,
  });

  final String id;
  String title;
  String content;
  final DateTime createdAt;
  DateTime updatedAt;

  /// 是否置顶。
  bool pinned;

  factory Memo.create({required String title, required String content}) {
    final now = DateTime.now();
    return Memo(
      id: '${now.microsecondsSinceEpoch}',
      title: title,
      content: content,
      createdAt: now,
      updatedAt: now,
    );
  }

  factory Memo.fromJson(Map<String, dynamic> json) {
    return Memo(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      pinned: json['pinned'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'pinned': pinned,
      };

  Memo copyWith({String? title, String? content, bool? pinned}) {
    return Memo(
      id: id,
      title: title ?? this.title,
      content: content ?? this.content,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      pinned: pinned ?? this.pinned,
    );
  }

  @override
  bool operator ==(Object other) => other is Memo && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

@immutable
class MemoDraft {
  const MemoDraft({required this.title, required this.content});

  final String title;
  final String content;

  bool get isEmpty => title.trim().isEmpty && content.trim().isEmpty;
}
