#!/usr/bin/env node
'use strict';

const childProcess = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const readline = require('node:readline');

const ROOT = path.resolve(__dirname, '..');
const DEFAULT_OCW = path.join(ROOT, 'bin', 'ocw');
const OCW_BIN = process.env.OCW_BIN || DEFAULT_OCW;
const DEFAULT_MAX_OUTPUT_CHARS = 20000;
const SUPPORTED_PROTOCOLS = ['2025-11-25', '2025-06-18', '2025-03-26', '2024-11-05'];

function ocwVersion() {
  const result = childProcess.spawnSync(OCW_BIN, ['version'], {
    encoding: 'utf8',
    env: process.env,
  });
  const text = (result.stdout || '').trim();
  return text.replace(/^ocw\s+/, '') || 'unknown';
}

const VERSION = ocwVersion();

function schema(properties, required = []) {
  return {
    type: 'object',
    properties,
    required,
    additionalProperties: false,
  };
}

const commonProperties = {
  cwd: {
    type: 'string',
    description: 'Working directory for the OCW command. Defaults to the MCP server process cwd.',
  },
  output_root: {
    type: 'string',
    description: 'OCW output root, equivalent to OCW_OUTPUT_ROOT.',
  },
  max_output_chars: {
    type: 'integer',
    minimum: 1000,
    maximum: 200000,
    description: 'Maximum stdout/stderr characters returned in the MCP result. Defaults to 20000.',
  },
};

const tools = [
  {
    name: 'ocw_run',
    description: 'Run an OCW worker mode and return its local artifact path. Use for cheap/explore/scan/review/patch delegation.',
    inputSchema: schema({
      ...commonProperties,
      mode: { type: 'string', enum: ['cheap', 'explore', 'scan', 'review', 'patch'] },
      task: { type: 'string', minLength: 1, description: 'Bounded worker task.' },
      model: { type: 'string', description: 'OpenCode model override.' },
      agent: { type: 'string', description: 'OpenCode agent override.' },
      variant: { type: 'string', description: 'OpenCode model variant.' },
      attach: { type: 'string', description: 'OpenCode server attach URL.' },
      files: { type: 'array', items: { type: 'string' }, description: 'Files to attach to the OpenCode prompt.' },
      auto_approve: { type: 'boolean', description: 'Pass OCW --auto-approve.' },
      require_clean: { type: 'boolean', description: 'Pass OCW --require-clean.' },
      worktree: { type: 'boolean', description: 'Run patch mode in an isolated worktree.' },
      rm_worktree: { type: 'boolean', description: 'Remove isolated patch worktree after capturing diff.' },
    }, ['mode', 'task']),
    annotations: { destructiveHint: true },
  },
  {
    name: 'ocw_last',
    description: 'Return the latest OCW run directory, optionally filtered by mode.',
    inputSchema: schema({
      ...commonProperties,
      mode: { type: 'string', enum: ['cheap', 'explore', 'scan', 'review', 'patch', 'bench', 'batch', 'pr-review', 'pr-summary'] },
    }),
    annotations: { readOnlyHint: true },
  },
  {
    name: 'ocw_show',
    description: 'Show a saved OCW artifact view such as summary, diff, status, metadata, jsonl, or path.',
    inputSchema: schema({
      ...commonProperties,
      ref: { type: 'string', description: 'Run directory, run basename, or latest. Defaults to latest.' },
      view: { type: 'string', enum: ['default', 'summary', 'diff', 'stat', 'status', 'metadata', 'jsonl', 'path'], description: 'Artifact view. Defaults to summary.' },
    }),
    annotations: { readOnlyHint: true },
  },
  {
    name: 'ocw_manifest',
    description: 'Return a machine-readable manifest for a saved OCW run, including metadata and artifact checksums.',
    inputSchema: schema({
      ...commonProperties,
      ref: { type: 'string', description: 'Run directory, run basename, or latest. Defaults to latest.' },
      json: { type: 'boolean', description: 'Return JSON output. Defaults to true.' },
    }),
    annotations: { readOnlyHint: true },
  },
  {
    name: 'ocw_audit',
    description: 'Audit a saved OCW run for failed workers, missing artifacts, unsafe patch isolation, large diffs, and prompt-injection markers.',
    inputSchema: schema({
      ...commonProperties,
      ref: { type: 'string', description: 'Run directory, run basename, or latest. Defaults to latest.' },
      json: { type: 'boolean', description: 'Return JSON output. Defaults to true.' },
      max_diff_bytes: {
        type: 'integer',
        minimum: 0,
        maximum: 100000000,
        description: 'Warn when diff.after.patch is larger than this many bytes. Defaults to OCW CLI default.',
      },
    }),
    annotations: { readOnlyHint: true },
  },
  {
    name: 'ocw_apply_check',
    description: 'Run `ocw apply --check` for a saved patch artifact. Does not modify files.',
    inputSchema: schema({
      ...commonProperties,
      ref: { type: 'string', description: 'Run directory, run basename, or latest. Defaults to latest patch.' },
      allow_dirty: { type: 'boolean' },
      force: { type: 'boolean', description: 'Allow checking non-worktree patch runs.' },
    }),
    annotations: { readOnlyHint: true },
  },
  {
    name: 'ocw_apply',
    description: 'Apply a saved OCW patch artifact with git apply. This can modify the working tree.',
    inputSchema: schema({
      ...commonProperties,
      ref: { type: 'string', description: 'Run directory, run basename, or latest. Defaults to latest patch.' },
      allow_dirty: { type: 'boolean' },
      force: { type: 'boolean', description: 'Allow applying non-worktree patch runs.' },
    }),
    annotations: { destructiveHint: true },
  },
  {
    name: 'ocw_stats',
    description: 'Run `ocw stats` and return OpenCode token/cost statistics output.',
    inputSchema: schema({
      ...commonProperties,
      args: { type: 'array', items: { type: 'string' }, description: 'Arguments passed to `ocw stats`, for example ["--days", "7", "--models", "10"].' },
    }),
    annotations: { readOnlyHint: true },
  },
];

