/// Small text helpers. No Flutter code here, so they are easy to test.

const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// 1536 -> "2 KB", 3 MB -> "3.0 MB"
String formatBytes(int bytes) {
  final kb = bytes / 1024;
  if (kb >= 1024) return '${(kb / 1024).toStringAsFixed(1)} MB';
  return '${kb.round()} KB';
}

/// "28 Oct 2026"
String formatDate(DateTime date) {
  return '${date.day} ${_months[date.month - 1]} ${date.year}';
}

/// "28 Oct 2026, 21:05"
String formatDateTime(DateTime date) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${formatDate(date)}, ${two(date.hour)}:${two(date.minute)}';
}

/// "just now", "5 min ago", "3 days ago", "2 months ago"
String timeAgo(DateTime date, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(date);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  if (diff.inDays < 30) {
    return diff.inDays == 1 ? '1 day ago' : '${diff.inDays} days ago';
  }
  if (diff.inDays < 365) {
    final months = diff.inDays ~/ 30;
    return months == 1 ? '1 month ago' : '$months months ago';
  }
  final years = diff.inDays ~/ 365;
  return years == 1 ? '1 year ago' : '$years years ago';
}

/// "Good morning", "Good afternoon" or "Good evening"
String greeting({DateTime? now}) {
  final hour = (now ?? DateTime.now()).hour;
  if (hour < 12) return 'Good morning';
  if (hour < 18) return 'Good afternoon';
  return 'Good evening';
}

/// 0 -> "Immediately", 30 -> "30 seconds", 60 -> "1 minute", 300 -> "5 minutes"
String secondsLabel(int seconds) {
  if (seconds <= 0) return 'Immediately';
  if (seconds < 60) return '$seconds seconds';
  final minutes = seconds ~/ 60;
  return minutes == 1 ? '1 minute' : '$minutes minutes';
}
