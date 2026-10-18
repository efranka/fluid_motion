import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// Marching squares with linking: instead of a small polygon per cell (which
/// shows facets and seams between cells), the contour is traced as connected
/// loops and drawn as ONE smooth path, with corners rounded by quadratic
/// curves. That lets Flutter anti-alias the whole edge at once.
///
/// [f] is the field on a grid of (cols + 1) × (rows + 1) nodes; negative =
/// inside. The grid's border must be "outside" so every loop is closed.
/// Uses reused number buffers instead of maps and lists, so thousands of
/// objects are not allocated per frame.
Path? traceContour(
  Float64List f,
  int cols,
  int rows,
  double left,
  double top,
  double cell,
) {
  final stride = cols + 1;
  final maxId = 2 * stride * (rows + 1);
  if (_tcSeen.length < maxId) {
    _tcPos = Float32List(maxId * 2);
    _tcLinks = Int32List(maxId * 2);
    _tcSeen = Uint8List(maxId);
    _tcOrder = Int32List(maxId);
  }
  final pos = _tcPos, links = _tcLinks, seen = _tcSeen, order = _tcOrder;
  var count = 0;

  // Edge ids: horizontal edge at node (i, j) = 2·idx, vertical = 2·idx + 1.
  // seen: 0 = unused, 1 = has a point, 2 = visited while tracing.
  void point(int id, int i0, int j0, int i1, int j1) {
    if (seen[id] != 0) return;
    seen[id] = 1;
    links[2 * id] = -1;
    links[2 * id + 1] = -1;
    order[count++] = id;
    final v0 = f[j0 * stride + i0], v1 = f[j1 * stride + i1];
    final t = v0 / (v0 - v1);
    pos[2 * id] = left + (i0 + (i1 - i0) * t) * cell;
    pos[2 * id + 1] = top + (j0 + (j1 - j0) * t) * cell;
  }

  void link(int p, int q) {
    if (links[2 * p] < 0) {
      links[2 * p] = q;
    } else {
      links[2 * p + 1] = q;
    }
    if (links[2 * q] < 0) {
      links[2 * q] = p;
    } else {
      links[2 * q + 1] = p;
    }
  }

  for (var j = 0; j < rows; j++) {
    for (var i = 0; i < cols; i++) {
      final vtl = f[j * stride + i], vtr = f[j * stride + i + 1];
      final vbr = f[(j + 1) * stride + i + 1], vbl = f[(j + 1) * stride + i];
      final tl = vtl < 0, tr = vtr < 0, br = vbr < 0, bl = vbl < 0;
      if (tl == tr && tr == br && br == bl) continue;

      final eT = 2 * (j * stride + i);
      final eB = 2 * ((j + 1) * stride + i);
      final eL = 2 * (j * stride + i) + 1;
      final eR = 2 * (j * stride + i + 1) + 1;
      if (tl != tr) point(eT, i, j, i + 1, j);
      if (tr != br) point(eR, i + 1, j, i + 1, j + 1);
      if (bl != br) point(eB, i, j + 1, i + 1, j + 1);
      if (tl != bl) point(eL, i, j, i, j + 1);

      final crossings = (tl != tr ? 1 : 0) +
          (tr != br ? 1 : 0) +
          (bl != br ? 1 : 0) +
          (tl != bl ? 1 : 0);
      if (crossings == 2) {
        final a = tl != tr ? eT : (tr != br ? eR : eB);
        final b = tl != bl ? eL : (bl != br ? eB : eR);
        link(a, b);
      } else {
        // Saddle point: the centre decides which corners are connected.
        final centerInside = (vtl + vtr + vbr + vbl) / 4 < 0;
        if (tl == centerInside) {
          link(eT, eR);
          link(eB, eL);
        } else {
          link(eT, eL);
          link(eB, eR);
        }
      }
    }
  }
  if (count == 0) return null;

  final path = Path()..fillType = PathFillType.evenOdd;
  final loop = _tcLoop..clear();
  for (var o = 0; o < count; o++) {
    final start = order[o];
    if (seen[start] == 2) continue;
    seen[start] = 2;
    loop
      ..clear()
      ..add(Offset(pos[2 * start], pos[2 * start + 1]));
    var prev = -1, cur = start;
    while (true) {
      final a = links[2 * cur], b = links[2 * cur + 1];
      final next = a != prev ? a : b;
      if (next < 0 || next == start || seen[next] == 2) break;
      seen[next] = 2;
      loop.add(Offset(pos[2 * next], pos[2 * next + 1]));
      prev = cur;
      cur = next;
    }
    if (loop.length < 3) continue;

    // Smooth loop: quadratic curves through the midpoints, with each point
    // as the control point. Removes the grid's facets.
    final n = loop.length;
    Offset mid(int k) => (loop[k % n] + loop[(k + 1) % n]) / 2;
    final m0 = mid(n - 1);
    path.moveTo(m0.dx, m0.dy);
    for (var k = 0; k < n; k++) {
      final c = loop[k], m = mid(k);
      path.quadraticBezierTo(c.dx, c.dy, m.dx, m.dy);
    }
    path.close();
  }
  // Reset only the entries that were used.
  for (var o = 0; o < count; o++) {
    seen[order[o]] = 0;
  }
  return path;
}

Float32List _tcPos = Float32List(0);
Int32List _tcLinks = Int32List(0);
Uint8List _tcSeen = Uint8List(0);
Int32List _tcOrder = Int32List(0);
final List<Offset> _tcLoop = [];

/// Smooth minimum: like min(a, b), but softly rounded within [k]. This is
/// what makes two shapes "flow together".
double smoothMin(double a, double b, double k) {
  final h = math.max(k - (a - b).abs(), 0.0) / k;
  return math.min(a, b) - h * h * k * 0.25;
}
