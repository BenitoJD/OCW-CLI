#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const childProcess = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const readline = require('node:readline');

const ROOT = path.resolve(__dirname, '..');
const OCW = path.join(ROOT, 'bin', 'ocw');
const MOCK_OPENCODE = path.join(ROOT, 'test', 'fixtures', 'opencode');
const MOCK_GH = path.join(ROOT, 'test', 'fixtures', 'gh');

function run(command, args, options = {}) {
  const result = childProcess.spawnSync(command, args, {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    ...options,
  });
  if (result.status !== 0) {
    throw new Error(`${command} ${args.join(' ')} failed\n${result.stdout}\n${result.stderr}`);
  }
  return result;
}

function makeRepo() {
  const repo = fs.mkdtempSync(path.join(os.tmpdir(), 'ocw-mcp-'));
  run('git', ['init', '-q'], { cwd: repo });
  fs.writeFileSync(path.join(repo, 'tracked.txt'), 'base\n');
  fs.writeFileSync(path.join(repo, 'attached.txt'), 'attachment\n');
  run('git', ['add', 'tracked.txt', 'attached.txt'], { cwd: repo });
  run('git', ['-c', 'user.name=OCW MCP', '-c', 'user.email=ocw-mcp@example.invalid', 'commit', '-q', '-m', 'init'], { cwd: repo });
  return repo;
}

function createClient(repo) {
  const server = childProcess.spawn(OCW, ['mcp'], {
    cwd: repo,
    env: {
      ...process.env,
      OCW_OPENCODE_BIN: MOCK_OPENCODE,
      OCW_GH_BIN: MOCK_GH,
      OCW_MOCK_LOG: path.join(repo, '.out', 'mock.log'),
      OCW_TEST_CREATED_AT: '2026-01-01T00:00:00Z',
    },
    stdio: ['pipe', 'pipe', 'pipe'],
  });

  const pending = new Map();
  const stderr = [];
  const rl = readline.createInterface({ input: server.stdout });
  rl.on('line', (line) => {
    const message = JSON.parse(line);
    if (Object.prototype.hasOwnProperty.call(message, 'id') && pending.has(message.id)) {
      const { resolve, reject } = pending.get(message.id);
      pending.delete(message.id);
      if (message.error) {
        reject(new Error(message.error.message));
      } else {
        resolve(message.result);
      }
    }
  });
  server.stderr.on('data', (chunk) => stderr.push(String(chunk)));

  let id = 1;
  function request(method, params) {
    const requestId = id;
    id += 1;
    server.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', id: requestId, method, params })}\n`);
    return new Promise((resolve, reject) => {
      pending.set(requestId, { resolve, reject });
      setTimeout(() => {
        if (pending.has(requestId)) {
          pending.delete(requestId);
          reject(new Error(`timeout waiting for ${method}\nstderr:\n${stderr.join('')}`));
        }
      }, 15000);
    });
  }

  function notify(method, params) {
    server.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', method, params })}\n`);
  }

  function close() {
    server.kill();
  }

  return { request, notify, close };
}

(async () => {
  const repo = makeRepo();
  const client = createClient(repo);
  try {
    const init = await client.request('initialize', {
      protocolVersion: '2025-06-18',
      capabilities: {},
      clientInfo: { name: 'ocw-test', version: '0.0.0' },
    });
    assert.equal(init.serverInfo.name, 'ocw-mcp');
    assert.ok(init.capabilities.tools);
    client.notify('notifications/initialized');

    const listed = await client.request('tools/list', {});
    const names = listed.tools.map((tool) => tool.name).sort();
    assert.deepEqual(names, ['ocw_apply', 'ocw_apply_check', 'ocw_audit', 'ocw_last', 'ocw_manifest', 'ocw_run', 'ocw_show', 'ocw_stats'].sort());

    const common = { cwd: repo, output_root: '.out' };
    const runCheap = await client.request('tools/call', {
      name: 'ocw_run',
      arguments: {
        ...common,
        mode: 'cheap',
        task: 'MCP cheap route',
        files: ['attached.txt'],
      },
    });
    assert.equal(runCheap.structuredContent.status, 0);
    assert.match(runCheap.structuredContent.output_dir, /cheap$/);

    const last = await client.request('tools/call', {
      name: 'ocw_last',
      arguments: { ...common, mode: 'cheap' },
    });
    assert.equal(last.structuredContent.status, 0);
    assert.match(last.structuredContent.stdout, /cheap/);

    const show = await client.request('tools/call', {
      name: 'ocw_show',
      arguments: { ...common, ref: 'latest', view: 'summary' },
    });
    assert.equal(show.structuredContent.status, 0);
    assert.match(show.structuredContent.stdout, /MOCK_OK/);

    const manifest = await client.request('tools/call', {
      name: 'ocw_manifest',
      arguments: { ...common, ref: 'latest' },
    });
    assert.equal(manifest.structuredContent.status, 0);
    assert.match(manifest.structuredContent.stdout, /"schema_version": "ocw\.manifest\.v1"/);
    assert.match(manifest.structuredContent.stdout, /"summary\.md"/);

    const audit = await client.request('tools/call', {
      name: 'ocw_audit',
      arguments: { ...common, ref: 'latest' },
    });
    assert.equal(audit.structuredContent.status, 0);
    assert.match(audit.structuredContent.stdout, /"overall": "ok"/);

    const patch = await client.request('tools/call', {
      name: 'ocw_run',
      arguments: {
        ...common,
        mode: 'patch',
        task: 'OCW_MOCK_EDIT',
        worktree: true,
      },
    });
    assert.equal(patch.structuredContent.status, 0);

    const check = await client.request('tools/call', {
      name: 'ocw_apply_check',
      arguments: common,
    });
    assert.equal(check.structuredContent.status, 0);
    assert.match(check.structuredContent.stdout, /Patch can be applied/);

    const apply = await client.request('tools/call', {
      name: 'ocw_apply',
      arguments: common,
    });
    assert.equal(apply.structuredContent.status, 0);
    assert.match(fs.readFileSync(path.join(repo, 'tracked.txt'), 'utf8'), /mock edit from opencode-go\/kimi-k2\.6/);

    const stats = await client.request('tools/call', {
      name: 'ocw_stats',
      arguments: { cwd: repo, args: ['--days', '7', '--models', '5'] },
    });
    assert.equal(stats.structuredContent.status, 0);
    assert.match(stats.structuredContent.stdout, /MOCK_STATS --days 7 --models 5/);
  } finally {
    client.close();
  }
})().catch((error) => {
  console.error(error.stack || error.message);
  process.exit(1);
});
