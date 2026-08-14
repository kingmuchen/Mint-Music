double strSim(String s1, String s2) {
  final t1 = s1.toLowerCase().trim();
  final t2 = s2.toLowerCase().trim();
  if (t1 == t2) return 1.0;

  final b1 = _bigrams(t1);
  final b2 = _bigrams(t2);
  if (b1.isEmpty || b2.isEmpty) return t1 == t2 ? 1.0 : 0.0;

  var inter = 0;
  for (final x in b1) {
    if (b2.contains(x)) inter++;
  }
  return (2.0 * inter) / (b1.length + b2.length);
}

Set<String> _bigrams(String str) {
  final res = <String>{};
  for (var i = 0; i < str.length - 1; i++) {
    res.add(str.substring(i, i + 2));
  }
  return res;
}
