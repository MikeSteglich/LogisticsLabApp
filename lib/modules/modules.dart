import 'flows.dart';
import 'module_spec.dart';
import 'routing.dart';
import 'tpp.dart';

export 'flows.dart';
export 'module_spec.dart';
export 'routing.dart';
export 'tpp.dart';

/// All modules of the UI - the menu "new problem" of the problem chooser groups them by ModuleGroup.
final modules = {
  for (final m in [tppSpec, ...flowSpecs, tspSpec]) m.type: m,
};

/// Problem types of the menu "new problem" - those without ModuleSpec are not implemented in the prototype yet.
const problemTypesByGroup = {
  ModuleGroup.transport: ['tpp'],
  ModuleGroup.location: ['wlp', 'pmedian', 'pcentre', 'scp', 'mcp', 'contpmedian', 'contpcentre'],
  ModuleGroup.routing: ['tsp', 'cpp', 'vrp'],
  ModuleGroup.network: ['mincostflow', 'maxflow', 'multicommodity', 'multimodal', 'multistagewlp'],
};

Map<ModuleGroup, List<ModuleSpec>> modulesByGroup() => {
  for (final g in ModuleGroup.values)
    g: [
      for (final m in modules.values)
        if (m.group == g) m,
    ],
};

/// Message keys of all modules and of the common texts.
Set<String> allMessageKeys() => {
  for (final g in ModuleGroup.values) 'group.${g.name}',
  ...errorKeys,
  for (final m in modules.values) ...m.messageKeys,
};
