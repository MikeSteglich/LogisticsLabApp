/// Routing: chinese postman (below) and travelling salesman problem - round trip (back to the start), passage from a start to an end node
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

/// Chinese postman: the shortest tour from the start over every edge of the network (at least once) and back -
/// each edge directed or not
final cppSpec = ModuleSpec(
  type: 'cpp',
  group: ModuleGroup.routing,
  roles: const [],
  network: NetworkUse.required,
  edgeDirections: true,
  parameters: const [
    FieldSpec('startNode', FieldKind.node, required: true),
    FieldSpec('matrixMode', FieldKind.choice, choices: ['distances', 'times', 'costs'], defaultValue: 'distances'),
    ...solverFields,
  ],
  objective: (_) => 'tourLength',
  summary: const [
    ResultColumn('tourLength', unit: '€'),
    ResultColumn('edgesLength', unit: '€'),
    ResultColumn('extraLength', unit: '€'),
    ResultColumn('nrOfEdges'),
    ResultColumn('nrOfRepeats'),
  ],
);

/// Pickup and delivery: every pickup brings its amount to its delivery node - on the same tour, the pickup first, the
/// load at most the capacity of the vehicle. Depot, vehicles, times and parameters as in the vehicle routing.
final pdpSpec = ModuleSpec(
  type: 'pdp',
  group: ModuleGroup.routing,
  usesVehicles: true,
  roles: [
    const RoleSpec('depots', 'depot', [
      FieldSpec('timeWindow', FieldKind.timeWindow, labelKey: 'field.depotTime'),
    ], main: 'timeWindow'),
    RoleSpec('sources', 'pickup', [
      const FieldSpec('amount', FieldKind.number, required: true, min: 0),
      const FieldSpec('deliveryTo', FieldKind.node, required: true, nodeRole: 'delivery'),
      const FieldSpec('serviceTime', FieldKind.number, unit: '@time', min: 0),
      FieldSpec('timeWindow', FieldKind.timeWindow, unit: '@time', visibleIf: (p) => isOn(p, 'useTimeWindows')),
    ], main: 'amount'),
    RoleSpec('destinations', 'delivery', [
      // the amounts of the pickups delivered here - entered at the pickups
      const FieldSpec('delivered', FieldKind.number, computed: true),
      // service: a stop time per visit and a time per unit delivered - several quantities at one stop share the
      // stop time
      const FieldSpec('serviceTime', FieldKind.number, labelKey: 'field.stopTime', unit: '@time', min: 0),
      const FieldSpec('serviceTimePerUnit', FieldKind.number, unit: '@time', min: 0),
      FieldSpec('timeWindow', FieldKind.timeWindow, unit: '@time', visibleIf: (p) => isOn(p, 'useTimeWindows')),
    ], main: 'delivered'),
  ],
  // dial-a-ride: the longest ride of every pair - absolute and as a factor of the direct ride, the stricter counts
  parameters: [
    for (final f in vrpSpec.parameters) ...[
      if (f.key == 'maxSolvingTime') ...const [
        FieldSpec('maxRideTime', FieldKind.number, unit: '@time', min: 0),
        FieldSpec('maxDetour', FieldKind.number, min: 1),
      ],
      f,
    ],
  ],
  objective: (_) => 'totalDistance',
  summary: [
    ...vrpSpec.summary,
    const ResultColumn('longestRide', unit: '@time'),
    const ResultColumn('maxDetour', unit: '×'),
  ],
);

/// Vehicle routing: tours of the vehicles from the depot to the customers and back - capacities, time windows and
/// service times, at most a time and a distance per tour. The vehicles are records of the scenario.
final vrpSpec = ModuleSpec(
  type: 'vrp',
  group: ModuleGroup.routing,
  usesVehicles: true,
  roles: [
    // the depot: start of the tours and their latest return (times of the day)
    const RoleSpec('depots', 'depot', [
      FieldSpec('timeWindow', FieldKind.timeWindow, labelKey: 'field.depotTime'),
    ], main: 'timeWindow'),
    RoleSpec('destinations', 'customer', [
      const FieldSpec('demand', FieldKind.number, required: true, min: 0),
      const FieldSpec('serviceTime', FieldKind.number, unit: '@time', min: 0),
      FieldSpec('timeWindow', FieldKind.timeWindow, unit: '@time', visibleIf: (p) => isOn(p, 'useTimeWindows')),
    ]),
  ],
  parameters: const [
    FieldSpec('useTimeWindows', FieldKind.boolean, defaultValue: false),
    // every tour starts at the start of the depot (waiting at the customers) - otherwise as late as needed
    FieldSpec('fixedStart', FieldKind.boolean, defaultValue: false),
    FieldSpec('maxTime', FieldKind.number, unit: '@time', min: 0),
    FieldSpec('maxDist', FieldKind.number, unit: '@distance', min: 0),
    FieldSpec('maxSolvingTime', FieldKind.number, unit: 's', min: 1),
  ],
  // total distance in the distance unit of the scenario
  objective: (_) => 'totalDistance',
  summary: const [
    ResultColumn('totalDistance', unit: '€'),
    ResultColumn('nrOfRoutes'),
    ResultColumn('nrOfVehicles'),
    ResultColumn('totalLoad'),
    ResultColumn('utilization', unit: '%'),
    ResultColumn('longestRoute', unit: '€'),
    ResultColumn('longestDuration', unit: '@time'),
    ResultColumn('totalWaitingTime', unit: '@time'),
  ],
);
