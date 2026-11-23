/// 04:32, or 1:04:32 past an hour.
String clock(int ms) {
  final s = ms ~/ 1000;
  String two(int v) => v.toString().padLeft(2, '0');
  return s >= 3600 ? '${s ~/ 3600}:${two(s ~/ 60 % 60)}:${two(s % 60)}' : '${two(s ~/ 60)}:${two(s % 60)}';
}

/// "4 minutes 32 seconds", for screen readers.
String spokenTime(int ms) {
  final s = ms ~/ 1000;
  final parts = <String>[
    if (s >= 3600) _unit(s ~/ 3600, 'hour'),
    if (s >= 60) _unit(s ~/ 60 % 60, 'minute'),
    _unit(s % 60, 'second'),
  ];
  return parts.join(' ');
}

String _unit(int n, String word) => '$n $word${n == 1 ? '' : 's'}';

/// "38 h of space left" at the default 96 kbit/s.
String spaceLeft(int freeBytes) {
  final hours = freeBytes / (96000 / 8) / 3600;
  if (hours >= 1) return '${hours.floor()} h of space left';
  return '${(hours * 60).floor()} min of space left';
}
