/// How the nodes are served in a solution: target (supply, demand), actual quantity, share and the partners.
///
/// Built from the ModuleSpec: the roles of the problem with their main field (tpp: supply of the sources, demand
/// of the destinations), the quantity of a node in the solution (`results.nodes.<id>.flow`) and the connections
/// (`results.assignments` from -> to). The first role sends, the second receives. The other nodes of the network
/// of a network flow (transshipment nodes, warehouses) pass quantities through - with the utilization of their
/// capacity.
library;

import '../modules/modules.dart';
import 'scenario.dart';

/// one node in the solution
class NodeUse {
  final Node node;
  final String role; // node role in the problem, e.g. supplier
  final bool sends; // first role (tpp: supplier) - else it receives
  final num? target; // supply or demand
  final num actual; // quantity in the solution
  final List<(String, num)> partners; // other end and quantity of each connection
  final bool through; // passes quantities through: transshipment node, warehouse - actual is its throughput
  final num? capacity; // capacity of the node (maxCap, capacity of a warehouse)
  final num? utilization; // throughput / capacity

  NodeUse(
    this.node,
    this.role,
    this.sends,
    this.target,
    this.actual,
    this.partners, {
    this.through = false,
    this.capacity,
    this.utilization,
  });

  static const _eps = 1e-6;

  /// actual / target - null without target
  double? get share => target == null || target! <= 0 ? null : (actual / target!).clamp(0, 1).toDouble();

  bool get unused => actual <= _eps;

  /// supply not shipped completely or demand not met completely
  bool get notFull => target != null && actual < target! - _eps;

  num get missing => target == null ? 0 : (target! - actual).clamp(0, double.infinity);

  bool get multiple => partners.length > 1;

  /// receives from several senders (tpp: customer with several suppliers)
  bool get multipleReceiver => !sends && !through && multiple;

  /// capacity used completely - a bottleneck
  bool get full => utilization != null && utilization! >= 1 - _eps;
}

class SolutionAnalysis {
  final List<NodeUse> uses;
  final List<String> roles; // the roles of the problem in their order (tpp: supplier, customer)

  SolutionAnalysis(this.uses, this.roles);

  /// null if the problem has no roles with targets or the solution no quantities of the nodes - networkNodes: the
  /// nodes of the network of a network flow, those without a rated role pass quantities through
  /// The first role of the problem sends (tpp, flows: suppliers), the last receives (customers) - roles between
  /// them (warehouses of a multi-stage WLP) are not rated. Connections: results.assignments (tpp) or results.edges
  /// (network flows); values per commodity are added up.
  static SolutionAnalysis? of(
    Scenario scenario,
    ModuleSpec? spec,
    Map<String, dynamic> parameters,
    Map<String, dynamic>? results, {
    Iterable<String> networkNodes = const [],
  }) {
    if (spec == null || results == null) return null;
    final nodeResults = (results['nodes'] as Map?)?.cast<String, dynamic>() ?? const {};
    if (results['nodes'] == null && networkNodes.isEmpty) return null;
    if (spec.roles.length < 2 && networkNodes.isEmpty) return null;
    final connections = connectionsOf(results);
    final rated = spec.roles.length < 2 ? const <RoleSpec>[] : [spec.roles.first, spec.roles.last];
    final roles = [for (final r in rated) spec.nodeRole(r, parameters)];
    final uses = <NodeUse>[];
    for (final (i, r) in rated.indexed) {
      final role = roles[i];
      final sends = i == 0;
      for (final n in scenario.nodes) {
        if (!n.active || !n.roles.contains(role)) continue;
        final target = r.mainField == null ? null : total(n[r.mainField!.key]);
        final res = (nodeResults[n.id] as Map?)?.cast<String, dynamic>() ?? const {};
        // the core gives unused supply and unmet demand of network flows - else the quantity through the node
        final missing = total(res[sends ? 'unusedSupply' : 'unmetDemand']);
        final actual = target != null && missing != null ? target - missing : (total(res['flow']) ?? 0);
        final partners = [
          for (final a in connections)
            if ((sends ? a['from'] : a['to']) == n.id) ('${sends ? a['to'] : a['from']}', a['flow'] as num),
        ];
        uses.add(
          NodeUse(
            n,
            role,
            sends,
            target,
            actual,
            partners,
            capacity: res['capacity'] as num?,
            utilization: res['utilization'] as num?,
          ),
        );
      }
    }
    // the other nodes of the network: throughput (the core gives it with node capacities, else the inflow)
    final rolesOfSpec = {for (final r in spec.roles) spec.nodeRole(r, parameters)};
    for (final id in networkNodes) {
      if (uses.any((u) => u.node.id == id)) continue;
      final n = scenario.node(id);
      if (n == null || !n.active) continue;
      final res = (nodeResults[id] as Map?)?.cast<String, dynamic>() ?? const {};
      final inflow = connections.where((a) => a['to'] == id).fold<num>(0, (sum, a) => sum + (a['flow'] as num));
      final role = n.roles.firstWhere(rolesOfSpec.contains, orElse: () => 'transit');
      uses.add(
        NodeUse(
          n,
          role,
          false,
          null,
          total(res['flow']) ?? inflow,
          [
            for (final a in connections)
              if (a['from'] == id || a['to'] == id) ('${a['from'] == id ? a['to'] : a['from']}', a['flow'] as num),
          ],
          through: true,
          capacity: res['capacity'] as num?,
          utilization: res['utilization'] as num?,
        ),
      );
    }
    return SolutionAnalysis(uses, roles);
  }

  /// a number or the sum of the values per commodity - null if there is none
  static num? total(Object? v) => v is num
      ? v
      : v is Map
      ? v.values.whereType<num>().fold<num>(0, (a, b) => a + b)
      : null;

  /// connections of a solution: from -> to with quantity (tpp: assignments, network flows: edges)
  static List<Map<String, dynamic>> connectionsOf(Map<String, dynamic>? results) =>
      ((results?['assignments'] ?? results?['edges']) as List? ?? const []).cast<Map<String, dynamic>>();

  NodeUse? use(String id) => uses.where((u) => u.node.id == id).firstOrNull;

  Iterable<NodeUse> ofRole(String role) => uses.where((u) => u.role == role);

  /// supply not shipped (first role) or demand not met (second role)
  num missing(String role) => ofRole(role).fold<num>(0, (sum, u) => sum + u.missing);

  /// receivers served by more than one sender (tpp: customers with several suppliers)
  int get multipleReceivers => uses.where((u) => u.multipleReceiver).length;

  /// nodes passing quantities through (transshipment nodes, warehouses)
  Iterable<NodeUse> get through => uses.where((u) => u.through);
}
