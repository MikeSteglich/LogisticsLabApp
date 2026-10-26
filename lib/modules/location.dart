import 'module_spec.dart';

//*************** discrete location problems ************************************
//
// Candidates for the locations and customers assigned to the open ones - warehouse location (fixed and variable
// costs), p-median (sum of the distances), p-centre (longest distance), set covering (every customer within a
// radius) and maximal covering (as much demand as possible within a radius for a budget).

String? _objVal(Map<String, dynamic> _) => 'objVal';

bool _capacitated(Map<String, dynamic> p) => isOn(p, 'isCapacitated');

/// set covering and maximal covering: the fixed costs of the candidates - maximal covering by default
bool _fixed(Map<String, dynamic> p, {required bool byDefault}) => (p['useFixedCosts'] as bool?) ?? byDefault;

/// candidates: their opening costs and (capacitated) their capacity
RoleSpec _candidates({FieldCondition? withFixedCosts, bool withCapacity = false}) => RoleSpec('sources', 'candidate', [
  FieldSpec('fixedCost', FieldKind.number, unit: '€', min: 0, labelKey: 'field.openingCost', visibleIf: withFixedCosts),
  if (withCapacity)
    const FieldSpec(
      'capacity',
      FieldKind.unlimited,
      min: 0,
      labelKey: 'field.candidateSupply',
      visibleIf: _capacitated,
    ),
  // the list of all nodes: their supply - without capacities (coverings) their operating costs
], main: withCapacity ? 'capacity' : 'fixedCost');

/// customers: demand (empty: 1) and - for costs per unit - their cost factor
RoleSpec _customers({bool withCostFactor = false}) => RoleSpec('destinations', 'customer', [
  const FieldSpec('demand', FieldKind.number, min: 0, hint: 'hint.one'),
  if (withCostFactor) const FieldSpec('costFactor', FieldKind.number, defaultValue: 1.0, min: 0),
], main: 'demand');

const _p = FieldSpec('p', FieldKind.integer, required: true, min: 1);
const _radius = FieldSpec('radius', FieldKind.number, required: true, min: 0, unit: '@measure');
// medians, centres and coverings: distances unless chosen otherwise
const _matrixMode = FieldSpec(
  'matrixMode',
  FieldKind.choice,
  choices: ['distances', 'times', 'costs'],
  labelKey: 'field.matrixModeLocation',
);
const _isCapacitated = FieldSpec('isCapacitated', FieldKind.boolean, defaultValue: false);
const _isDemandWeighted = FieldSpec('isDemandWeighted', FieldKind.boolean, defaultValue: false);

final wlpSpec = ModuleSpec(
  type: 'wlp',
  group: ModuleGroup.location,
  roles: [_candidates(withCapacity: true), _customers(withCostFactor: true)],
  parameters: const [matrixModeField, _isCapacitated, ...solverFields],
  objective: _objVal,
  summary: const [
    ResultColumn('objVal', unit: '€', labelKey: 'result.totalCosts'),
    ResultColumn('totalFixedCosts', unit: 'EUR', labelKey: 'result.totalOpeningCosts'),
    ResultColumn('totalVarCosts', unit: '€'),
    ResultColumn('nrOfOpen', labelKey: 'result.nrOfLocations'),
    ResultColumn('longestAssignment', unit: '€'),
  ],
);

final pMedianSpec = ModuleSpec(
  type: 'pmedian',
  group: ModuleGroup.location,
  roles: [_candidates(withCapacity: true), _customers(withCostFactor: true)],
  parameters: const [_p, _matrixMode, _isDemandWeighted, _isCapacitated, ...solverFields],
  objective: _objVal,
  summary: const [
    ResultColumn('objVal', unit: '€', labelKey: 'result.sumOfAssignments'),
    ResultColumn('nrOfOpen', labelKey: 'result.nrOfLocations'),
    ResultColumn('longestAssignment', unit: '€'),
  ],
);

final pCentreSpec = ModuleSpec(
  type: 'pcentre',
  group: ModuleGroup.location,
  roles: [_candidates(withCapacity: true), _customers()],
  parameters: const [_p, _matrixMode, _isDemandWeighted, _isCapacitated, ...solverFields],
  objective: _objVal,
  summary: const [
    ResultColumn('objVal', unit: '€', labelKey: 'result.longestAssignment'),
    ResultColumn('nrOfOpen', labelKey: 'result.nrOfLocations'),
  ],
);

