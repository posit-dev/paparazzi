import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, readdir, stat, unlink, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
const vendor = path.join(root, 'inst/js/vendor/html-to-image');
const upstream = path.join(root, 'node_modules/html-to-image');
const readJson = async (file) => JSON.parse(await readFile(file, 'utf8'));

// Validate inputs and notices before replacing any distributed files.
const project = await readJson(path.join(root, 'package.json'));
const lock = await readJson(path.join(root, 'package-lock.json'));
const installed = await readJson(path.join(upstream, 'package.json'));
const version = project.devDependencies?.['html-to-image'];
assert.match(version ?? '', /^\d+\.\d+\.\d+$/, 'Use an exact html-to-image version');
assert.equal(project.private, true, 'The npm project must remain private');
assert.match(await readFile(path.join(root, 'DESCRIPTION'), 'utf8'), /^Package: paparazzi$/m);
assert.ok((await stat(vendor)).isDirectory(), 'Expected the existing vendor directory');
assert.equal(lock.lockfileVersion, 3, 'Expected npm lockfile version 3');
assert.equal(lock.packages?.['']?.devDependencies?.['html-to-image'], version);
const locked = lock.packages?.['node_modules/html-to-image'];
assert.equal(locked?.version, version, 'Lockfile version differs; update the lock and run npm ci');
assert.equal(locked.dev, true, 'html-to-image must be development-only');
assert.equal(installed.name, 'html-to-image');
assert.equal(installed.version, version, 'Installed version differs; run npm ci');
assert.equal(installed.repository?.url, 'git+https://github.com/bubkoo/html-to-image.git',
  'Unexpected upstream repository; review project identity');
const repository = installed.repository.url.replace(/^git\+/, '').replace(/\.git$/, '');
const archive = `https://registry.npmjs.org/html-to-image/-/html-to-image-${version}.tgz`;
assert.equal(locked.resolved, archive, 'Unexpected npm archive source');
assert.match(locked.integrity ?? '', /^sha512-[A-Za-z0-9+/]{86}==$/, 'Expected npm SHA-512 integrity');
assert.equal(installed.license, 'MIT', 'License changed; review licensing before vendoring');
assert.equal(locked.license, 'MIT');

const license = await readFile(path.join(upstream, 'LICENSE'));
const licenseText = license.toString('utf8');
const paragraphs = licenseText.trim().split(/\r?\n\r?\n/);
assert.equal(paragraphs.length, 5, 'Unexpected license structure; review upstream notices');
assert.equal(paragraphs[0], 'MIT License');
const copyright = paragraphs[1];
assert.match(copyright, /^Copyright \(c\) \d{4}(?:-\d{4})? W\.Y\.$/,
  'Upstream copyright identity or format changed; review attribution manually');
assert.ok(paragraphs[2].startsWith('Permission is hereby granted, free of charge, to any person obtaining a copy'));
assert.ok(paragraphs[3].startsWith('The above copyright notice and this permission notice shall be included in all'));
assert.ok(paragraphs[4].startsWith('THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND'));
assert.ok(paragraphs[4].endsWith('SOFTWARE.'));

const notePath = path.join(root, 'LICENSE.note');
const note = await readFile(notePath, 'utf8');
const componentNotice = /This package also includes the unmodified html-to-image \d+\.\d+\.\d+ JavaScript\nlibrary at inst\/js\/vendor\/html-to-image\/html-to-image-\d+\.\d+\.\d+\.umd\.js\. That\ncomponent is Copyright \(c\) [^\n]+ and is separately licensed under the\nMIT License\. Its complete license is at\ninst\/js\/vendor\/html-to-image\/LICENSE\. Source and checksum details are in\ninst\/js\/vendor\/html-to-image\/PROVENANCE\.md\./g;
assert.equal([...note.matchAll(componentNotice)].length, 1,
  'Expected one html-to-image notice in LICENSE.note; review structure manually');
const bundleName = `html-to-image-${version}.umd.js`;
const updatedNote = note.replace(componentNotice,
  `This package also includes the unmodified html-to-image ${version} JavaScript\n` +
  `library at inst/js/vendor/html-to-image/${bundleName}. That\n` +
  `component is ${copyright} and is separately licensed under the\n` +
  'MIT License. Its complete license is at\n' +
  'inst/js/vendor/html-to-image/LICENSE. Source and checksum details are in\n' +
  'inst/js/vendor/html-to-image/PROVENANCE.md.');

const bundle = await readFile(path.join(upstream, 'dist/html-to-image.js'));
assert.ok(bundle.length > 0, 'Upstream bundle is empty');
const checksum = createHash('sha256').update(bundle).digest('hex');
const provenance = `# html-to-image ${version}

- **Project:** <${repository}>
- **Package:** \`html-to-image@${version}\`, pinned in the root \`package.json\`.
- **Upstream archive:** <${locked.resolved}>
- **Archive integrity:** \`${locked.integrity}\` from \`package-lock.json\`;
  verified by npm during \`npm ci\`.
- **Bundled file:** \`${bundleName}\` is copied without modification from
  \`node_modules/html-to-image/dist/html-to-image.js\` (${bundle.length} bytes).
- **Bundle SHA-256:** \`${checksum}\`.
- **License:** MIT; ${copyright} The upstream \`LICENSE\` is copied
  without modification, and bundle notices are preserved.

## Refresh the vendored files

From the repository root, run:

\`\`\`sh
npm ci
npm run vendor:html-to-image
\`\`\`

npm and Node.js are development tools only; the R package uses the bundled asset
and does not install npm dependencies at runtime. To upgrade, update the exact
version in \`package.json\` and regenerate \`package-lock.json\` with
\`npm install --package-lock-only\`, then run the commands above. Review upstream
licensing and the separate \`DESCRIPTION\` copyright-holder attribution manually
when upgrading. The script rejects unexpected project or license structure;
resolve those changes before refreshing. It removes only obsolete versioned
\`html-to-image-<version>.umd.js\` bundles and refreshes the component notice in
\`LICENSE.note\`, preserving other files and notices.
`;

const obsolete = (await readdir(vendor)).filter((name) =>
  /^html-to-image-\d+\.\d+\.\d+\.umd\.js$/.test(name) && name !== bundleName);
for (const name of obsolete) {
  assert.ok((await stat(path.join(vendor, name))).isFile(), `Not a bundle file: ${name}`);
}
await writeFile(path.join(vendor, bundleName), bundle);
await writeFile(path.join(vendor, 'LICENSE'), license);
await writeFile(path.join(vendor, 'PROVENANCE.md'), provenance);
await writeFile(notePath, updatedNote);
for (const name of obsolete) await unlink(path.join(vendor, name));
console.log(`Vendored html-to-image ${version}; SHA-256 ${checksum}`);
