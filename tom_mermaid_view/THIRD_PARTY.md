# Third-party software in tom_mermaid_view

The package's own code is BSD-3-Clause ([LICENSE](LICENSE)). It vendors one
component, shipped to every application that depends on it as a Flutter asset.

## mermaid.js 11.13.0 — MIT

| | |
| --- | --- |
| File | `assets/js/mermaid.min.js` (2,894 KB) |
| Version | 11.13.0, the unmodified distribution build: byte-identical to `https://cdn.jsdelivr.net/npm/mermaid@11.13.0/dist/mermaid.min.js` (SHA-256 `3e2002bf333907fae7c1d6860bbc78f5da417bc70b64f3d2268581ba0ba8b96a`) |
| Upstream | <https://github.com/mermaid-js/mermaid>, by Knut Sveidqvist and the Mermaid contributors |
| Licence | MIT; the text is [assets/js/LICENSE](assets/js/LICENSE), copied from the tag `mermaid@11.13.0` |
| How it reaches a user | loaded by `MermaidWebView` from the asset bundle into its webview; nothing is fetched from the network |

The build bundles Mermaid's npm dependencies. Its own banner ("Bundled license
information") names DOMPurify 3.3.1, js-yaml 4.1.1, lodash-es and cytoscape.
The licences, as their packages declare them:

| Dependency | Licence |
| --- | --- |
| `@braintree/sanitize-url`, `@iconify/utils`, `@mermaid-js/parser`, `@upsetjs/venn.js`, `cytoscape`, `cytoscape-cose-bilkent`, `cytoscape-fcose`, `dagre-d3-es`, `dayjs`, `js-yaml`, `katex`, `khroma`, `lodash-es`, `marked`, `roughjs`, `stylis`, `ts-dedent`, `uuid` | MIT |
| `d3` | ISC |
| `d3-sankey` | BSD-3-Clause |
| `dompurify` | MPL-2.0 or Apache-2.0, at the user's choice; used here under Apache-2.0 |

None is under a copyleft licence that would reach the application's code.

To update mermaid.js: replace `assets/js/mermaid.min.js` with the
`dist/mermaid.min.js` of the new release, replace `assets/js/LICENSE` with
that tag's `LICENSE`, and update the version, checksum and dependency table
here and in the `THIRD_PARTY.md` of the applications that ship it
(`tom_forge/tom_forge_app`, `app_webwork`).