final scpSpec = ModuleSpec(
  type: 'scp',
  group: ModuleGroup.location,
  roles: [
    _candidates(withFixedCosts: (p) => _fixed(p, byDefault: false)),
    _customers(),
  ],
  parameters: const [
    _radius,
    _matrixMode,
    FieldSpec('useFixedCosts', FieldKind.boolean, defaultValue: false, labelKey: 'field.useOpeningCosts'),
    ...solverFields,
  ],
  // fewest locations - or the lowest opening costs
  objective: (p) => _fixed(p, byDefault: false) ? 'totalFixedCosts' : 'nrOfOpen',
  summary: const [
    ResultColumn('nrOfOpen', labelKey: 'result.nrOfLocations'),
    ResultColumn('totalFixedCosts', unit: 'EUR', labelKey: 'result.totalOpeningCosts'),
    ResultColumn('longestAssignment', unit: '€'),
  ],
);

final mcpSpec = ModuleSpec(
  type: 'mcp',
  group: ModuleGroup.location,
  roles: [
    _candidates(withFixedCosts: (p) => _fixed(p, byDefault: true)),
    _customers(),
  ],
  parameters: [
    _radius,
    // the budget: opening costs - without them the number of locations
    FieldSpec(
      'maxSrcCost',
      FieldKind.number,
      required: true,
      min: 0,
      unit: '€',
      labelKey: 'field.budget',
      visibleIf: (p) => _fixed(p, byDefault: true),
    ),
    FieldSpec(
      'maxSrcCost',
      FieldKind.integer,
      required: true,
      min: 1,
      labelKey: 'field.maxLocations',
      visibleIf: (p) => !_fixed(p, byDefault: true),
    ),
    _matrixMode,
    const FieldSpec('useFixedCosts', FieldKind.boolean, defaultValue: true, labelKey: 'field.useOpeningCosts'),
    ...solverFields,
  ],
  objective: (_) => 'coveredDemand',
  summary: const [
    ResultColumn('coveredDemand'),
    ResultColumn('coverage', unit: '%'),
    ResultColumn('nrOfUncovered'),
    ResultColumn('nrOfOpen', labelKey: 'result.nrOfLocations'),
    ResultColumn('totalFixedCosts', unit: 'EUR', labelKey: 'result.totalOpeningCosts'),
  ],
);

//*************** continuous location problems ************************************
//
// p locations anywhere on the map (great-circle distances) - their places are a result, not nodes.

List<FieldSpec> _continuousParameters() => [
  _p,
  const FieldSpec('isDemandWeighted', FieldKind.boolean, defaultValue: true),
  _isCapacitated,
  // one capacity for all locations
  FieldSpec(
    'capacities',
    FieldKind.number,
    required: true,
    min: 0,
    labelKey: 'field.capacityPerLocation',
    visibleIf: _capacitated,
  ),
  FieldSpec(
    'isSingleSource',
    FieldKind.boolean,
    defaultValue: true,
    labelKey: 'field.isSingleSourceLocation',
    visibleIf: _capacitated,
  ),
  const FieldSpec('nrOfStarts', FieldKind.integer, min: 1, hint: 'hint.auto'),
  const FieldSpec('maxSolvingTime', FieldKind.number, unit: 's', min: 1),
];

final contPMedianSpec = ModuleSpec(
  type: 'contpmedian',
  group: ModuleGroup.location,
  roles: [_customers(withCostFactor: true)],
  parameters: _continuousParameters(),
  objective: _objVal,
  summary: const [
    ResultColumn('objVal', unit: '€', labelKey: 'result.objVal'),
    ResultColumn('totalDistance', unit: '€', labelKey: 'result.sumOfAssignments'),
    ResultColumn('longestAssignment', unit: '€'),
    ResultColumn('nrOfOpen', labelKey: 'result.nrOfLocations'),
  ],
);

final contPCentreSpec = ModuleSpec(
  type: 'contpcentre',
  group: ModuleGroup.location,
  roles: [_customers()],
  parameters: _continuousParameters(),
  objective: _objVal,
  summary: const [
    ResultColumn('objVal', unit: '€', labelKey: 'result.objVal'),
    ResultColumn('longestAssignment', unit: '€'),
    ResultColumn('totalDistance', unit: '€', labelKey: 'result.sumOfAssignments'),
    ResultColumn('nrOfOpen', labelKey: 'result.nrOfLocations'),
  ],
);

final locationSpecs = [wlpSpec, pMedianSpec, pCentreSpec, scpSpec, mcpSpec, contPMedianSpec, contPCentreSpec];
