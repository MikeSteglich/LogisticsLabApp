/// OSM map with the nodes, the edges of the network and the solution.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../app_state.dart';
import '../model/scenario.dart';
import '../model/solution_analysis.dart';
import '../modules/modules.dart';
import 'theme.dart';

class MapView extends StatefulWidget {
  /// false in tests - they have no network and no cache directory for the tiles
  static bool showTiles = true;

  final AppState state;
  const MapView({super.key, required this.state});

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  final _map = MapController();
  bool _showSolution = true;
  bool _showNetwork = true;
  bool _showLabels = true;

  // edge under the mouse - index in the edges of the network or in the connections of the solution
  final _edgeHit = LayerHitNotifier<int>(null);
  final _flowHit = LayerHitNotifier<int>(null);
  bool _ready = false;
  int _fitted = -1; // AppState.geometry of the last fit
  Timer? _fitTimer;

  AppState get s => widget.state;

  @override
  void dispose() {
    _edgeHit.dispose();
    _flowHit.dispose();
    _fitTimer?.cancel();
    super.dispose();
  }

  /// shows all nodes - after opening a file and whenever nodes or their coordinates change
  void _fitAll() {
    _fitted = s.geometry;
    final points = [for (final n in s.scenario.nodes) n.position];
    if (!_ready || points.isEmpty || !mounted) return;
    _map.fitCamera(CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(56), maxZoom: 14));
  }

  void _scheduleFit() {
    if (s.geometry == _fitted) return;
    _fitTimer?.cancel();
    // a new file at once, typed coordinates only after a short pause - the map does not jump with every key
    _fitTimer = Timer(s.dirty ? const Duration(milliseconds: 600) : Duration.zero, _fitAll);
  }

  SolutionAnalysis? _analysis;

  @override
  Widget build(BuildContext context) {
    final nodes = s.scenario.nodes;
    _analysis = _showSolution ? s.analysis : null;
    _scheduleFit();
    return Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: const LatLng(52.4, 13.4),
            initialZoom: 8,
            onMapReady: () {
              _ready = true;
              _fitAll();
            },
            backgroundColor: Ui.mapBackground,
            onTap: (_, p) => s.tapMap(p),
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
          ),
          children: [
            if (MapView.showTiles)
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'de.th-wildau.logisticslab',
              ),
            if (_showNetwork)
              _hitLayer(
                PolylineLayer<int>(polylines: _networkLines(), hitNotifier: _edgeHit, minimumHitbox: 12),
                _edgeHit,
                (i) => s.selectEdge(i, showTab: true),
              ),
            if (_showSolution)
              _hitLayer(
                PolylineLayer<int>(polylines: _solutionLines(), hitNotifier: _flowHit, minimumHitbox: 12),
                _flowHit,
                (i) => s.selectFlow(i, showTab: true),
              ),
            if (_showLabels) _LabelLayer(labels: _labels(), obstacles: [for (final n in nodes) n.position]),
            MarkerLayer(markers: [for (final n in nodes) _symbol(n)], rotate: false),
            RichAttributionWidget(
              alignment: AttributionAlignment.bottomLeft,
              attributions: [TextSourceAttribution('OpenStreetMap contributors')],
            ),
          ],
        ),
        Positioned(
          top: 12,
          left: 12,
          right: 220,
          child: Align(alignment: Alignment.topLeft, child: _tools()),
        ),
        _hoverCard(),
        Positioned(top: 12, right: 12, child: _layers()),
        Positioned(bottom: 36, right: 12, child: _zoom()),
      ],
    );
  }

  /// hint while a position or an edge is set on the map, else the button "draw edge" (with a network)
  Widget _tools() {
    final t = s.strings;
    final hint = s.placing
        ? t('ui.node.placeHint')
        : s.drawingEdge
        ? t(s.edgeStart == null ? 'ui.edge.drawStart' : 'ui.edge.drawEnd')
        : null;
    if (hint == null) {
      if (s.network == null) return const SizedBox.shrink();
      return OutlinedButton.icon(
        style: OutlinedButton.styleFrom(backgroundColor: Ui.surface),
        icon: const Icon(Icons.timeline, size: 16),
        label: Text(t('ui.edge.draw')),
        onPressed: () => s.setDrawingEdge(true),
      );
    }
    return _panel(
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(s.placing ? Icons.ads_click : Icons.timeline, size: 18, color: Ui.accent),
          const SizedBox(width: 8),
          Flexible(child: Text(hint, style: const TextStyle(fontSize: 13))),
          const SizedBox(width: 4),
          IconButton(
            tooltip: t('ui.cancel'),
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => s.placing ? s.setPlacing(false) : s.setDrawingEdge(false),
          ),
        ],
      ),
    );
  }

  //*********** layers ************

  List<Polyline<int>> _networkLines() {
    final net = s.network;
    if (net == null) return const [];
    final edges = net.edges;
    // the selected edge last - on top
    final order = [
      for (var i = 0; i < edges.length; i++)
        if (i != s.selectedEdge) i,
      ?s.edge == null ? null : s.selectedEdge,
    ];
    return [
      for (final i in order)
        if (s.scenario.node(edges[i].from) case final a?)
          if (s.scenario.node(edges[i].to) case final b?)
            i == s.selectedEdge
                ? Polyline(
                    hitValue: i,
                    points: s.edgePoints(a.position, b.position),
                    color: Ui.accent,
                    strokeWidth: 5,
                    strokeCap: StrokeCap.round,
                    strokeJoin: StrokeJoin.round,
                  )
                : Polyline(
                    // solid - dashes of overlapping edges merge into solid lines; light grey beside the solution
                    hitValue: i,
                    points: s.edgePoints(a.position, b.position),
                    color: Ui.network,
                    strokeWidth: 3.5,
                    borderColor: Colors.white,
                    borderStrokeWidth: 1.5,
                    strokeCap: StrokeCap.round,
                    strokeJoin: StrokeJoin.round,
                  ),
    ];
  }

  /// connections of the solution - the selected one last, so that it is drawn on top
  List<_Flow> _flows() {
    final res = s.solution?.results;
    final list = res?['assignments'] as List?;
    if (list == null) return const [];
    final flows = [
      for (final (i, a) in list.cast<Map<String, dynamic>>().indexed)
        if (s.scenario.node(a['from'] as String) case final from?)
          if (s.scenario.node(a['to'] as String) case final to?)
            (
              index: i,
              points: s.edgePoints(from.position, to.position),
              flow: a['flow'] as num,
              selected: i == s.selectedFlow,
            ),
    ];
    return [...flows.where((f) => !f.selected), ...flows.where((f) => f.selected)];
  }

  List<Polyline<int>> _solutionLines() {
    final stale = s.solutionIsStale;
    return [
      for (final f in _flows())
        Polyline(
          hitValue: f.index,
          points: f.points,
          // a stale solution pale blue, the network light grey - all solid, dashes merge where lines overlap
          color: f.selected ? Ui.highlight : (stale ? Ui.accent.withValues(alpha: 0.4) : Ui.accent),
          strokeWidth: f.selected ? 6 : 3.5,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
        ),
    ];
  }

  /// labels of the map in the order of their priority - those that would overlap are left out (_LabelLayer):
  /// the selected node, the selected connection, the quantities of the solution, the nodes of the problem, the rest
  List<_Label> _labels() {
    final nodes = s.scenario.nodes;
    final selected = nodes.where((n) => n.id == s.selectedNode);
    final flows = _showSolution ? _flows() : const <_Flow>[];
    _Label flowLabel(_Flow f) => _Label(
      f.points[f.points.length ~/ 2],
      s.strings.number(f.flow),
      const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, fontFeatures: Ui.tabular),
      centered: true,
      color: f.selected ? Ui.highlight : Ui.accentDark,
      border: f.selected ? Ui.highlight : (s.solutionIsStale ? Ui.textSecondary : Ui.accent),
      borderWidth: f.selected ? 2 : 1,
    );
    _Label nodeLabel(Node n) => _Label(
      n.position,
      n.name,
      const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      color: s.isRelevant(n) ? Ui.text : Ui.textSecondary,
    );
    return [
      for (final n in selected) nodeLabel(n),
      for (final f in flows.where((f) => f.selected)) flowLabel(f),
      for (final f in flows.where((f) => !f.selected)) flowLabel(f),
      for (final n in nodes.where((n) => n.id != s.selectedNode && s.isRelevant(n))) nodeLabel(n),
      for (final n in nodes.where((n) => n.id != s.selectedNode && !s.isRelevant(n))) nodeLabel(n),
    ];
  }

  Marker _symbol(Node n) {
    // the start of the edge being drawn is marked like the selection
    final selected = s.drawingEdge ? n.id == s.edgeStart : n.id == s.selectedNode;
    // shape by the roles in the problem - a depot is no supplier of a tpp
    final roles = [
      for (final r in n.roles)
        if (s.problemRoles.contains(r)) r,
    ];
    final relevant = s.isRelevant(n);
    final color = relevant ? Ui.text : Ui.pale;
    // with a solution: how far the supply is shipped / the demand is met
    final use = _analysis?.use(n.id);
    // suppliers blue, customers green - pale without a role in the problem
    final (fill, line) = relevant
        ? Ui.roleColors(roles.contains('customer') ? 'customer' : 'supplier')
        : (Ui.pale, Ui.pale);
    final Widget shape;
    if (roles.contains('supplier') || roles.contains('depot')) {
      shape = use == null
          ? Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(2),
                border: Border.all(color: line, width: 1.5),
              ),
            )
          // level from the bottom - full: everything shipped, empty: not used
          : Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: Ui.surface,
                borderRadius: BorderRadius.circular(2),
                border: Border.all(color: use.unused ? Ui.pale : line, width: 2),
              ),
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: use.share ?? 1,
                widthFactor: 1,
                child: ColoredBox(color: fill),
              ),
            );
    } else if (roles.contains('customer')) {
      shape = use == null
          ? Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: Ui.surface,
                shape: BoxShape.circle,
                border: Border.all(color: fill, width: 3.5),
              ),
            )
          // pie of the demand met - an orange ring if it is not met completely
          : CustomPaint(
              size: const Size(18, 18),
              painter: _PiePainter(
                share: use.share ?? 1,
                fill: fill,
                ring: use.notFull ? Ui.warning : line,
                ringWidth: use.notFull ? 3 : 2,
              ),
            );
    } else {
      shape = Transform.rotate(
        angle: 0.785,
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: Ui.mapBackground,
            border: Border.all(color: color, width: 3),
          ),
        ),
      );
    }
    return Marker(
      point: n.position,
      width: Ui.minTarget,
      height: Ui.minTarget,
      child: Semantics(
        button: true,
        selected: selected,
        label: n.name,
        child: Tooltip(
          message: use == null ? n.name : '${n.name}\n${_useInfo(use)}',
          waitDuration: const Duration(milliseconds: 300),
          child: GestureDetector(
            onTap: () => s.tapNode(n.id),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: selected
                      ? BoxDecoration(
                          border: Border.all(color: Ui.accent, width: 3),
                          borderRadius: BorderRadius.circular(6),
                        )
                      : null,
                  child: use != null && use.multiple && !use.sends
                      // served by several suppliers: their number
                      ? Stack(
                          clipBehavior: Clip.none,
                          children: [
                            shape,
                            Positioned(right: -9, top: -9, child: _badge(use.partners.length)),
                          ],
                        )
                      : shape,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _badge(int n) => Container(
    width: 15,
    height: 15,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Ui.accent,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 1.5),
    ),
    child: Text(
      '$n',
      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white, height: 1),
    ),
  );

  /// e.g. "demand 120 · received 75 (63 %) · from Werk Ludwigsfelde 75"
  String _useInfo(NodeUse u) {
    final t = s.strings;
    final target = u.target == null ? '' : '${t(u.sends ? 'field.supply' : 'field.demand')} ${t.number(u.target!)} · ';
    final share = u.share == null ? '' : ' (${t.number(u.share! * 100, decimals: 0)} %)';
    final partners = u.partners.map((p) => '${_name(p.$1)} ${t.number(p.$2)}').join(', ');
    return '$target${t(u.sends ? 'ui.sol.shipped' : 'ui.sol.received')} ${t.number(u.actual)}$share'
        '${partners.isEmpty ? '' : ' · ${t(u.sends ? 'ui.sol.toPartners' : 'ui.sol.fromPartners')} $partners'}';
  }

  //*********** edges under the mouse ************

  /// layer whose lines react to the mouse: the pointer becomes a hand, a tap selects the line
  Widget _hitLayer(Widget layer, LayerHitNotifier<int> hit, void Function(int) select) => MouseRegion(
    cursor: SystemMouseCursors.click,
    hitTestBehavior: HitTestBehavior.deferToChild, // only over a line - the map stays movable
    onExit: (_) => hit.value = null,
    child: GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onTap: () {
        final h = hit.value;
        if (h != null && h.hitValues.isNotEmpty) select(h.hitValues.first);
      },
      child: layer,
    ),
  );

  /// card at the mouse with the line under it - a connection of the solution has priority over an edge
  Widget _hoverCard() => ValueListenableBuilder(
    valueListenable: _flowHit,
    builder: (context, flowHit, _) => ValueListenableBuilder(
      valueListenable: _edgeHit,
      builder: (context, edgeHit, _) {
        final hit = flowHit ?? edgeHit;
        if (hit == null || hit.hitValues.isEmpty) return const SizedBox.shrink();
        final lines = flowHit != null ? _flowInfo(hit.hitValues.first) : _edgeInfo(hit.hitValues.first);
        if (lines == null) return const SizedBox.shrink();
        return Positioned(
          left: hit.point.dx + 14,
          top: hit.point.dy + 14,
          child: IgnorePointer(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 320),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Ui.surface,
                borderRadius: BorderRadius.circular(Ui.radius),
                border: Border.all(color: Ui.border),
                boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 8, offset: Offset(0, 2))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(lines.$1, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  if (lines.$2.isNotEmpty)
                    Text(
                      lines.$2,
                      style: const TextStyle(fontSize: 12, color: Ui.textMuted, fontFeatures: Ui.tabular),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );

  String _name(String id) => s.scenario.node(id)?.name ?? id;

  /// title and values of a connection of the solution
  (String, String)? _flowInfo(int i) {
    final list = s.solution?.results?['assignments'] as List?;
    if (list == null || i >= list.length) return null;
    final a = list[i] as Map<String, dynamic>;
    final t = s.strings;
    final flow = a['flow'] as num, rate = a['rate'] as num?;
    return (
      '${_name('${a['from']}')} → ${_name('${a['to']}')}',
      [
        '${t('result.flow')} ${t.number(flow)}',
        if (rate != null) '${t('result.rate')} ${t.fixed(rate, 2)}',
        if (rate != null) '${t('ui.sol.costs')} ${t.fixed(flow * rate, 2)}',
      ].join(' · '),
    );
  }

  /// title and values of an edge of the network - with the quantity of the solution if it is used
  (String, String)? _edgeInfo(int i) {
    final net = s.network;
    if (net == null || i >= net.edges.length) return null;
    final e = net.edges[i];
    final t = s.strings;
    String value(Object? v) => v == null ? '–' : (v == 'M' ? '∞' : (v is num ? t.number(v) : '$v'));
    final flows = (s.solution?.results?['assignments'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final used = flows.where(
      (a) => (a['from'] == e.from && a['to'] == e.to) || (!net.directed && a['from'] == e.to && a['to'] == e.from),
    );
    return (
      '${_name(e.from)} ${net.directed ? '→' : '↔'} ${_name(e.to)}',
      [
        for (final f in s.spec?.edgeFields ?? const <FieldSpec>[]) '${t(f.label)} ${value(e[f.key])}',
        if (used.isNotEmpty) '${t('result.flow')} ${t.number(used.first['flow'] as num)}',
      ].join(' · '),
    );
  }

  //*********** controls ************

  Widget _panel(Widget child) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: Ui.surface,
      border: Border.all(color: Ui.border),
      borderRadius: BorderRadius.circular(Ui.radius),
    ),
    child: child,
  );

  Widget _layers() {
    final t = s.strings;
    Widget check(String label, bool v, ValueChanged<bool> on) => InkWell(
      onTap: () => on(!v),
      child: SizedBox(
        height: 36,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(value: v, onChanged: (x) => on(x ?? false), visualDensity: VisualDensity.compact),
            Text(label, style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
    return _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(t('ui.layers').toUpperCase(), style: Ui.sectionLabel),
          check(t('ui.layer.solution'), _showSolution, (v) => setState(() => _showSolution = v)),
          check(t('ui.layer.labels'), _showLabels, (v) => setState(() => _showLabels = v)),
          if (s.problem?.network != null)
            check(t('ui.layer.network'), _showNetwork, (v) => setState(() => _showNetwork = v)),
          const SizedBox(height: 4),
          // colours of the roles of the problem
          for (final role in s.problemRoles.where((r) => r == 'supplier' || r == 'customer'))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 22,
                    child: Center(
                      child: Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          color: Ui.roleColors(role).$1,
                          shape: role == 'customer' ? BoxShape.circle : BoxShape.rectangle,
                          borderRadius: role == 'customer' ? null : BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(t('role.$role.plural'), style: Ui.small),
                ],
              ),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomPaint(size: const Size(22, 10), painter: _EdgeIcon(s.scenario.usesRoads)),
              const SizedBox(width: 6),
              Text(t(s.scenario.usesRoads ? 'ui.edges.osm' : 'ui.edges.beeline'), style: Ui.small),
            ],
          ),
          if (s.scenario.usesRoads && s.routesLoading > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 6),
                  Text(t('ui.routes.loading', {'n': s.routesLoading}), style: Ui.small),
                ],
              ),
            ),
          if (s.scenario.usesRoads && s.routesMissing > 0)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t('ui.routes.missing', {'n': s.routesMissing}),
                  style: const TextStyle(fontSize: 12, color: Ui.warning),
                ),
                TextButton(onPressed: s.retryRoutes, child: Text(t('ui.routes.retry'))),
              ],
            ),
        ],
      ),
    );
  }

  Widget _zoom() {
    void zoom(double d) => _map.move(_map.camera.center, _map.camera.zoom + d);
    return Container(
      decoration: BoxDecoration(
        color: Ui.surface,
        border: Border.all(color: Ui.border),
        borderRadius: BorderRadius.circular(Ui.radius),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(icon: const Icon(Icons.add), onPressed: () => zoom(1)),
          const SizedBox(width: Ui.minTarget, child: Divider()),
          IconButton(icon: const Icon(Icons.remove), onPressed: () => zoom(-1)),
        ],
      ),
    );
  }
}

