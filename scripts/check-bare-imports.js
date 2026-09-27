#!/usr/bin/env node
/*--------------------------------------------------------------------------------------
 *  Copyright 2026 Loophole AI. All rights reserved.
 *  Licensed under the AGPL-3.0 License. See LICENSE.txt for more information.
 *--------------------------------------------------------------------------------------*/

/**
 * check-bare-imports — fails the build if a shipped renderer bundle contains an
 * import specifier the browser cannot resolve.
 *
 * Why this exists: the workbench is loaded as ONE native ES module
 * (`await import('vs/workbench/workbench.desktop.main.js')` in
 * electron-browser/workbench.js) and no import map is installed for npm
 * packages. A bare specifier such as `"@huggingface/transformers"` therefore
 * cannot be resolved: the import() rejects, and because workbench.js has already
 * painted the dark background, the user gets a black window and no renderer log.
 *
 * The first version of this check grepped for one hard-coded package name, so it
 * reported OK for any *other* bare specifier, and it was marked
 * continue-on-error so it could never fail anything. This checks every
 * specifier of every renderer bundle and exits non-zero on any hit.
 *
 * It uses Node's own ES module parser (vm.SourceTextModule) rather than a regex.
 * That is deliberate: these bundles are minified, and a regex over a 20 MB file
 * matches across string boundaries and reports nonsense such as a bare "vm" that
 * is really the Node built-in name inside a string. Parsing gives exactly the
 * specifiers the browser would try to resolve, which is what we care about.
 *
 * Usage: node check-bare-imports.js <dir> [<dir> ...]
 * (re-execs itself with --experimental-vm-modules if the flag is missing)
 */

const fs = require('fs');
const path = require('path');
const vm = require('vm');

// vm.SourceTextModule is still behind a flag. Re-exec once with the flag rather
// than making every caller remember it.
if (typeof vm.SourceTextModule !== 'function') {
	if (process.env.CHECK_BARE_IMPORTS_RESPAWNED === '1') {
		console.error('::error::vm.SourceTextModule unavailable even with ' +
			'--experimental-vm-modules. Cannot verify renderer bundles.');
		process.exit(1);
	}
	const { spawnSync } = require('child_process');
	const r = spawnSync(
		process.execPath,
		['--experimental-vm-modules', '--no-warnings', __filename, ...process.argv.slice(2)],
		{ stdio: 'inherit', env: { ...process.env, CHECK_BARE_IMPORTS_RESPAWNED: '1' } }
	);
	process.exit(r.status === null ? 1 : r.status);
}

/** Bundles that are loaded as native ES modules in the renderer. */
const BUNDLE_NAMES = new Set([
	'workbench.desktop.main.js',
]);

/** True when the browser can resolve this specifier without an import map. */
function isResolvable(spec) {
	if (!spec) { return true; }
	if (spec.startsWith('./') || spec.startsWith('../') || spec.startsWith('/')) { return true; }
	// Any URL with a scheme: data:, blob:, node:, vscode-file: ...
	if (/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(spec)) { return true; }
	// VS Code's own internal specifiers.
	if (spec.startsWith('vs/')) { return true; }
	return false;
}

function walk(dir, depth, acc) {
	if (depth > 8) { return; }
	let entries;
	try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
	for (const e of entries) {
		const p = path.join(dir, e.name);
		if (e.isDirectory()) {
			if (e.name === 'node_modules' || e.name === '.git') { continue; }
			walk(p, depth + 1, acc);
		} else if (BUNDLE_NAMES.has(e.name)) {
			acc.push(p);
		}
	}
}

const roots = process.argv.slice(2);
if (roots.length === 0) {
	console.error('usage: node check-bare-imports.js <dir> [<dir> ...]');
	process.exit(2);
}

const bundles = [];
for (const r of roots) {
	if (!fs.existsSync(r)) { continue; }
	if (fs.statSync(r).isFile()) { bundles.push(r); } else { walk(r, 0, bundles); }
}

if (bundles.length === 0) {
	// A check that silently inspects nothing is worse than no check, because the
	// log line still says OK.
	console.error('::error::check-bare-imports found no renderer bundles to inspect. ' +
		'Point it at the directory containing out/vs/workbench/.');
	process.exit(1);
}

let bad = 0;
let totalSpecs = 0;

(async () => {
	for (const b of bundles) {
		const rel = path.relative(process.cwd(), b);
		let mod;
		try {
			// Parses the module without evaluating it, so nothing in the bundle runs.
			mod = new vm.SourceTextModule(fs.readFileSync(b, 'utf8'));
		} catch (e) {
			console.error('::error file=' + rel + '::failed to parse bundle: ' + e.message);
			bad++;
			continue;
		}

		const specs = [...new Set(mod.dependencySpecifiers)].sort();
		totalSpecs += specs.length;
		const bare = specs.filter(s => !isResolvable(s));

		if (bare.length === 0) {
			console.log('OK   ' + rel + '  (' + specs.length + ' specifiers, all resolvable)');
		} else {
			bad++;
			for (const s of bare) {
				console.error('::error file=' + rel + '::unresolvable bare import "' + s + '". ' +
					'The renderer has no import map for npm packages, so the workbench ' +
					'import() rejects and the IDE boots to a black screen.');
			}
		}
	}

	if (bad > 0) {
		console.error('');
		console.error('FAILED: ' + bad + ' bundle(s) contain unresolvable bare import specifiers.');
		process.exit(1);
	}

	console.log('');
	console.log('OK: no unresolvable bare imports in any renderer bundle (' +
		bundles.length + ' bundle(s), ' + totalSpecs + ' specifiers parsed).');
})();
