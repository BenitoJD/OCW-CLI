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
      OCW_OUTPUT_ROOT: '.out',
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
    assert.ok(init.capabilities.resources);
    assert.ok(init.capabilities.prompts);
    client.notify('notifications/initialized');

    const listed = await client.request('tools/list', {});
    const names = listed.tools.map((tool) => tool.name).sort();
    assert.deepEqual(names, [
      'ocw_apply',
      'ocw_apply_check',
      'ocw_audit',
      'ocw_backend',
      'ocw_bridge',
      'ocw_dashboard',
      'ocw_delegate',
      'ocw_doctor',
      'ocw_eval',
      'ocw_last',
      'ocw_manifest',
      'ocw_mcp_audit',
      'ocw_memory',
      'ocw_models',
      'ocw_keys',
      'ocw_report',
      'ocw_route',
      'ocw_run',
      'ocw_savings',
      'ocw_show',
      'ocw_stats',
      'ocw_tournament',
      'ocw_verdict',
    ].sort());

    const common = { cwd: repo, output_root: '.out' };
    const doctor = await client.request('tools/call', {
      name: 'ocw_doctor',
      arguments: { ...common, deep: true },
    });
    assert.equal(doctor.structuredContent.status, 0);
    assert.match(doctor.structuredContent.stdout, /"schema_version": "ocw\.doctor\.v1"/);

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

    const missingShow = await client.request('tools/call', {
      name: 'ocw_show',
      arguments: { ...common, ref: 'missing-run', view: 'summary' },
    });
    assert.equal(missingShow.isError, true);
    assert.notEqual(missingShow.structuredContent.status, 0);
    assert.equal(missingShow.structuredContent.error_code, 'not_found');

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

    fs.writeFileSync(path.join(repo, 'models.json'), JSON.stringify({ models: [{ id: 'opencode-go/mcp-a' }, { id: 'opencode-go/mcp-b' }] }));
    const modelsSync = await client.request('tools/call', {
      name: 'ocw_models',
      arguments: { ...common, action: 'sync', url: `file://${path.join(repo, 'models.json')}`, out: '.codex/models.json' },
    });
    assert.equal(modelsSync.structuredContent.status, 0);
    assert.match(modelsSync.structuredContent.stdout, /ocw\.models\.sync\.v1/);
    const modelsMetadata = await client.request('tools/call', {
      name: 'ocw_models',
      arguments: { ...common, action: 'list', cache: '.codex/models.json', metadata: true },
    });
    assert.equal(modelsMetadata.structuredContent.status, 0);
    assert.match(modelsMetadata.structuredContent.stdout, /configured_modes/);
    const modelsProfiles = await client.request('tools/call', {
      name: 'ocw_models',
      arguments: { ...common, action: 'profiles' },
    });
    assert.equal(modelsProfiles.structuredContent.status, 0);
    assert.match(modelsProfiles.structuredContent.stdout, /balanced/);
    const modelsRecommend = await client.request('tools/call', {
      name: 'ocw_models',
      arguments: { ...common, action: 'recommend', mode: 'patch', profile: 'balanced', cache: '.codex/models.json' },
    });
    assert.equal(modelsRecommend.structuredContent.status, 0);
    assert.match(modelsRecommend.structuredContent.stdout, /opencode-go\/mcp-a/);
    const modelsConfigure = await client.request('tools/call', {
      name: 'ocw_models',
      arguments: {
        ...common,
        action: 'configure',
        profile: 'balanced',
        cache: '.codex/models.json',
        cheap: 'opencode-go/mcp-a',
        explore: 'opencode-go/mcp-b',
        scan: 'opencode-go/mcp-a',
        review: 'opencode-go/mcp-b',
        patch: 'opencode-go/mcp-a',
        reason: 'mcp smoke profile',
      },
    });
    assert.equal(modelsConfigure.structuredContent.status, 0);
    assert.match(modelsConfigure.structuredContent.stdout, /ocw\.models\.configure\.v1/);
    const keysList = await client.request('tools/call', {
      name: 'ocw_keys',
      arguments: { ...common, action: 'list' },
    });
    assert.equal(keysList.structuredContent.status, 0);
    assert.match(keysList.structuredContent.stdout, /ocw\.keys\.v1/);
    const keysDoctor = await client.request('tools/call', {
      name: 'ocw_keys',
      arguments: { ...common, action: 'doctor' },
    });
    assert.equal(keysDoctor.structuredContent.status, 0);
    assert.match(keysDoctor.structuredContent.stdout, /ocw\.keys\.doctor\.v1/);

    const routeSet = await client.request('tools/call', {
      name: 'ocw_route',
      arguments: { ...common, action: 'set', mode: 'cheap', model: 'opencode-go/mcp-a', reason: 'mcp smoke' },
    });
    assert.equal(routeSet.structuredContent.status, 0);
    const routeExplain = await client.request('tools/call', {
      name: 'ocw_route',
      arguments: { ...common, action: 'explain', mode: 'cheap' },
    });
    assert.equal(routeExplain.structuredContent.status, 0);
    assert.match(routeExplain.structuredContent.stdout, /opencode-go\/mcp-a/);
    const routeDoctor = await client.request('tools/call', {
      name: 'ocw_route',
      arguments: { ...common, action: 'doctor', cache: '.codex/models.json' },
    });
    assert.equal(routeDoctor.structuredContent.status, 0);
    assert.match(routeDoctor.structuredContent.stdout, /ocw\.route\.doctor\.v1/);

    const memoryAdd = await client.request('tools/call', {
      name: 'ocw_memory',
      arguments: { ...common, action: 'add', key: 'mcp', value: 'structured tools are available', tags: 'test' },
    });
    assert.equal(memoryAdd.structuredContent.status, 0);
    const memoryExport = await client.request('tools/call', {
      name: 'ocw_memory',
      arguments: { ...common, action: 'export' },
    });
    assert.equal(memoryExport.structuredContent.status, 0);
    assert.match(memoryExport.structuredContent.stdout, /ocw\.memory\.v1/);

    const dashboard = await client.request('tools/call', {
      name: 'ocw_dashboard',
      arguments: { ...common, json: true },
    });
    assert.equal(dashboard.structuredContent.status, 0);
    assert.match(dashboard.structuredContent.stdout, /ocw\.dashboard\.v1/);

    const delegated = await client.request('tools/call', {
      name: 'ocw_delegate',
      arguments: {
        ...common,
        mode: 'review',
        task: 'MCP delegate review pass',
      },
    });
    assert.equal(delegated.structuredContent.status, 0);
    assert.match(delegated.structuredContent.output_dir, /review$/);
    assert.match(delegated.structuredContent.stdout, /ocw\.delegate\.v1/);

    const verdict = await client.request('tools/call', {
      name: 'ocw_verdict',
      arguments: { ...common, ref: 'latest' },
    });
    assert.equal(verdict.structuredContent.status, 0);
    assert.match(verdict.structuredContent.stdout, /ocw\.verdict\.v1/);

    const savings = await client.request('tools/call', {
      name: 'ocw_savings',
      arguments: { ...common, days: 0 },
    });
    assert.equal(savings.structuredContent.status, 0);
    assert.match(savings.structuredContent.stdout, /ocw\.savings\.v1/);

    const backend = await client.request('tools/call', {
      name: 'ocw_backend',
      arguments: { ...common, action: 'list' },
    });
    assert.equal(backend.structuredContent.status, 0);
    assert.match(backend.structuredContent.stdout, /ocw\.backend\.v1/);

    const bridgeInstall = await client.request('tools/call', {
      name: 'ocw_bridge',
      arguments: { ...common, action: 'install', force: true },
    });
    assert.equal(bridgeInstall.structuredContent.status, 0);
    assert.ok(fs.existsSync(path.join(repo, '.codex/ocw-bridge/bin/oss-scout')));
    const bridgeOrchestration = await client.request('tools/call', {
      name: 'ocw_bridge',
      arguments: { ...common, action: 'orchestration-sync', force: true },
    });
    assert.equal(bridgeOrchestration.structuredContent.status, 0);
    assert.ok(fs.existsSync(path.join(repo, '.codex/ocw-bridge-orchestration/ROUTING.md')));

    const tournament = await client.request('tools/call', {
      name: 'ocw_tournament',
      arguments: {
        ...common,
        mode: 'cheap',
        task: 'MCP tournament smoke',
        models: 'opencode-go/mcp-a,opencode-go/mcp-b',
        judge_model: 'opencode-go/mcp-b',
      },
    });
    assert.equal(tournament.structuredContent.status, 0);
    assert.match(tournament.structuredContent.output_dir, /tournament$/);

    const mcpAudit = await client.request('tools/call', {
      name: 'ocw_mcp_audit',
      arguments: { ...common },
    });
    assert.equal(mcpAudit.structuredContent.status, 0);
    assert.match(mcpAudit.structuredContent.stdout, /ocw\.mcp\.audit\.v1/);

    const resources = await client.request('resources/list', {});
    assert.ok(resources.resources.some((resource) => resource.uri === 'ocw://latest/summary'));
    const summaryResource = await client.request('resources/read', { uri: 'ocw://latest/summary' });
    assert.match(summaryResource.contents[0].text, /MOCK_OK/);

    const prompts = await client.request('prompts/list', {});
    assert.ok(prompts.prompts.some((prompt) => prompt.name === 'ocw-patch-small'));
    const prompt = await client.request('prompts/get', {
      name: 'ocw-patch-small',
      arguments: { task: 'fix the small bug' },
    });
    assert.match(prompt.messages[0].content.text, /ocw --worktree patch/);

    const report = await client.request('tools/call', {
      name: 'ocw_report',
      arguments: { ...common, ref: 'latest', format: 'json' },
    });
    assert.equal(report.structuredContent.status, 0);
    assert.match(report.structuredContent.stdout, /"schema_version": "ocw\.report\.v1"/);

    fs.writeFileSync(path.join(repo, 'eval.ocw'), 'cheap|Return MOCK_OK for the eval|MOCK_OK\n');
    const evalRun = await client.request('tools/call', {
      name: 'ocw_eval',
      arguments: { ...common, file: 'eval.ocw', iterations: 1 },
    });
    assert.equal(evalRun.structuredContent.status, 0);
    assert.match(evalRun.structuredContent.output_dir, /eval$/);

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
      arguments: { ...common, allow_dirty: true },
    });
    assert.equal(check.structuredContent.status, 0);
    assert.match(check.structuredContent.stdout, /Patch can be applied/);

    const apply = await client.request('tools/call', {
      name: 'ocw_apply',
      arguments: { ...common, allow_dirty: true },
    });
    assert.equal(apply.structuredContent.status, 0);
    assert.match(fs.readFileSync(path.join(repo, 'tracked.txt'), 'utf8'), /mock edit from opencode-go\/mcp-a/);

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
