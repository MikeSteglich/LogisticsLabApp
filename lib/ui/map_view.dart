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
        Positioned(
          top: 12,
          left: 12,
          right: 220,
          child: Align(alignment: Alignment.topLeft, child: _tools()),
        ),
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

  List<Polyline> _networkLines() {
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
                    points: s.edgePoints(a.position, b.position),
                    color: Ui.accent,
                    strokeWidth: 5,
                    strokeCap: StrokeCap.round,
                    strokeJoin: StrokeJoin.round,
                  )
                : Polyline(
                    // solid - dashes of overlapping edges merge into solid lines; light grey beside the solution
                    points: s.edgePoints(a.position, b.position),
                    color: Ui.network,
                    strokeWidth: 3,
                    borderColor: Colors.white,
                    borderStrokeWidth: 1,
                    strokeCap: StrokeCap.round,
                    strokeJoin: StrokeJoin.round,
                  ),
    ];
  }

  /// connections of the solution - the selected one last, so that it is drawn on top
  List<({List<LatLng> points, num flow, bool selected})> _flows() {
    final res = s.solution?.results;
    final list = res?['assignments'] as List?;
    if (list == null) return const [];
    final flows = [
      for (final (i, a) in list.cast<Map<String, dynamic>>().indexed)
        if (s.scenario.node(a['from'] as String) case final from?)
          if (s.scenario.node(a['to'] as String) case final to?)
            (points: s.edgePoints(from.position, to.position), flow: a['flow'] as num, selected: i == s.selectedFlow),
    ];
    return [...flows.where((f) => !f.selected), ...flows.where((f) => f.selected)];
  }

  List<Polyline> _solutionLines() {
    final stale = s.solutionIsStale;
    return [
      for (final f in _flows())
        Polyline(
          points: f.points,
          // a stale solution pale blue, the network light grey - all solid, dashes merge where lines overlap
          color: f.selected ? Ui.highlight : (stale ? Ui.accent.withValues(alpha: 0.4) : Ui.accent),
          strokeWidth: f.selected ? 6 : 3.5,
          strokeCap: StrokeCap.round,
          strokeJoin: StrokeJoin.round,
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
              border: Border.all(
                color: f.selected ? Ui.highlight : (s.solutionIsStale ? Ui.textSecondary : Ui.accent),
                width: f.selected ? 2 : 1,
              ),
            ),
            child: Text(
              s.strings.number(f.flow),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: f.selected ? Ui.highlight : Ui.accentDark,
                fontFeatures: Ui.tabular,
              ),
            ),
          ),
        ),
      ),
  ];

  Marker _symbol(Node n) {
    // the start of the edge being drawn is marked like the selection
    final selected = s.drawingEdge ? n.id == s.edgeStart : n.id == s.selectedNode;
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
