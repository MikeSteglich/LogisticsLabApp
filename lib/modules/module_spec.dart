/// Description of the problem types for a common UI - sketch.
///
/// The UI does not have its own screen per problem type. It builds the node mask, the parameter form, the edge mask
/// and the result tables from a ModuleSpec. The keys are the names of the llab format (docs/dateiformate.md):
/// node attributes, problem parameters and the result fields of the llsol file.
///
/// A ModuleSpec contains no texts, only message keys - the texts are in `assets/i18n/<language>.json`:
///   `module.<type>`, `module.<type>.description`    label and description of the problem type
///   `group.<group>`                               group of the problem chooser
///   `role.<node role>`                            e.g. role.supplier
///   `field.<key>`, `field.<key>.help`               fields of the masks - labelKey overrides `field.<key>`
///   `choice.<field key>.<value>`                  values of a choice field
///   `result.<key>`                                columns of the result tables
///   `error.<kind>`                                messages of the checks with {label}, {min}, {value}
library;

enum ModuleGroup { transport, location, routing, network }

enum FieldKind {
  number,
  unlimited, // number or 'M' (no limit) - shown as empty field with the hint "unlimited"
  integer,
  boolean,
  choice,
  text,
  node, // id of a node of the scenario, e.g. source of a max flow
  commodities, // a number per commodity of the scenario, e.g. supplies of a multi-commodity flow
  modes, // modes allowed at an edge (multimodal) - null: all modes of the scenario
  timeWindow, // [earliest, latest] in the time unit of the scenario - latest null: open (vrp)
}

/// Text to be shown in the language of the UI - key with arguments, e.g. error.min with {label} and {min}.
class Message {
  final String key;
  final Map<String, Object> args;
  const Message(this.key, [this.args = const {}]);

  @override
  String toString() => args.isEmpty ? key : '$key $args';
}

/// Visibility of a field depending on the current parameters of the problem, e.g. minSupply only with useSupplyRanges.
typedef FieldCondition = bool Function(Map<String, dynamic> parameters);

class FieldSpec {
  final String key;
  final FieldKind kind;
  final String? labelKey; // default field.<key>
  final String? unit;
  final String? hint; // key of the text in an empty field, e.g. hint.auto
  final num? emptyValue; // the value the core takes for an empty field - shown there (grey), not stored
  final Object? defaultValue;
  final List<String> choices; // values of FieldKind.choice - labels choice.<key>.<value>
  final bool required;
  final num? min;
  final FieldCondition? visibleIf;
  final String? requires; // boolean parameter that switches the field on, e.g. useCapacities
  final String? nodeRole; // FieldKind.node: only nodes with this role, e.g. delivery (pdp)
  final bool computed; // shown, not entered - computed from other nodes, e.g. the delivered amount (pdp)
  // a field of every node (ModuleSpec.nodeFields) not for the nodes of these roles (keys of RoleSpec), e.g. the
  // throughput of a network flow: not for suppliers and customers (their supply and demand limit it)
  final List<String> notForRoles;

  const FieldSpec(
    this.key,
    this.kind, {
    this.labelKey,
    this.unit,
    this.hint,
    this.emptyValue,
    this.defaultValue,
    this.choices = const [],
    this.required = false,
    this.min,
    this.visibleIf,
    this.requires,
    this.nodeRole,
    this.computed = false,
    this.notForRoles = const [],
  });

  String get label => labelKey ?? 'field.$key';
  String get help => '$label.help';
  String choiceLabel(String value) => 'choice.$key.$value';

  bool isVisible(Map<String, dynamic> parameters) =>
      (requires == null || parameters[requires] == true) && (visibleIf?.call(parameters) ?? true);

  /// Message for a wrong value or null - the server checks again, this is only for the mask.
  /// The argument label is the message key of the field, the UI replaces it by its text.
  Message? validate(Object? value) {
    if (value == null || value == '') return required ? Message('error.required', {'label': label}) : null;
    switch (kind) {
      case FieldKind.number || FieldKind.integer || FieldKind.unlimited:
        if (kind == FieldKind.unlimited && value == 'M') return null;
        if (value is! num) return Message('error.number', {'label': label});
        if (kind == FieldKind.integer && value != value.roundToDouble()) {
          return Message('error.integer', {'label': label});
        }
        if (min != null && value < min!) return Message('error.min', {'label': label, 'min': min!});
        return null;
      case FieldKind.boolean:
        return value is bool ? null : Message('error.boolean', {'label': label});
      case FieldKind.choice:
        return choices.contains(value) ? null : Message('error.choice', {'label': label, 'value': value});
      case FieldKind.text || FieldKind.node:
        return value is String ? null : Message('error.text', {'label': label});
      case FieldKind.timeWindow:
        if (value is! List || value.length != 2 || value.any((x) => x != null && x is! num)) {
          return Message('error.number', {'label': label});
        }
        final [a, b] = value;
        if (a is num && b is num && a > b) return Message('error.timeWindow', {'label': label});
        return null;
      case FieldKind.commodities || FieldKind.modes:
        return value is Map ? null : Message('error.text', {'label': label});
    }
  }

