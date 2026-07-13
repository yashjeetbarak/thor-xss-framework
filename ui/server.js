#!/usr/bin/env node
'use strict';

/**
 * Thor Workbench UI server.
 *
 * This server is intentionally thin. It does not reimplement Thor's scan
 * workflow; it only validates UI input, builds an explicit argv array, spawns
 * ../thor.sh, and streams stdout/stderr back to the browser.
 */

const http = require('http');
const fs = require('fs');
const fsp = require('fs/promises');
const path = require('path');
const { spawn } = require('child_process');
const crypto = require('crypto');
const os = require('os');

const UI_ROOT = __dirname;
const THOR_ROOT = path.resolve(UI_ROOT, '..');
const PUBLIC_DIR = path.join(UI_ROOT, 'public');
const THOR_BIN = path.join(THOR_ROOT, 'thor.sh');
const HOST = process.env.THOR_UI_HOST || '127.0.0.1';
const PORT = Number.parseInt(process.env.THOR_UI_PORT || '4173', 10);
const MAX_BODY_BYTES = 1024 * 256;
const MAX_BUFFERED_EVENTS = 2500;
const MAX_FILE_PREVIEW_BYTES = 1024 * 1024 * 2;

const runs = new Map();

const mime = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.svg': 'image/svg+xml; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.txt': 'text/plain; charset=utf-8',
  '.md': 'text/markdown; charset=utf-8',
  '.log': 'text/plain; charset=utf-8',
  '.env': 'text/plain; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg'
};

function json(res, status, data) {
  const body = JSON.stringify(data, null, 2);
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff'
  });
  res.end(body);
}

function text(res, status, body, type = 'text/plain; charset=utf-8') {
  res.writeHead(status, {
    'content-type': type,
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff'
  });
  res.end(body);
}

function notFound(res) {
  json(res, 404, { error: 'Not found' });
}

function safeRelativePath(candidate) {
  const resolved = path.resolve(THOR_ROOT, candidate || '.');
  if (resolved !== THOR_ROOT && !resolved.startsWith(`${THOR_ROOT}${path.sep}`)) {
    throw new Error('Path is outside Thor project root.');
  }
  return resolved;
}

function isSafeDomain(value) {
  return typeof value === 'string' && /^[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/.test(value.trim()) && !value.includes('..');
}

function normalizeLineBuffer(textValue) {
  return textValue.replace(/\r/g, '\n').split('\n');
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let total = 0;
    const chunks = [];
    req.on('data', chunk => {
      total += chunk.length;
      if (total > MAX_BODY_BYTES) {
        reject(new Error('Request body too large.'));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => {
      const body = Buffer.concat(chunks).toString('utf8');
      if (!body) return resolve({});
      try {
        resolve(JSON.parse(body));
      } catch (error) {
        reject(new Error(`Invalid JSON: ${error.message}`));
      }
    });
    req.on('error', reject);
  });
}

function pushEvent(run, type, payload) {
  const event = {
    id: crypto.randomUUID(),
    type,
    time: new Date().toISOString(),
    ...payload
  };
  run.events.push(event);
  if (run.events.length > MAX_BUFFERED_EVENTS) {
    run.events.splice(0, run.events.length - MAX_BUFFERED_EVENTS);
  }
  for (const client of run.clients) {
    client.write(`event: ${type}\n`);
    client.write(`data: ${JSON.stringify(event)}\n\n`);
  }
}

function readConfigSnapshot() {
  const configPath = path.join(THOR_ROOT, 'config.conf');
  const config = {};
  try {
    const content = fs.readFileSync(configPath, 'utf8');
    for (const line of content.split(/\r?\n/)) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('#')) continue;
      const match = trimmed.match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/);
      if (!match) continue;
      config[match[1]] = match[2].replace(/^['"]|['"]$/g, '');
    }
  } catch {
    // Thor CLI remains source of truth; config display is best-effort.
  }
  return config;
}

function safeShellPreview(args) {
  return ['thor', ...args].map(part => {
    if (/^[A-Za-z0-9_./:=@+-]+$/.test(part)) return part;
    return `'${String(part).replace(/'/g, `'"'"'`)}'`;
  }).join(' ');
}

function addIntegerFlag(args, options, key, flag) {
  const value = options[key];
  if (value !== undefined && value !== null && String(value).trim() !== '') {
    if (!/^\d+$/.test(String(value))) throw new Error(`${key} must be a number.`);
    args.push(flag, String(value));
  }
}

function addStringFlag(args, options, key, flag) {
  const value = typeof options[key] === 'string' ? options[key].trim() : '';
  if (value) args.push(flag, value);
}

