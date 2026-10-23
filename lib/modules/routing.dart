/// Routing: travelling salesman problem - round trip (back to the start), passage from a start to an end node
/// ("Durchfahrt") or with an open end. The tour visits all active nodes of the scenario.
library;

import 'module_spec.dart';

bool _isPath(Map<String, dynamic> p) => p['tourType'] == 'path';

final tspSpec = ModuleSpec(
  type: 'tsp',
  group: ModuleGroup.routing,
  roles: const [],
  allNodes: true,
  edgeDirections: true,
  network: NetworkUse.optional,
  parameters: [
    const FieldSpec('tourType', FieldKind.choice, defaultValue: 'round', choices: ['round', 'path', 'open']),
    const FieldSpec('startNode', FieldKind.node, required: true),
    FieldSpec('endNode', FieldKind.node, required: true, visibleIf: _isPath),
    const FieldSpec(
      'matrixMode',
      FieldKind.choice,
      choices: ['distances', 'times', 'costs'],
      defaultValue: 'distances',
    ),
  ],
  // length of the tour in the unit of the matrix (km, min or costs)
  objective: (_) => 'tourLength',
  summary: const [
    ResultColumn('tourLength', unit: '€'),
    ResultColumn('nrOfNodes'),
    ResultColumn('longestLeg', unit: '€'),
  ],
);