  Iterable<String> get messageKeys => [label, for (final c in choices) choiceLabel(c)];
}

/// Role of the nodes in a problem, e.g. sources of a tpp. The problem parameter roles can map it to another node role.
class RoleSpec {
  final String key; // key in parameters.roles, e.g. sources
  final String defaultRole; // node role, e.g. supplier - label role.<defaultRole>
  final List<FieldSpec> nodeFields; // shown in the node mask if the node has this role
  final FieldCondition? visibleIf; // the role is used only with these parameters - e.g. max flow from the suppliers
  final String? main; // key of the main field if it is not required (e.g. an upper bound)

  const RoleSpec(this.key, this.defaultRole, this.nodeFields, {this.visibleIf, this.main});

  String get label => 'role.$defaultRole';

  bool isUsed(Map<String, dynamic> parameters) => visibleIf?.call(parameters) ?? true;

  /// main value of the role, shown in the node list - e.g. supply of the sources of a tpp
  FieldSpec? get mainField =>
      main != null ? nodeFields.firstWhere((f) => f.key == main) : nodeFields.where((f) => f.required).firstOrNull;
}

enum NetworkUse { none, optional, required }

/// Column of a result table - key is the field in the llsol file, label `result.<key>.`
class ResultColumn {
  final String key; // key in results.summary - objVal: the objective value of the results
  final String? unit;
  final String? labelKey; // default result.<key>
  // isDemandWeighted: the label - and the value without a unit (demand x distance)
  final String? weightedLabelKey;
  final String? hideIfSameAs; // left out if its value is the same as that of this column, e.g. objVal
  const ResultColumn(this.key, {this.unit, this.labelKey, this.weightedLabelKey, this.hideIfSameAs});

  String get label => labelKey ?? 'result.$key';
}

/// the distances multiplied by the demands (isDemandWeighted) - its default if not set
bool isDemandWeighted(ModuleSpec spec, Map<String, dynamic> p) =>
    (p['isDemandWeighted'] as bool?) ??
    (spec.parameters.where((f) => f.key == 'isDemandWeighted').firstOrNull?.defaultValue as bool?) ??
    false;

class ModuleSpec {
  final String type; // problem type of the llab file
  final ModuleGroup group;
  final List<RoleSpec> roles;
  final List<FieldSpec> parameters;
  final NetworkUse network;
  final List<FieldSpec> edgeFields; // attributes of the edges used by this problem type
  final bool usesMatrix; // distances, times or costs from OSM (matrixMode)
  final List<ResultColumn> summary;
  final List<ResultColumn> nodeResults;
  final List<ResultColumn> assignments; // rows from -> to, e.g. flows of a tpp
  final List<FieldSpec> nodeFields; // fields of every node of the problem, e.g. node capacities of a network flow
  final bool usesCommodities; // the scenario needs commodities (multicommodity)
  final bool usesModes; // the scenario needs modes of transport (multimodal)
  final bool allNodes; // the problem uses all active nodes, e.g. the tsp
  final bool edgeDirections; // each edge directed or not (tsp, cpp) - else the direction of the network
  final bool usesVehicles; // the scenario needs vehicles (vrp)

  /// key of the summary value the objective function uses - depends on the parameters (e.g. objSense)
  final String? Function(Map<String, dynamic> parameters)? objective;

  const ModuleSpec({
    required this.type,
    required this.group,
    required this.roles,
    required this.parameters,
    this.network = NetworkUse.none,
    this.edgeFields = const [],
    this.usesMatrix = true,
    this.summary = const [],
    this.nodeResults = const [],
    this.assignments = const [],
    this.nodeFields = const [],
    this.usesCommodities = false,
    this.usesModes = false,
    this.allNodes = false,
    this.edgeDirections = false,
    this.usesVehicles = false,
    this.objective,
  });

