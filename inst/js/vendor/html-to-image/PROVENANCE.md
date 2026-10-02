# html-to-image 1.11.13

- **Project:** <https://github.com/bubkoo/html-to-image>
- **Package:** `html-to-image@1.11.13`, pinned in the root `package.json`.
- **Upstream archive:** <https://registry.npmjs.org/html-to-image/-/html-to-image-1.11.13.tgz>
- **Archive integrity:** `sha512-cuOPoI7WApyhBElTTb9oqsawRvZ0rHhaHwghRLlTuffoD1B2aDemlCruLeZrUIIdvG7gs9xeELEPm6PhuASqrg==` from `package-lock.json`;
  verified by npm during `npm ci`.
- **Bundled file:** `html-to-image-1.11.13.umd.js` is copied without modification from
  `node_modules/html-to-image/dist/html-to-image.js` (20562 bytes).
- **Bundle SHA-256:** `a90b42909d80964269ef6d5f3d1e4a5a7e2a4c263a5d2a76a9e7151901343262`.
- **License:** MIT; Copyright (c) 2017-2025 W.Y. The upstream `LICENSE` is copied
  without modification, and bundle notices are preserved.

## Refresh the vendored files

From the repository root, run:

```sh
npm ci
npm run vendor:html-to-image
```

npm and Node.js are development tools only; the R package uses the bundled asset
and does not install npm dependencies at runtime. To upgrade, update the exact
version in `package.json` and regenerate `package-lock.json` with
`npm install --package-lock-only`, then run the commands above. Review upstream
licensing and the separate `DESCRIPTION` copyright-holder attribution manually
when upgrading. The script rejects unexpected project or license structure;
resolve those changes before refreshing. It removes only obsolete versioned
`html-to-image-<version>.umd.js` bundles and refreshes the component notice in
`LICENSE.note`, preserving other files and notices.
