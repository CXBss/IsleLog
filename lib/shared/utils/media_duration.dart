/// 媒体时长文本：一小时以内 `mm:ss`，超过则 `h:mm:ss`。
String formatMediaDuration(Duration d) {
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  if (d.inHours == 0) return '$m:$s';
  return '${d.inHours}:$m:$s';
}
