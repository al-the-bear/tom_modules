# Third-party components

| Component | License | How it is used |
| --- | --- | --- |
| [zetajs](https://github.com/allotropia/zetajs) `source/zeta.js`, commit `b3dec98af5dc4c059a260afd6db0bf0fe38c6384` | MIT ([assets/zetaoffice/zeta.js.LICENSE](assets/zetaoffice/zeta.js.LICENSE)) | Vendored unchanged except for a header naming its source, as `assets/zetaoffice/zeta.js`: the UNO bridge the office thread uses. |
| [ZetaOffice](https://zetaoffice.net) (`soffice.js`, `soffice.wasm`, `soffice.data`) | MPL-2.0 (LibreOffice) | Not distributed: downloaded at run time from `cdn.zetaoffice.net` after the user confirms, into the user's cache folder. Never committed to a repository. |
| [flutter_inappwebview](https://github.com/pichillilorenzo/flutter_inappwebview), the fork `tom_flutter_inappwebview` | Apache-2.0 | Dependency: the webview `TomZetaOfficeView` shows ZetaOffice in. |