function buildScanArgs(body) {
  const args = ['scan'];
  const options = body.options || {};
  const target = typeof body.target === 'string' ? body.target.trim() : '';
  const listPath = typeof body.listPath === 'string' ? body.listPath.trim() : '';

  if (!body.authorized) {
    throw new Error('Authorization confirmation is required before starting a browser scan.');
  }

  if (listPath) {
    args.push('-l', safeRelativePath(listPath));
  } else {
    if (!isSafeDomain(target)) throw new Error('Enter a valid authorized domain, for example example.com.');
    args.push(target);
  }

  args.push('--authorized');

  addIntegerFlag(args, options, 'workers', '--dalfox-workers');
  addIntegerFlag(args, options, 'timeout', '--dalfox-timeout');
  addIntegerFlag(args, options, 'delay', '--dalfox-delay');
  addIntegerFlag(args, options, 'batchSize', '--dalfox-batch-size');
  addIntegerFlag(args, options, 'retries', '--dalfox-retries');
  addIntegerFlag(args, options, 'threads', '--threads');
  addIntegerFlag(args, options, 'httpxThreads', '--httpx-threads');
  addIntegerFlag(args, options, 'paramspiderThreads', '--paramspider-threads');

  if (options.safeDalfox) args.push('--dalfox-workers-safe');
  if (options.disableHttpx) args.push('--no-httpx');
  if (options.disableGau) args.push('--no-gau');
  if (options.disableWaymore) args.push('--no-waymore');
  if (options.disableKatana) args.push('--no-katana');
  if (options.disableDalfoxPrecheck) args.push('--no-dalfox-precheck-live');
  if (options.rawJson) args.push('--dalfox-raw-json');
  if (options.disableScopeOnly) args.push('--dalfox-no-scope-only');
  if (options.verbose) args.push('--verbose');
  if (options.debug) args.push('--debug');

  addStringFlag(args, options, 'proxy', '--proxy');
  addStringFlag(args, options, 'userAgent', '--user-agent');
  addStringFlag(args, options, 'method', '--dalfox-method');
  addStringFlag(args, options, 'payloadFile', '--dalfox-payload-file');

  const cookie = typeof options.cookie === 'string' ? options.cookie.trim() : '';
  if (cookie) args.push('--cookie', cookie);

  const headers = typeof options.headers === 'string' ? options.headers.split(/\r?\n/).map(v => v.trim()).filter(Boolean) : [];
  for (const header of headers) args.push('--header', header);

  return args;
}

function buildArgs(body) {
  const command = body.command;
  switch (command) {
    case 'scan':
      return buildScanArgs(body);
    case 'doctor':
      return ['doctor'];
    case 'history':
      return ['history'];
    case 'version':
      return ['--version'];
    case 'resume': {
      const scanDir = typeof body.scanDir === 'string' && body.scanDir.trim() ? safeRelativePath(body.scanDir.trim()) : undefined;
      return scanDir ? ['resume', scanDir] : ['resume'];
    }
    case 'report': {
      const scanDir = typeof body.scanDir === 'string' && body.scanDir.trim() ? safeRelativePath(body.scanDir.trim()) : undefined;
      return scanDir ? ['report', scanDir] : ['report'];
    }
    case 'clean':
      return ['clean'];
    default:
      throw new Error('Unsupported command.');
  }
}

function startRun(body) {
  const args = buildArgs(body);
  const id = crypto.randomUUID().slice(0, 12);
  const run = {
    id,
    command: body.command,
    args,
    preview: safeShellPreview(args),
    status: 'running',
    exitCode: null,
    startedAt: new Date().toISOString(),
    endedAt: null,
    cwd: THOR_ROOT,
    events: [],
    clients: new Set(),
    child: null
  };
  runs.set(id, run);

  const env = {
    ...process.env,
    THOR_ASSUME_AUTHORIZED: body.authorized ? 'true' : process.env.THOR_ASSUME_AUTHORIZED || 'false',
    FORCE_COLOR: '0'
  };

  const child = spawn('bash', [THOR_BIN, ...args], {
    cwd: THOR_ROOT,
    env,
    stdio: ['ignore', 'pipe', 'pipe']
  });
  run.child = child;
  pushEvent(run, 'start', { message: `bash ${path.basename(THOR_BIN)} ${args.join(' ')}`, preview: run.preview });

  const attach = (streamName, stream) => {
    let remainder = '';
    stream.on('data', chunk => {
      const raw = remainder + chunk.toString('utf8');
      const parts = normalizeLineBuffer(raw);
      remainder = parts.pop() || '';
      for (const line of parts) {
        if (line.trim() !== '') pushEvent(run, 'line', { stream: streamName, line });
      }
    });
    stream.on('end', () => {
      if (remainder.trim() !== '') pushEvent(run, 'line', { stream: streamName, line: remainder });
    });
  };

  attach('stdout', child.stdout);
  attach('stderr', child.stderr);

  child.on('error', error => {
    run.status = 'failed';
    run.endedAt = new Date().toISOString();
    pushEvent(run, 'error', { message: error.message });
  });

  child.on('close', code => {
    run.exitCode = code;
    run.status = code === 0 ? 'completed' : 'failed';
    run.endedAt = new Date().toISOString();
    pushEvent(run, 'done', { exitCode: code, status: run.status });
    for (const client of run.clients) client.end();
    run.clients.clear();
  });

  return run;
}

