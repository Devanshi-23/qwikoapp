enum MediaSource { file, sample }

/// A photo picked on the device (`file`) or a built-in demo placeholder
/// (`sample`). Rendered through `MediaImage` on every platform.
class MediaRef {
  const MediaRef.file(String this.path)
    : source = MediaSource.file,
      sampleId = null;

  const MediaRef.sample(String this.sampleId)
    : source = MediaSource.sample,
      path = null;

  final MediaSource source;
  final String? path;
  final String? sampleId;

  @override
  bool operator ==(Object other) =>
      other is MediaRef &&
      other.source == source &&
      other.path == path &&
      other.sampleId == sampleId;

  @override
  int get hashCode => Object.hash(source, path, sampleId);

  @override
  String toString() => 'MediaRef(${source.name}: ${path ?? sampleId})';
}
