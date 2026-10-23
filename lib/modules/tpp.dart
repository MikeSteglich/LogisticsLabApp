import 'module_spec.dart';

//*************** transportation problem ************************************

/// maximisation: contribution per unit of a connection = price of the customer - unit cost of the supplier - transport
/// costs
bool _isMax(Map<String, dynamic> p) => p['objSense'] == 'max';

final tppSpec = ModuleSpec(
  type: 'tpp',
  group: ModuleGroup.transport,
  roles: [
    RoleSpec('sources', 'supplier', [
      const FieldSpec('supply', FieldKind.number, required: true, min: 0),
      FieldSpec('minSupply', FieldKind.number, min: 0, visibleIf: (p) => isOn(p, 'useSupplyRanges')),
      FieldSpec('maxSupply', FieldKind.unlimited, min: 0, visibleIf: (p) => isOn(p, 'useSupplyRanges')),
      FieldSpec('unitCost', FieldKind.number, unit: '€', min: 0, visibleIf: _isMax),
    ]),
    RoleSpec('destinations', 'customer', [
      const FieldSpec('demand', FieldKind.number, required: true, min: 0),
      FieldSpec('minDemand', FieldKind.number, min: 0, visibleIf: (p) => isOn(p, 'useDemandRanges')),
      FieldSpec('maxDemand', FieldKind.unlimited, min: 0, visibleIf: (p) => isOn(p, 'useDemandRanges')),
      const FieldSpec('costFactor', FieldKind.number, defaultValue: 1.0, min: 0),
      FieldSpec('price', FieldKind.number, unit: '€', min: 0, visibleIf: _isMax),
    ]),
  ],
  parameters: [
    objSenseField,
    matrixModeField,
    const FieldSpec('isSingleSource', FieldKind.boolean, defaultValue: false),
    const FieldSpec('minBlock', FieldKind.number, min: 0),
    const FieldSpec('maxBlock', FieldKind.unlimited, min: 0),
    const FieldSpec('useSupplyRanges', FieldKind.boolean, defaultValue: false),
    const FieldSpec('useDemandRanges', FieldKind.boolean, defaultValue: false),
    const FieldSpec('useCapacities', FieldKind.boolean, defaultValue: false),
    FieldSpec('useFixedCosts', FieldKind.boolean, defaultValue: false, visibleIf: (p) => p['objSense'] != 'maxflow'),
    ...solverFields,
  ],
  network: NetworkUse.optional,
  edgeFields: [
    FieldSpec('capacity', FieldKind.unlimited, min: 0, requires: 'useCapacities'),
    FieldSpec(
      'fixedCost',
      FieldKind.number,
      unit: '€',
      min: 0,
      requires: 'useFixedCosts',
      visibleIf: (p) => p['objSense'] != 'maxflow',
    ),
  ],
  // costs (or value) in total - the largest cost rate of the used connections with minimax (bottleneck) - max: the
  // contribution after the fixed costs
  objective: (p) => switch (p['objSense']) {
    'minimax' => 'maxCostRate',
    'maxflow' => 'totalFlow',
    'max' => 'netContribution',
    _ => 'totalCosts',
  },
  // min: costs, max: contributions - only the values of the solution are shown
  summary: const [
    ResultColumn('netContribution', unit: '€'),
    ResultColumn('totalContribution', unit: '€'),
    ResultColumn('totalCosts', unit: '€'),
    ResultColumn('totalVarCosts', unit: '€'),
    ResultColumn('totalFixedCosts', unit: '€'),
    ResultColumn('totalFlow'),
    ResultColumn('minCostRate'),
    ResultColumn('maxCostRate'),
    ResultColumn('minContributionRate'),
    ResultColumn('maxContributionRate'),
  ],
  nodeResults: const [ResultColumn('flow')],
  assignments: const [ResultColumn('flow'), ResultColumn('rate')],
);