function send(message) {
  process.stdout.write(`${JSON.stringify(message)}\n`);
}

function rpcResult(id, result) {
  send({ jsonrpc: '2.0', id, result });
}

function rpcError(id, code, message, data) {
  const error = { code, message };
  if (data !== undefined) {
    error.data = data;
  }
  send({ jsonrpc: '2.0', id, error });
}

function assertString(value, name, required = false) {
  if (value === undefined || value === null || value === '') {
    if (required) {
      throw new Error(`${name} is required`);
    }
    return undefined;
  }
  if (typeof value !== 'string') {
    throw new Error(`${name} must be a string`);
  }
  return value;
}

function assertBoolean(value, name) {
  if (value === undefined || value === null) {
    return false;
  }
  if (typeof value !== 'boolean') {
    throw new Error(`${name} must be a boolean`);
  }
  return value;
}

function assertStringArray(value, name) {
  if (value === undefined || value === null) {
    return [];
  }
  if (!Array.isArray(value) || value.some((item) => typeof item !== 'string')) {
    throw new Error(`${name} must be an array of strings`);
  }
  return value;
}

function commandCwd(args) {
  const cwd = assertString(args.cwd, 'cwd') || process.cwd();
  if (!fs.existsSync(cwd) || !fs.statSync(cwd).isDirectory()) {
    throw new Error(`cwd is not a directory: ${cwd}`);
  }
  return cwd;
}

function commandEnv(args) {
  const env = { ...process.env, OCW_MCP: '1' };
  const outputRoot = assertString(args.output_root, 'output_root');
  if (outputRoot) {
    env.OCW_OUTPUT_ROOT = outputRoot;
  }
  return env;
}

function maxOutputChars(args) {
  if (args.max_output_chars === undefined || args.max_output_chars === null) {
    return DEFAULT_MAX_OUTPUT_CHARS;
  }
  if (!Number.isInteger(args.max_output_chars) || args.max_output_chars < 1000 || args.max_output_chars > 200000) {
    throw new Error('max_output_chars must be an integer between 1000 and 200000');
  }
  return args.max_output_chars;
}