/// small line of the legend - bent for roads, straight for the straight line
class _EdgeIcon extends CustomPainter {
  final bool roads;
  _EdgeIcon(this.roads);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Ui.textSecondary
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    if (roads) {
      path
        ..moveTo(1, 7)
        ..lineTo(7, 2)
        ..lineTo(14, 8)
        ..lineTo(21, 3);
    } else {
      path
        ..moveTo(1, 5)
        ..lineTo(21, 5);
    }
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_EdgeIcon old) => old.roads != roads;
}

/// label of the map - the name of a node (right of it) or a quantity of the solution (centred on the connection)
class _Label {
  final LatLng point;
  final String text;
  final TextStyle style;
  final bool centered;
  final Color color;
  final Color? border;
  final double borderWidth;

  const _Label(
    this.point,
    this.text,
    this.style, {
    this.centered = false,
    required this.color,
    this.border,
    this.borderWidth = 1,
  });

  static const _padding = EdgeInsets.symmetric(horizontal: 6, vertical: 2);
  static const _gap = 14.0; // between the node and its name
  static final _sizes = <String, Size>{};

  /// size of the label with its padding and border - measured with the text style the label is shown with
  Size size(TextStyle base, TextScaler scaler) =>
      _sizes.putIfAbsent('${base.fontFamily}|${scaler.scale(10)}|${style.fontSize}|$text', () {
        final p = TextPainter(
          text: TextSpan(text: text, style: base.merge(style)),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
          maxLines: 1,
        )..layout(maxWidth: 220);
        final b = border == null ? 0.0 : 2 * borderWidth;
        return Size(
          (p.width + _padding.horizontal + b).ceilToDouble(),
          (p.height + _padding.vertical + b).ceilToDouble(),
        );
      });

