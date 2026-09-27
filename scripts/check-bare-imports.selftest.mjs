// Self-test for check-bare-imports. A guard that cannot fail is worse than none,
// so prove it detects a real bare import and does not fire on a string that merely
// mentions one.
import { writeFileSync, mkdirSync, rmSync } from 'fs';
import { execFileSync } from 'child_process';
import { join } from 'path';

const root = join(process.env.TEMP || '/tmp', 'bare-import-selftest');
rmSync(root, { recursive: true, force: true });
mkdirSync(root, { recursive: true });

const script = process.argv[2];

const cases = [
	{
		name: 'clean relative imports',
		src: 'import{a}from"./x.js";import*as b from"../y.js";import"data:text/javascript,1";export{c}from"./z.js";',
		expect: 0,
	},
	{
		name: 'the 2.2.3 regression: bare huggingface import',
		src: 'import{pipeline}from"@huggingface/transformers";export const x=pipeline;',
		expect: 1,
	},
	{
		name: 'bare onnxruntime specifier',
		src: 'import*as W from"onnxruntime-web/webgpu";import{T}from"onnxruntime-common";export{W,T};',
		expect: 1,
	},
	{
		name: 'node built-in name inside a string must NOT fire',
		src: 'const m=await import("./real.js");const s="require(\'fs\')";const t=`vm`;const u="from \\"module\\" ";export{m,s,t,u};',
		expect: 0,
	},
	{
		name: 'vscode internal specifier is fine',
		src: 'import{x}from"vs/base/common/lifecycle";export{x};',
		expect: 0,
	},
	{
		name: 'relative dynamic import is fine',
		src: 'const p=await import(`./gen/${n}.js`);export{p};',
		expect: 0,
	},
];

let failed = 0;
for (const c of cases) {
	const dir = join(root, c.name.replace(/\W+/g, '_'));
	mkdirSync(dir, { recursive: true });
	writeFileSync(join(dir, 'workbench.desktop.main.js'), c.src);

	let code = 0;
	try {
		execFileSync(process.execPath, [script, dir], { stdio: 'pipe' });
		code = 0;
	} catch (e) {
		code = e.status === null ? -1 : e.status;
	}

	const ok = code === c.expect;
	if (!ok) { failed++; }
	console.log(
		(ok ? 'PASS  ' : 'FAIL  ') +
		c.name.padEnd(46) +
		'exit=' + String(code).padEnd(3) +
		'expected=' + c.expect
	);
}

rmSync(root, { recursive: true, force: true });
console.log('');
if (failed > 0) {
	console.error('SELF-TEST FAILED: ' + failed + ' case(s)');
	process.exit(1);
}
console.log('SELF-TEST PASSED: ' + cases.length + ' cases');