function truncate(text, limit) {
  const value = text || '';
  if (value.length <= limit) {
    return { text: value, truncated: false };
  }
  return {
    text: `${value.slice(0, limit)}\n[truncated ${value.length - limit} chars]`,
    truncated: true,
  };
}

function runOcw(ocwArgs, args) {
  const cwd = commandCwd(args);
  const env = commandEnv(args);
  const result = childProcess.spawnSync(OCW_BIN, ocwArgs, {
    cwd,
    env,
    encoding: 'utf8',
    maxBuffer: 50 * 1024 * 1024,
  });
  const limit = maxOutputChars(args);
  const stdout = truncate(result.stdout || '', limit);
  const stderr = truncate(result.stderr || '', limit);
  const status = result.status === null ? 1 : result.status;
  const outputDirMatch = (result.stdout || '').match(/OCW (?:output|benchmark output|batch output|PR [a-z]+ output): (.+)/);

  return {
    status,
    signal: result.signal,
    command: [OCW_BIN, ...ocwArgs],
    cwd,
    stdout: stdout.text,
    stderr: stderr.text,
    stdout_truncated: stdout.truncated,
    stderr_truncated: stderr.truncated,
    output_dir: outputDirMatch ? outputDirMatch[1].trim() : undefined,
  };
}

function toolResponse(name, result) {
  const lines = [
    `${name}: exit ${result.status}`,
    `cwd: ${result.cwd}`,
  ];
  if (result.output_dir) {
    lines.push(`output_dir: ${result.output_dir}`);
  }
  if (result.stdout.trim()) {
    lines.push('', 'stdout:', result.stdout.trimEnd());
  }
  if (result.stderr.trim()) {
    lines.push('', 'stderr:', result.stderr.trimEnd());
  }
  return {
    content: [{ type: 'text', text: lines.join('\n') }],
    structuredContent: result,
    isError: result.status !== 0,
  };
}