  String get label => 'module.$type';
  String get description => 'module.$type.description';
  String get groupLabel => 'group.${group.name}';

  /// Parameters of a new problem of this type.
  Map<String, dynamic> defaultParameters() => {
    for (final f in parameters)
      if (f.defaultValue != null) f.key: f.defaultValue,
  };

  /// Roles used with the parameters - e.g. max flow: suppliers and customers only without source and sink.
  List<RoleSpec> activeRoles(Map<String, dynamic> parameters) => [
    for (final r in roles)
      if (r.isUsed(parameters)) r,
  ];

  /// Node role of a role of the problem, e.g. sources -> supplier.
  String nodeRole(RoleSpec role, Map<String, dynamic> parameters) =>
      (parameters['roles'] as Map?)?[role.key] as String? ?? role.defaultRole;

  /// Node roles used by the problem, e.g. supplier and customer for a tpp.
  List<String> problemRoles(Map<String, dynamic> parameters) =>
      {for (final r in activeRoles(parameters)) nodeRole(r, parameters)}.toList();

  /// Fields of the node mask for a node with the given roles - each field only once. values: those of the node - a
  /// field of every node not for its roles is shown if it has a value (old files)
  List<FieldSpec> nodeFieldsFor(
    Iterable<String> nodeRoles,
    Map<String, dynamic> parameters, {
    Map<String, dynamic>? values,
  }) {
    final seen = <String>{};
    return [
      for (final r in activeRoles(parameters))
        if (nodeRoles.contains(nodeRole(r, parameters)))
          for (final f in r.nodeFields)
            if (f.isVisible(parameters) && seen.add(f.key)) f,
      for (final f in nodeFields)
        if (f.isVisible(parameters) &&
            (isForRoles(f, nodeRoles, parameters) || values?[f.key] != null) &&
            seen.add(f.key))
          f,
    ];
  }

  /// a field of every node for a node with these roles - not for the roles of notForRoles
  bool isForRoles(FieldSpec f, Iterable<String> nodeRoles, Map<String, dynamic> parameters) =>
      !activeRoles(parameters).any((r) => f.notForRoles.contains(r.key) && nodeRoles.contains(nodeRole(r, parameters)));

  /// the edge fields the problem uses with its parameters (fixed costs only with useFixedCosts)
  List<FieldSpec> visibleEdgeFields(Map<String, dynamic> parameters) => [
    for (final f in edgeFields)
      if (f.isVisible(parameters)) f,
  ];

  /// Fields of the parameter form - e.g. without minSupply if it does not apply.
  Iterable<FieldSpec> visibleParameters(Map<String, dynamic> values) => parameters.where((f) => f.isVisible(values));

  List<Message> validateParameters(Map<String, dynamic> values) => [
    for (final f in visibleParameters(values))
      if (f.validate(values[f.key] ?? f.defaultValue) case final Message msg) msg,
  ];

  /// All message keys of the module - must be in every language file (bin/i18n_check.dart).
  Set<String> get messageKeys => {
    label,
    description,
    groupLabel,
    for (final r in roles) ...[r.label, for (final f in r.nodeFields) ...f.messageKeys],
    for (final f in [...parameters, ...edgeFields, ...nodeFields]) ...f.messageKeys,
    for (final c in [...summary, ...nodeResults, ...assignments]) c.label,
  };
}

//*************** common fields ************************************

const errorKeys = [
  'error.required',
  'error.number',
  'error.integer',
  'error.min',
  'error.boolean',
  'error.choice',
  'error.text',
];

const objSenseField = FieldSpec(
  'objSense',
  FieldKind.choice,
  defaultValue: 'min',
  choices: ['min', 'max', 'maxflow', 'minimax'],
);

const matrixModeField = FieldSpec('matrixMode', FieldKind.choice, choices: ['distances', 'times', 'costs']);

// the defaults of the core (logisticsLabCore/items.py): SolverOptions - FlowOptions
const solverFields = [
  FieldSpec('maxSolvingTime', FieldKind.number, unit: 's', min: 1, emptyValue: 300),
  FieldSpec('mipGap', FieldKind.number, min: 0, emptyValue: 0.001),
];
const flowSolverFields = [
  FieldSpec('maxSolvingTime', FieldKind.number, unit: 's', min: 1, emptyValue: 60),
  FieldSpec('mipGap', FieldKind.number, min: 0, emptyValue: 0.001),
];

bool isOn(Map<String, dynamic> p, String key) => p[key] == true;
