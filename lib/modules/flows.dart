/// Network flows: min cost flow, max flow, multi-commodity flow, multimodal flow and the multi-stage WLP.
///
/// All need a network (its edges are the connections), the matrix of the scenario gives the costs of the edges.
/// Node capacities (minCap, maxCap) are split by the core into in- and output - no extra nodes needed.
library;

import 'module_spec.dart';

const _balance = FieldSpec('balance', FieldKind.choice, defaultValue: 'auto', choices: ['auto', 'exact']);
const _nodeCaps = [FieldSpec('minCap', FieldKind.number, min: 0), FieldSpec('maxCap', FieldKind.unlimited, min: 0)];
const _shortage = FieldSpec('shortageCost', FieldKind.number, unit: '€', min: 0);
const _flowSummary = [
  ResultColumn('objVal', unit: '€', labelKey: 'result.objVal'),
  ResultColumn('totalVarCosts', unit: '€'),
  ResultColumn('totalFixedCosts', unit: '€'),
  ResultColumn('totalShortageCosts', unit: '€'),
];
String? _objVal(Map<String, dynamic> _) => 'objVal';

final minCostFlowSpec = ModuleSpec(
  type: 'mincostflow',
  group: ModuleGroup.network,
  network: NetworkUse.required,
  roles: const [
    RoleSpec('sources', 'supplier', [FieldSpec('supply', FieldKind.number, required: true, min: 0)]),
    RoleSpec('destinations', 'customer', [FieldSpec('demand', FieldKind.number, required: true, min: 0), _shortage]),
  ],
  nodeFields: _nodeCaps,
  parameters: [
    matrixModeField,
    const FieldSpec('useFixedCosts', FieldKind.boolean, defaultValue: false),
    _balance,
    ...solverFields,
  ],
  edgeFields: const [
    FieldSpec('capacity', FieldKind.unlimited, min: 0),
    FieldSpec('minFlow', FieldKind.number, min: 0),
    FieldSpec('fixedCost', FieldKind.number, unit: '€', min: 0, requires: 'useFixedCosts'),
  ],
  summary: _flowSummary,
  objective: _objVal,
);

final maxFlowSpec = ModuleSpec(
  type: 'maxflow',
  group: ModuleGroup.network,
  network: NetworkUse.required,
  usesMatrix: false,
  roles: const [],
  nodeFields: _nodeCaps,
  parameters: const [
    FieldSpec('source', FieldKind.node, required: true),
    FieldSpec('sink', FieldKind.node, required: true),
    FieldSpec('maxSolvingTime', FieldKind.number, unit: 's', min: 1),
  ],
  edgeFields: const [
    FieldSpec('capacity', FieldKind.unlimited, min: 0),
    FieldSpec('minFlow', FieldKind.number, min: 0),
  ],
  summary: const [ResultColumn('objVal', labelKey: 'result.maxFlow')],
  objective: _objVal,
);

final multiCommoditySpec = ModuleSpec(
  type: 'multicommodity',
  group: ModuleGroup.network,
  network: NetworkUse.required,
  usesCommodities: true,
  roles: const [
    RoleSpec('sources', 'supplier', [FieldSpec('supplies', FieldKind.commodities, required: true)]),
    RoleSpec('destinations', 'customer', [FieldSpec('demands', FieldKind.commodities, required: true), _shortage]),
  ],
  nodeFields: const [..._nodeCaps, FieldSpec('capacityFactors', FieldKind.commodities)],
  parameters: const [
    FieldSpec('isInteger', FieldKind.boolean, defaultValue: false),
    _balance,
    FieldSpec('maxSolvingTime', FieldKind.number, unit: 's', min: 1),
    FieldSpec('mipGap', FieldKind.number, min: 0),
  ],
  edgeFields: const [
    FieldSpec('capacity', FieldKind.unlimited, min: 0),
    FieldSpec('minFlow', FieldKind.number, min: 0),
  ],
  summary: const [
    ResultColumn('objVal', unit: '€', labelKey: 'result.objVal'),
    ResultColumn('totalShortageCosts', unit: '€'),
  ],
  objective: _objVal,
);

final multimodalSpec = ModuleSpec(
  type: 'multimodal',
  group: ModuleGroup.network,
  network: NetworkUse.required,
  usesModes: true,
  roles: const [
    RoleSpec('sources', 'supplier', [FieldSpec('supply', FieldKind.number, required: true, min: 0)]),
    RoleSpec('destinations', 'customer', [FieldSpec('demand', FieldKind.number, required: true, min: 0), _shortage]),
  ],
  nodeFields: _nodeCaps,
  parameters: [_balance, ...solverFields],
  edgeFields: const [FieldSpec('modes', FieldKind.modes)],
  summary: _flowSummary,
  objective: _objVal,
);

final multiStageWlpSpec = ModuleSpec(
  type: 'multistagewlp',
  group: ModuleGroup.network,
  network: NetworkUse.required,
  roles: const [
    RoleSpec('sources', 'supplier', [FieldSpec('supply', FieldKind.number, required: true, min: 0)]),
    RoleSpec('warehouses', 'candidate', [
      FieldSpec('fixedCost', FieldKind.number, unit: '€', min: 0, labelKey: 'field.openingCost'),
      FieldSpec('capacity', FieldKind.unlimited, min: 0),
    ]),
    RoleSpec('destinations', 'customer', [FieldSpec('demand', FieldKind.number, required: true, min: 0), _shortage]),
  ],
  nodeFields: const [FieldSpec('minCap', FieldKind.number, min: 0)],
  parameters: [
    matrixModeField,
    const FieldSpec('isSingleSource', FieldKind.boolean, defaultValue: false, labelKey: 'field.isSingleSourceWlp'),
    _balance,
    ...solverFields,
  ],
  edgeFields: const [
    FieldSpec('capacity', FieldKind.unlimited, min: 0),
    FieldSpec('minFlow', FieldKind.number, min: 0),
    FieldSpec('fixedCost', FieldKind.number, unit: '€', min: 0),
  ],
  summary: const [
    ResultColumn('objVal', unit: '€', labelKey: 'result.objVal'),
    ResultColumn('totalOpeningCosts', unit: '€'),
    ResultColumn('nrOfOpen'),
    ResultColumn('totalVarCosts', unit: '€'),
    ResultColumn('totalFixedCosts', unit: '€'),
    ResultColumn('totalShortageCosts', unit: '€'),
  ],
  objective: _objVal,
);

final flowSpecs = [minCostFlowSpec, maxFlowSpec, multiCommoditySpec, multimodalSpec, multiStageWlpSpec];
