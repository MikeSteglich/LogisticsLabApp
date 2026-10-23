/// Routing: travelling salesman problem - round trip (back to the start), passage from a start to an end node
/// ("Durchfahrt"), open end, open start or completely open. The tour visits all active nodes of the scenario.
library;

import 'module_spec.dart';

/// the start is given - not with an open start or completely open
bool _withStart(Map<String, dynamic> p) => !const ['openStart', 'free'].contains(p['tourType']);

/// the end is given: passage or open start
bool _withEnd(Map<String, dynamic> p) => const ['path', 'openStart'].contains(p['tourType']);

final tspSpec = ModuleSpec(
  type: 'tsp',
  group: ModuleGroup.routing,
  roles: const [],
  allNodes: true,
  edgeDirections: true,
  network: NetworkUse.optional,
  parameters: [
    const FieldSpec(
      'tourType',
      FieldKind.choice,
      defaultValue: 'round',
      choices: ['round', 'path', 'open', 'openStart', 'free'],
    ),
    FieldSpec('startNode', FieldKind.node, required: true, visibleIf: _withStart),
    FieldSpec('endNode', FieldKind.node, required: true, visibleIf: _withEnd),
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
