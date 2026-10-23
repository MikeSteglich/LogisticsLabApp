/// How the nodes are served in a solution: target (supply, demand), actual quantity, share and the partners.
///
/// Built from the ModuleSpec: the roles of the problem with their main field (tpp: supply of the sources, demand
/// of the destinations), the quantity of a node in the solution (`results.nodes.<id>.flow`) and the connections
/// (`results.assignments` from -> to). The first role sends, the second receives.
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

  NodeUse(this.node, this.role, this.sends, this.target, this.actual, this.partners);

  static const _eps = 1e-6;

  /// actual / target - null without target
  double? get share => target == null || target! <= 0 ? null : (actual / target!).clamp(0, 1).toDouble();

  bool get unused => actual <= _eps;

  /// supply not shipped completely or demand not met completely
  bool get notFull => target != null && actual < target! - _eps;

  num get missing => target == null ? 0 : (target! - actual).clamp(0, double.infinity);

  bool get multiple => partners.length > 1;
}

class SolutionAnalysis {
  final List<NodeUse> uses;
  final List<String> roles; // the roles of the problem in their order (tpp: supplier, customer)

  SolutionAnalysis(this.uses, this.roles);

  /// null if the problem has no roles with targets or the solution no quantities of the nodes
  static SolutionAnalysis? of(
    Scenario scenario,
    ModuleSpec? spec,
    Map<String, dynamic> parameters,
    Map<String, dynamic>? results,
  ) {
    final nodeResults = (results?['nodes'] as Map?)?.cast<String, dynamic>();
    if (spec == null || nodeResults == null || spec.roles.length < 2) return null;
    final assignments = ((results?['assignments'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final roles = [for (final r in spec.roles) spec.nodeRole(r, parameters)];
    final uses = <NodeUse>[];
    for (final (i, r) in spec.roles.indexed) {
      final role = roles[i];
      final sends = i == 0;
      for (final n in scenario.nodes) {
        if (!n.active || !n.roles.contains(role)) continue;
        final target = r.mainField == null ? null : n[r.mainField!.key];
        final actual = ((nodeResults[n.id] as Map?)?['flow'] as num?) ?? 0;
        final partners = [
          for (final a in assignments)
            if ((sends ? a['from'] : a['to']) == n.id) ('${sends ? a['to'] : a['from']}', a['flow'] as num),
        ];
        uses.add(NodeUse(n, role, sends, target is num ? target : null, actual, partners));
      }
    }
    return SolutionAnalysis(uses, roles);
  }

  NodeUse? use(String id) => uses.where((u) => u.node.id == id).firstOrNull;

  Iterable<NodeUse> ofRole(String role) => uses.where((u) => u.role == role);

  /// supply not shipped (first role) or demand not met (second role)
  num missing(String role) => ofRole(role).fold<num>(0, (sum, u) => sum + u.missing);

  /// receivers served by more than one sender (tpp: customers with several suppliers)
  int get multipleReceivers => uses.where((u) => !u.sends && u.multiple).length;
}