  /// places of the label around its point: a quantity centred, a name right, left, above or below its node
  List<Alignment> get places => centered
      ? const [Alignment.center]
      : const [Alignment.centerRight, Alignment.centerLeft, Alignment.topCenter, Alignment.bottomCenter];

  static const _gapV = 10.0; // between the node and a name above or below it

  /// place on the screen for the point of the label on the screen and one of [places]
  Rect rect(Offset at, Size size, Alignment place) => switch (place) {
    Alignment.centerRight => Rect.fromLTWH(at.dx + _gap, at.dy - size.height / 2, size.width, size.height),
    Alignment.centerLeft => Rect.fromLTWH(at.dx - _gap - size.width, at.dy - size.height / 2, size.width, size.height),
    Alignment.topCenter => Rect.fromLTWH(at.dx - size.width / 2, at.dy - _gapV - size.height, size.width, size.height),
    Alignment.bottomCenter => Rect.fromLTWH(at.dx - size.width / 2, at.dy + _gapV, size.width, size.height),
    _ => Rect.fromCenter(center: at, width: size.width, height: size.height),
  };

  /// marker for [place] - the alignment of flutter_map puts the whole widget on that side of the point
  Marker marker(Size size, Alignment place) => Marker(
    point: point,
    width: place.x == 0 ? size.width : size.width + _gap,
    height: place.y == 0 ? size.height : size.height + _gapV,
    alignment: place,
    child: IgnorePointer(
      child: Align(
        alignment: place,
        child: Container(
          width: size.width,
          height: size.height,
          alignment: Alignment.center,
          padding: _padding,
          decoration: BoxDecoration(
            color: border == null ? Ui.surface.withValues(alpha: 0.85) : Ui.surface,
            borderRadius: BorderRadius.circular(centered ? 9 : 4),
            border: border == null ? null : Border.all(color: border!, width: borderWidth),
          ),
          child: Text(
            text,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
            style: style.copyWith(color: color),
          ),
        ),
      ),
    ),
  );
}

