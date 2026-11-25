# Tom Modules — Agent Guidelines

Guidelines of the **tom_modules** repository: reusable business models and
UI modules of the Tom workspace.

## Placement rule: where a component belongs

Three layers, each depending only on itself and the layers below:

| Layer | Repository | Holds | May depend on |
| --- | --- | --- | --- |
| 1 Framework | `tom_ai` (basics, core, core extensions) and **`tom_modules`** (this repository) | services, storage, sync, the business models (items, calendar, formula), file sessions and editors, highlighters, the PDF and office widgets: models and widgets any Flutter or Dart program can use | layer 1 |
| 2 Libraries of the kit | `tom_forge_modules` (`tom_ai/forge_modules`) | the Forge kit, its editors, adapters, views and hosts, Webwork's libraries, and every component that follows the kit's contracts | layers 1 and 2 |
| 3 Applications | `tom_forge`, `app_webwork`, `app_secrets_manager`, new projects | the composition of an application | layers 1 and 2 |

- **A package here is free of Forge:** it never depends on `tom_forge_modules`
  or on an application. A component that needs the kit (a `ForgeEditor`, a
  `ForgeKitApi` module) is an adapter and belongs in `tom_forge_modules`, next
  to the model or widget it adapts, which stays here.
- A model or widget that another application could use without Forge belongs
  here, not in `tom_forge_modules`.

The packages and what each holds: [../README.md](../README.md).
