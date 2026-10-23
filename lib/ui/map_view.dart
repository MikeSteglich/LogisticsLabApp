/// OSM map with the nodes, the edges of the network and the solution.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../app_state.dart';
import '../model/scenario.dart';
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
  bool _ready = false;
  int _fitted = -1; // AppState.geometry of the last fit
  Timer? _fitTimer;

  AppState get s => widget.state;

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    final nodes = s.scenario.nodes;
    final t = s.strings;
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
            if (_showNetwork) PolylineLayer(polylines: _networkLines()),
            if (_showSolution) PolylineLayer(polylines: _solutionLines()),
            if (_showSolution) MarkerLayer(markers: _flowLabels(), rotate: false),
            MarkerLayer(markers: [for (final n in nodes) _label(n)], rotate: false),
            MarkerLayer(markers: [for (final n in nodes) _symbol(n)], rotate: false),
            RichAttributionWidget(
              alignment: AttributionAlignment.bottomLeft,
              attributions: [TextSourceAttribution('OpenStreetMap contributors')],
            ),
          ],
        ),
        if (s.placing)
          Positioned(
            top: 12,
            left: 12,
            right: 220,
            child: Align(
              alignment: Alignment.topLeft,
              child: _panel(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.ads_click, size: 18, color: Ui.accent),
                    const SizedBox(width: 8),
                    Flexible(child: Text(t('ui.node.placeHint'), style: const TextStyle(fontSize: 13))),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: t('ui.cancel'),
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => s.setPlacing(false),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Positioned(top: 12, right: 12, child: _layers()),
        Positioned(bottom: 36, right: 12, child: _zoom()),
      ],
    );
  }

  //*********** layers ************

  List<Polyline> _networkLines() {
    final net = s.problem?.network == null ? null : s.scenario.networks[s.problem!.network];
    if (net == null) return const [];
    return [
      for (final e in net.edges)
        if (s.scenario.node(e.from) case final a?)
          if (s.scenario.node(e.to) case final b?)
            Polyline(
              points: s.edgePoints(a.position, b.position),
              color: Ui.textSecondary.withValues(alpha: 0.7),
              strokeWidth: 2,
              pattern: const StrokePattern.dotted(),
            ),
    ];
  }

  List<({List<LatLng> points, num flow})> _flows() {
    final res = s.solution?.results;
    final list = res?['assignments'] as List?;
    if (list == null) return const [];
    return [
      for (final a in list.cast<Map<String, dynamic>>())
        if (s.scenario.node(a['from'] as String) case final from?)
          if (s.scenario.node(a['to'] as String) case final to?)
            (points: s.edgePoints(from.position, to.position), flow: a['flow'] as num),
    ];
  }

  List<Polyline> _solutionLines() {
    final stale = s.solutionIsStale;
    return [
      for (final f in _flows())
        Polyline(
          points: f.points,
          color: stale ? Ui.textSecondary : Ui.accent,
          strokeWidth: 3.5,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
          pattern: stale ? StrokePattern.dashed(segments: const [8, 6]) : const StrokePattern.solid(),
        ),
    ];
  }

  List<Marker> _flowLabels() => [
    for (final f in _flows())
      Marker(
        point: f.points[f.points.length ~/ 2],
        width: 64,
        height: 22,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: Ui.surface,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: s.solutionIsStale ? Ui.textSecondary : Ui.accent),
            ),
            child: Text(
              s.strings.number(f.flow),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Ui.accentDark,
                fontFeatures: Ui.tabular,
              ),
            ),
          ),
        ),
      ),
  ];

  Marker _symbol(Node n) {
    final selected = n.id == s.selectedNode;
    // shape by the roles in the problem - a depot is no supplier of a tpp
    final roles = [
      for (final r in n.roles)
        if (s.problemRoles.contains(r)) r,
    ];
    final color = s.isRelevant(n) ? Ui.text : Ui.pale;
    final Widget shape;
    if (roles.contains('supplier') || roles.contains('depot')) {
      shape = Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
      );
    } else if (roles.contains('customer')) {
      shape = Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: Ui.surface,
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 3),
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
        child: GestureDetector(
          onTap: () => s.selectNode(n.id),
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
                child: shape,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Marker _label(Node n) => Marker(
    point: n.position,
    width: 180,
    height: 22,
    alignment: Alignment.centerRight, // the label starts at the node
    child: IgnorePointer(
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(left: 16),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(color: Ui.surface.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(4)),
          child: Text(
            n.name,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: s.isRelevant(n) ? Ui.text : Ui.textSecondary,
            ),
          ),
        ),
      ),
    ),
  );

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
          if (s.problem?.network != null)
            check(t('ui.layer.network'), _showNetwork, (v) => setState(() => _showNetwork = v)),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomPaint(size: const Size(22, 10), painter: _EdgeIcon(s.scenario.usesRoads)),
              const SizedBox(width: 6),
              Text(t(s.scenario.usesRoads ? 'ui.edges.osm' : 'ui.edges.beeline'), style: Ui.small),
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