function publicRun(run) {
  return {
    id: run.id,
    command: run.command,
    args: run.args,
    preview: run.preview,
    status: run.status,
    exitCode: run.exitCode,
    startedAt: run.startedAt,
    endedAt: run.endedAt,
    cwd: run.cwd,
    eventCount: run.events.length
  };
}

async function readReportSummary(scanDir) {
  try {
    const reportJson = JSON.parse(await fsp.readFile(path.join(scanDir, 'report.json'), 'utf8'));
    return reportJson.statistics || reportJson.summary || null;
  } catch {
    return null;
  }
}

async function listHistory() {
  const resultsDir = path.join(THOR_ROOT, 'results');
  const entries = [];
  try {
    const domains = await fsp.readdir(resultsDir, { withFileTypes: true });
    for (const domain of domains) {
      if (!domain.isDirectory()) continue;
      const domainDir = path.join(resultsDir, domain.name);
      const scans = await fsp.readdir(domainDir, { withFileTypes: true });
      for (const scan of scans) {
        if (!scan.isDirectory()) continue;
        const scanDir = path.join(domainDir, scan.name);
        const stat = await fsp.stat(scanDir);
        const summary = await readReportSummary(scanDir);
        entries.push({ domain: domain.name, scan: scan.name, path: scanDir, modifiedAt: stat.mtime.toISOString(), summary });
      }
    }
  } catch {
    return [];
  }
  return entries.sort((a, b) => b.modifiedAt.localeCompare(a.modifiedAt)).slice(0, 75);
}

async function listFiles(scanDir) {
  const dir = safeRelativePath(scanDir);
  const stat = await fsp.stat(dir);
  if (!stat.isDirectory()) throw new Error('Scan path is not a directory.');
  const allowed = new Set([
    'report.txt', 'report.json', 'report.html', 'logs.txt', 'subdomains.txt', 'live_hosts.txt',
    'allparams.txt', 'single_param_urls.txt', 'single_param_urls.skipped.txt', 'dalfox_input.txt',
    'dalfox_input_live.txt', 'dalfox_skipped_urls.txt', 'dalfox_unreachable_urls.txt', 'dalfox_result.txt',
    'dalfox_result.json', 'dalfox_error.log', 'state.env'
  ]);
  const files = [];
  for (const entry of await fsp.readdir(dir, { withFileTypes: true })) {
    if (!entry.isFile() || !allowed.has(entry.name)) continue;
    const filePath = path.join(dir, entry.name);
    const fileStat = await fsp.stat(filePath);
    files.push({ name: entry.name, path: filePath, size: fileStat.size, modifiedAt: fileStat.mtime.toISOString() });
  }
  return files.sort((a, b) => a.name.localeCompare(b.name));
}

