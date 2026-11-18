/// What to do on the TV so its text field matches [next], given that it
/// currently matches [old]: delete [deleted] characters from the end, then
/// type [inserted]. Counts are in characters (runes), not UTF-16 units.
({int deleted, String inserted}) diffText(String old, String next) {
  final a = old.runes.toList();
  final b = next.runes.toList();
  var i = 0;
  while (i < a.length && i < b.length && a[i] == b[i]) {
    i++;
  }
  return (deleted: a.length - i, inserted: String.fromCharCodes(b.sublist(i)));
}