/// Labels without overlaps: in the order of their priority, a label is shown only if it does not overlap a label
/// shown before or a node symbol - computed again with every move and zoom of the map.
class _LabelLayer extends StatelessWidget {
  final List<_Label> labels;
  final List<LatLng> obstacles; // the node symbols
  const _LabelLayer({required this.labels, required this.obstacles});

  static const _symbol = 9.0; // half the size of a node symbol

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final screen = Offset.zero & camera.nonRotatedSize;
    final symbols = [
      for (final p in obstacles)
        Rect.fromCenter(center: camera.latLngToScreenOffset(p), width: 2 * _symbol, height: 2 * _symbol),
    ];
    final base = DefaultTextStyle.of(context).style;
    final scaler = MediaQuery.textScalerOf(context);
    final placed = <Rect>[];
    final shown = <Marker>[];
    for (final l in labels) {
      final size = l.size(base, scaler);
      final at = camera.latLngToScreenOffset(l.point);
      // the first free place around the point
      for (final place in l.places) {
        final r = l.rect(at, size, place);
        if (!screen.overlaps(r)) break; // outside - takes no room
        final area = r.deflate(1);
        if (placed.any(area.overlaps) || symbols.any(area.overlaps)) continue;
        placed.add(r);
        shown.add(l.marker(size, place));
        break;
      }
    }
    return MarkerLayer(markers: shown, rotate: false);
  }
}

typedef _Flow = ({int index, List<LatLng> points, num flow, bool selected});

/// pie of a share inside a ring - a customer and the part of its demand that is met
class _PiePainter extends CustomPainter {
  final double share;
  final Color fill;
  final Color ring;
  final double ringWidth;
  _PiePainter({required this.share, required this.fill, required this.ring, required this.ringWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawCircle(c, r, Paint()..color = Ui.surface);
    if (share > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r - ringWidth / 2),
        -1.5708, // from 12 o'clock
        share * 6.28319,
        true,
        Paint()..color = fill,
      );
    }
    canvas.drawCircle(
      c,
      r - ringWidth / 2,
      Paint()
        ..color = ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringWidth,
    );
  }

  @override
  bool shouldRepaint(_PiePainter old) =>
      old.share != share || old.fill != fill || old.ring != ring || old.ringWidth != ringWidth;
}