async function serveStatic(req, res, pathname) {
  let filePath = pathname === '/' ? path.join(PUBLIC_DIR, 'index.html') : path.join(PUBLIC_DIR, pathname.replace(/^\//, ''));
  filePath = path.resolve(filePath);
  if (!filePath.startsWith(`${PUBLIC_DIR}${path.sep}`) && filePath !== path.join(PUBLIC_DIR, 'index.html')) {
    return notFound(res);
  }
  try {
    const stat = await fsp.stat(filePath);
    if (!stat.isFile()) return notFound(res);
    const ext = path.extname(filePath).toLowerCase();
    res.writeHead(200, {
      'content-type': mime[ext] || 'application/octet-stream',
      'cache-control': 'no-store',
      'x-content-type-options': 'nosniff'
    });
    fs.createReadStream(filePath).pipe(res);
  } catch {
    notFound(res);
  }
}

async function serveDownload(res, requested) {
  const filePath = safeRelativePath(requested || '');
  const stat = await fsp.stat(filePath);
  if (!stat.isFile()) return notFound(res);
  res.writeHead(200, {
    'content-type': mime[path.extname(filePath).toLowerCase()] || 'application/octet-stream',
    'content-disposition': `attachment; filename="${path.basename(filePath).replace(/"/g, '')}"`,
    'content-length': stat.size,
    'x-content-type-options': 'nosniff'
  });
  fs.createReadStream(filePath).pipe(res);
}

async function router(req, res) {
  const parsed = new URL(req.url, `http://${req.headers.host || `${HOST}:${PORT}`}`);
  const pathname = parsed.pathname;

  try {
    if (req.method === 'GET' && pathname === '/api/health') {
      return json(res, 200, { ok: true, name: 'Thor Command Deck', version: '1.4.0', time: new Date().toISOString() });
    }

    if (req.method === 'GET' && pathname === '/api/metadata') {
      return json(res, 200, {
        name: 'Thor Command Deck',
        version: '1.4.0',
        thorRoot: THOR_ROOT,
        platform: os.platform(),
        node: process.version,
        config: readConfigSnapshot(),
        commands: ['scan', 'doctor', 'history', 'resume', 'report', 'clean', 'version']
      });
    }

    if (req.method === 'POST' && pathname === '/api/preview') {
      const body = await readBody(req);
      const args = buildArgs(body);
      return json(res, 200, { args, preview: safeShellPreview(args) });
    }

    if (req.method === 'POST' && pathname === '/api/run') {
      const body = await readBody(req);
      const run = startRun(body);
      return json(res, 201, publicRun(run));
    }

    if (req.method === 'GET' && pathname === '/api/runs') {
      return json(res, 200, Array.from(runs.values()).map(publicRun).reverse());
    }

    const runMatch = pathname.match(/^\/api\/runs\/([^/]+)$/);
    if (req.method === 'GET' && runMatch) {
      const run = runs.get(runMatch[1]);
      if (!run) return notFound(res);
      return json(res, 200, { ...publicRun(run), events: run.events });
    }

    const eventMatch = pathname.match(/^\/api\/runs\/([^/]+)\/events$/);
    if (req.method === 'GET' && eventMatch) {
      const run = runs.get(eventMatch[1]);
      if (!run) return notFound(res);
      res.writeHead(200, {
        'content-type': 'text/event-stream; charset=utf-8',
        'cache-control': 'no-store',
        connection: 'keep-alive',
        'x-content-type-options': 'nosniff'
      });
      run.clients.add(res);
      for (const event of run.events) {
        res.write(`event: ${event.type}\n`);
        res.write(`data: ${JSON.stringify(event)}\n\n`);
      }
      req.on('close', () => run.clients.delete(res));
      return;
    }

    const stopMatch = pathname.match(/^\/api\/runs\/([^/]+)\/stop$/);
    if (req.method === 'POST' && stopMatch) {
      const run = runs.get(stopMatch[1]);
      if (!run) return notFound(res);
      if (run.child && run.status === 'running') {
        run.child.kill('SIGINT');
        setTimeout(() => {
          if (run.child && run.status === 'running') run.child.kill('SIGTERM');
        }, 3500).unref();
        pushEvent(run, 'line', { stream: 'stderr', line: 'Stop requested from Thor Workbench UI.' });
      }
      return json(res, 200, publicRun(run));
    }

    if (req.method === 'GET' && pathname === '/api/history') {
      return json(res, 200, await listHistory());
    }

    if (req.method === 'GET' && pathname === '/api/files') {
      return json(res, 200, await listFiles(parsed.searchParams.get('scanDir') || ''));
    }

    if (req.method === 'GET' && pathname === '/api/file') {
      const requested = safeRelativePath(parsed.searchParams.get('path') || '');
      const stat = await fsp.stat(requested);
      if (!stat.isFile()) return notFound(res);
      if (stat.size > MAX_FILE_PREVIEW_BYTES) {
        return text(res, 200, `File is ${stat.size} bytes. Use Download for the full file.`, 'text/plain; charset=utf-8');
      }
      const content = await fsp.readFile(requested, 'utf8');
      return text(res, 200, content, mime[path.extname(requested).toLowerCase()] || 'text/plain; charset=utf-8');
    }

    if (req.method === 'GET' && pathname === '/api/download') {
      return serveDownload(res, parsed.searchParams.get('path') || '');
    }

    if (req.method === 'GET') return serveStatic(req, res, pathname);
    json(res, 405, { error: 'Method not allowed' });
  } catch (error) {
    json(res, 400, { error: error.message });
  }
}

const server = http.createServer((req, res) => {
  router(req, res).catch(error => json(res, 500, { error: error.message }));
});

server.listen(PORT, HOST, () => {
  console.log(`Thor Workbench UI running at http://${HOST}:${PORT}`);
  console.log(`Thor root: ${THOR_ROOT}`);
  console.log('The CLI remains the source of truth. Close this process to stop the UI server.');
});
