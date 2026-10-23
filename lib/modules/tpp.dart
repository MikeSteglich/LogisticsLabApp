import 'module_spec.dart';

//*************** transportation problem ************************************

final tppSpec = ModuleSpec(
  type: 'tpp',
  group: ModuleGroup.transport,
  roles: [
    RoleSpec('sources', 'supplier', [
      const FieldSpec('supply', FieldKind.number, required: true, min: 0),
      FieldSpec('minSupply', FieldKind.number, min: 0, visibleIf: (p) => isOn(p, 'useSupplyRanges')),
      FieldSpec('maxSupply', FieldKind.unlimited, min: 0, visibleIf: (p) => isOn(p, 'useSupplyRanges')),
    ]),
    RoleSpec('destinations', 'customer', [
      const FieldSpec('demand', FieldKind.number, required: true, min: 0),
      FieldSpec('minDemand', FieldKind.number, min: 0, visibleIf: (p) => isOn(p, 'useDemandRanges')),
      FieldSpec('maxDemand', FieldKind.unlimited, min: 0, visibleIf: (p) => isOn(p, 'useDemandRanges')),
      const FieldSpec('costFactor', FieldKind.number, defaultValue: 1.0, min: 0),
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
    const FieldSpec('useFixedCosts', FieldKind.boolean, defaultValue: false),
    ...solverFields,
  ],
  network: NetworkUse.optional,
  edgeFields: [
    FieldSpec('capacity', FieldKind.unlimited, min: 0, requires: 'useCapacities'),
    FieldSpec('fixedCost', FieldKind.number, unit: '€', min: 0, requires: 'useFixedCosts'),
  ],
  // costs (or value) in total - the largest cost rate of the used connections with minimax (bottleneck)
  objective: (p) => p['objSense'] == 'minimax' ? 'maxCostRate' : 'totalCosts',
  summary: const [
    ResultColumn('totalCosts', unit: '€'),
    ResultColumn('totalVarCosts', unit: '€'),
    ResultColumn('totalFixedCosts', unit: '€'),
    ResultColumn('totalFlow'),
    ResultColumn('minCostRate'),
    ResultColumn('maxCostRate'),
  ],
  nodeResults: const [ResultColumn('flow')],
  assignments: const [ResultColumn('flow'), ResultColumn('rate')],
);