function callTool(name, args) {
  const input = args || {};
  let result;

  if (name === 'ocw_run') {
    const mode = assertString(input.mode, 'mode', true);
    const task = assertString(input.task, 'task', true);
    if (!['cheap', 'explore', 'scan', 'review', 'patch'].includes(mode)) {
      throw new Error(`unsupported mode: ${mode}`);
    }
    const ocwArgs = [];
    const flags = [
      ['model', '--model'],
      ['agent', '--agent'],
      ['variant', '--variant'],
      ['attach', '--attach'],
    ];
    for (const [key, flag] of flags) {
      const value = assertString(input[key], key);
      if (value) {
        ocwArgs.push(flag, value);
      }
    }
    for (const file of assertStringArray(input.files, 'files')) {
      ocwArgs.push('--file', file);
    }
    if (assertBoolean(input.auto_approve, 'auto_approve')) ocwArgs.push('--auto-approve');
    if (assertBoolean(input.require_clean, 'require_clean')) ocwArgs.push('--require-clean');
    if (assertBoolean(input.worktree, 'worktree')) ocwArgs.push('--worktree');
    if (assertBoolean(input.rm_worktree, 'rm_worktree')) ocwArgs.push('--rm-worktree');
    ocwArgs.push(mode, task);
    result = runOcw(ocwArgs, input);
    return toolResponse(name, result);
  }

  if (name === 'ocw_last') {
    const ocwArgs = ['last'];
    const mode = assertString(input.mode, 'mode');
    if (mode) ocwArgs.push(mode);
    result = runOcw(ocwArgs, input);
    return toolResponse(name, result);
  }

  if (name === 'ocw_show') {
    const ref = assertString(input.ref, 'ref') || 'latest';
    const view = assertString(input.view, 'view') || 'summary';
    const viewFlags = {
      default: undefined,
      summary: '--summary',
      diff: '--diff',
      stat: '--stat',
      status: '--status',
      metadata: '--metadata',
      jsonl: '--jsonl',
      path: '--path',
    };
    if (!(view in viewFlags)) {
      throw new Error(`unsupported view: ${view}`);
    }
    const ocwArgs = ['show', ref];
    if (viewFlags[view]) ocwArgs.push(viewFlags[view]);
    result = runOcw(ocwArgs, input);
    return toolResponse(name, result);
  }

  if (name === 'ocw_manifest') {
    const ref = assertString(input.ref, 'ref') || 'latest';
    const ocwArgs = ['manifest', ref];
    if (input.json !== false) ocwArgs.push('--json');
    result = runOcw(ocwArgs, input);
    return toolResponse(name, result);
  }

  if (name === 'ocw_audit') {
    const ref = assertString(input.ref, 'ref') || 'latest';
    const ocwArgs = ['audit', ref];
    if (input.json !== false) ocwArgs.push('--json');
    if (input.max_diff_bytes !== undefined && input.max_diff_bytes !== null) {
      if (!Number.isInteger(input.max_diff_bytes) || input.max_diff_bytes < 0 || input.max_diff_bytes > 100000000) {
        throw new Error('max_diff_bytes must be an integer between 0 and 100000000');
      }
      ocwArgs.push('--max-diff-bytes', String(input.max_diff_bytes));
    }
    result = runOcw(ocwArgs, input);
    return toolResponse(name, result);
  }

  if (name === 'ocw_apply_check' || name === 'ocw_apply') {
    const ocwArgs = ['apply'];
    const ref = assertString(input.ref, 'ref');
    if (ref) ocwArgs.push(ref);
    if (name === 'ocw_apply_check') ocwArgs.push('--check');
    if (assertBoolean(input.allow_dirty, 'allow_dirty')) ocwArgs.push('--allow-dirty');
    if (assertBoolean(input.force, 'force')) ocwArgs.push('--force');
    result = runOcw(ocwArgs, input);
    return toolResponse(name, result);
  }

  if (name === 'ocw_stats') {
    result = runOcw(['stats', ...assertStringArray(input.args, 'args')], input);
    return toolResponse(name, result);
  }

  throw new Error(`unknown tool: ${name}`);
}

function handleRequest(message) {
  const id = message.id;
  try {
    if (message.method === 'initialize') {
      const requested = message.params && message.params.protocolVersion;
      const protocolVersion = SUPPORTED_PROTOCOLS.includes(requested) ? requested : SUPPORTED_PROTOCOLS[0];
      rpcResult(id, {
        protocolVersion,
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: 'ocw-mcp', version: VERSION },
        instructions: 'Structured tools for OCW. Worker output is draft material; the client remains responsible for review and tests.',
      });
      return;
    }

    if (message.method === 'ping') {
      rpcResult(id, {});
      return;
    }

    if (message.method === 'tools/list') {
      rpcResult(id, { tools });
      return;
    }

    if (message.method === 'tools/call') {
      const params = message.params || {};
      const name = assertString(params.name, 'name', true);
      rpcResult(id, callTool(name, params.arguments || {}));
      return;
    }

    rpcError(id, -32601, `method not found: ${message.method}`);
  } catch (error) {
    rpcError(id, -32602, error.message);
  }
}

function handleMessage(message) {
  if (!message || message.jsonrpc !== '2.0') {
    rpcError(null, -32600, 'invalid JSON-RPC message');
    return;
  }
  if (Object.prototype.hasOwnProperty.call(message, 'id')) {
    handleRequest(message);
  }
}

const rl = readline.createInterface({
  input: process.stdin,
  crlfDelay: Infinity,
});

rl.on('line', (line) => {
  const trimmed = line.trim();
  if (!trimmed) return;
  try {
    const message = JSON.parse(trimmed);
    if (Array.isArray(message)) {
      for (const item of message) {
        handleMessage(item);
      }
    } else {
      handleMessage(message);
    }
  } catch (error) {
    rpcError(null, -32700, 'parse error', error.message);
  }
});
