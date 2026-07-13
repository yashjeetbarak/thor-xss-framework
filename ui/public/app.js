'use strict';

const $ = selector => document.querySelector(selector);
const $$ = selector => Array.from(document.querySelectorAll(selector));

const els = {
  connectionState: $('#connectionState'),
  healthMeta: $('#healthMeta'),
  statusDot: $('#statusDot'),
  runStatus: $('#runStatus'),
  runTime: $('#runTime'),
  progressBar: $('#progressBar'),
  console: $('#console'),
  consoleSearch: $('#consoleSearch'),
  historySearch: $('#historySearch'),
  runButton: $('#runButton'),
  stopButton: $('#stopButton'),
  copyOutputButton: $('#copyOutputButton'),
  copyCommandButton: $('#copyCommandButton'),
  clearConsole: $('#clearConsole'),
  doctorButton: $('#doctorButton'),
  versionButton: $('#versionButton'),
  versionButtonTop: $('#versionButtonTop'),
  refreshHistory: $('#refreshHistory'),
  refreshFiles: $('#refreshFiles'),
  historyList: $('#historyList'),
  selectedRun: $('#selectedRun'),
  summaryCards: $('#summaryCards'),
  fileList: $('#fileList'),
  fileViewer: $('#fileViewer'),
  viewerTitle: $('#viewerTitle'),
  copyFileButton: $('#copyFileButton'),
  downloadFileButton: $('#downloadFileButton'),
  settingsGrid: $('#settingsGrid'),
  toast: $('#toast'),
  metaStatus: $('#metaStatus'),
  metaRunId: $('#metaRunId'),
  metaCommand: $('#metaCommand'),
  metaStarted: $('#metaStarted'),
  metaExit: $('#metaExit'),
  activeRunLabel: $('#activeRunLabel'),
  recentFiles: $('#recentFiles'),
  target: $('#target'),
  commandPreview: $('#commandPreview'),
  metricProgress: $('#metricProgress'),
  metricSubdomains: $('#metricSubdomains'),
  metricUrls: $('#metricUrls'),
  metricFindings: $('#metricFindings'),
  themeToggle: $('#themeToggle')
};

const state = {
  activeRun: null,
  activeSource: null,
  startedAt: null,
  timer: null,
  consoleLines: [],
  streamFilter: 'all',
  selectedScanDir: null,
  selectedFilePath: null,
  selectedFileContent: '',
  history: [],
  metrics: { progress: 0, subdomains: null, urls: null, findings: null }
};

function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, char => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
  }[char]));
}

function fmtBytes(bytes) {
  const n = Number(bytes || 0);
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / 1024 / 1024).toFixed(1)} MB`;
}

function toast(message) {
  els.toast.textContent = message;
  els.toast.classList.add('show');
  window.clearTimeout(toast._timer);
  toast._timer = window.setTimeout(() => els.toast.classList.remove('show'), 3200);
}

async function api(path, options = {}) {
  const response = await fetch(path, {
    headers: { 'content-type': 'application/json' },
    ...options
  });
  const type = response.headers.get('content-type') || '';
  const data = type.includes('application/json') ? await response.json() : await response.text();
  if (!response.ok) {
    throw new Error(typeof data === 'object' ? (data.error || JSON.stringify(data)) : data);
  }
  return data;
}

function setStatus(status, label) {
  els.runStatus.textContent = label;
  els.metaStatus.textContent = label;
  els.connectionState.textContent = label;
  els.statusDot.className = 'status-dot';
  if (status === 'running') els.statusDot.classList.add('running');
  else if (status === 'completed') els.statusDot.classList.add('done');
  else if (status === 'failed') els.statusDot.classList.add('error');
  else els.statusDot.classList.add('idle');
}

function updateClock() {
  if (!state.startedAt) return;
  const seconds = Math.floor((Date.now() - state.startedAt) / 1000);
  const mm = String(Math.floor(seconds / 60)).padStart(2, '0');
  const ss = String(seconds % 60).padStart(2, '0');
  els.runTime.textContent = `${mm}:${ss}`;
}

function resetMetrics() {
  state.metrics = { progress: 0, subdomains: null, urls: null, findings: null };
  renderMetrics();
}

function renderMetrics() {
  els.metricProgress.textContent = `${state.metrics.progress || 0}%`;
  els.metricSubdomains.textContent = state.metrics.subdomains ?? '—';
  els.metricUrls.textContent = state.metrics.urls ?? '—';
  els.metricFindings.textContent = state.metrics.findings ?? '—';
  els.progressBar.style.width = `${Math.max(3, Math.min(100, state.metrics.progress || 0))}%`;
}

function parseMetrics(line) {
  const progress = line.match(/\[(\d{1,3})%\]/);
  if (progress) state.metrics.progress = Math.min(100, Number(progress[1]));

  const subdomains = line.match(/Subdomains(?: Found)?[:=]\s*(\d+)/i) || line.match(/Subdomains=(\d+)/i);
  if (subdomains) state.metrics.subdomains = Number(subdomains[1]);

  const urls = line.match(/URLs(?: Found| Scanned| Loaded)?[:=]\s*(\d+)/i) || line.match(/URLs=(\d+)/i);
  if (urls) state.metrics.urls = Number(urls[1]);

  const findings = line.match(/Dalfox Findings[:=]\s*(\d+)/i) || line.match(/Vulnerabilities Found[:=]\s*(\d+)/i);
  if (findings) state.metrics.findings = Number(findings[1]);

  renderMetrics();
}

function addConsoleLine(stream, line) {
  parseMetrics(line);
  state.consoleLines.push({ stream, line, time: new Date().toLocaleTimeString() });
  if (state.consoleLines.length > 2200) state.consoleLines.shift();
  renderConsole();
}

function renderConsole() {
  const query = els.consoleSearch.value.trim().toLowerCase();
  const filtered = state.consoleLines.filter(item => {
    if (state.streamFilter !== 'all' && item.stream !== state.streamFilter) return false;
    return !query || item.line.toLowerCase().includes(query);
  });
  els.console.innerHTML = filtered.map(item => {
    const cls = item.stream === 'stderr' ? 'stderr' : item.stream === 'system' ? 'system' : 'stdout';
    return `<span class="${cls}">[${escapeHtml(item.time)}] ${escapeHtml(item.line)}</span>`;
  }).join('\n');
  els.console.scrollTop = els.console.scrollHeight;
}

function resetRunUi() {
  resetMetrics();
  els.metaExit.textContent = '—';
  els.metaRunId.textContent = '—';
  els.metaCommand.textContent = '—';
  els.metaStarted.textContent = '—';
  els.activeRunLabel.textContent = 'No active run';
}

function applyPreset(name) {
  const presets = {
    quick: { workers: '15', timeout: '5', batchSize: '150', retries: '1', delay: '0', safeDalfox: true, verbose: false, disableGau: true, disableWaymore: true, disableKatana: false },
    balanced: { workers: '25', timeout: '8', batchSize: '250', retries: '1', delay: '0', safeDalfox: true, verbose: false, disableGau: false, disableWaymore: false, disableKatana: false },
    deep: { workers: '35', timeout: '10', batchSize: '300', retries: '2', delay: '0', safeDalfox: false, verbose: true, disableGau: false, disableWaymore: false, disableKatana: false }
  };
  const p = presets[name] || presets.balanced;
  $('#workers').value = p.workers;
  $('#timeout').value = p.timeout;
  $('#batchSize').value = p.batchSize;
  $('#retries').value = p.retries;
  $('#delay').value = p.delay;
  $('#safeDalfox').checked = p.safeDalfox;
  $('#verbose').checked = p.verbose;
  $('#disableGau').checked = p.disableGau;
  $('#disableWaymore').checked = p.disableWaymore;
  $('#disableKatana').checked = p.disableKatana;
  $$('.preset').forEach(btn => btn.classList.toggle('active', btn.dataset.preset === name));
  updateCommandPreview();
  toast(`${name[0].toUpperCase()}${name.slice(1)} preset applied.`);
}

function formPayload() {
  return {
    command: 'scan',
    target: els.target.value.trim(),
    authorized: $('#authorized').checked,
    options: {
      workers: $('#workers').value.trim(),
      timeout: $('#timeout').value.trim(),
      delay: $('#delay').value.trim(),
      batchSize: $('#batchSize').value.trim(),
      retries: $('#retries').value.trim(),
      userAgent: $('#userAgent').value.trim(),
      proxy: $('#proxy').value.trim(),
      cookie: $('#cookie').value.trim(),
      method: $('#method').value.trim(),
      payloadFile: $('#payloadFile').value.trim(),
      headers: $('#headers').value,
      safeDalfox: $('#safeDalfox').checked,
      rawJson: $('#rawJson').checked,
      disableScopeOnly: !$('#scopeOnly').checked,
      disableDalfoxPrecheck: $('#disableDalfoxPrecheck').checked,
      verbose: $('#verbose').checked,
      disableGau: $('#disableGau').checked,
      disableWaymore: $('#disableWaymore').checked,
      disableKatana: $('#disableKatana').checked
    }
  };
}

function savePreferences() {
  const prefs = formPayload();
  delete prefs.authorized;
  localStorage.setItem('thorWorkbenchPrefs', JSON.stringify(prefs));
}

function loadPreferences() {
  try {
    const prefs = JSON.parse(localStorage.getItem('thorWorkbenchPrefs') || '{}');
    if (prefs.target) els.target.value = prefs.target;
    const o = prefs.options || {};
    for (const [key, id] of Object.entries({ workers: 'workers', timeout: 'timeout', delay: 'delay', batchSize: 'batchSize', retries: 'retries', userAgent: 'userAgent', proxy: 'proxy', cookie: 'cookie', method: 'method', payloadFile: 'payloadFile', headers: 'headers' })) {
      if (o[key] !== undefined && $(`#${id}`)) $(`#${id}`).value = o[key];
    }
    for (const [key, id] of Object.entries({ safeDalfox: 'safeDalfox', rawJson: 'rawJson', disableDalfoxPrecheck: 'disableDalfoxPrecheck', verbose: 'verbose', disableGau: 'disableGau', disableWaymore: 'disableWaymore', disableKatana: 'disableKatana' })) {
      if (o[key] !== undefined && $(`#${id}`)) $(`#${id}`).checked = !!o[key];
    }
    if (o.disableScopeOnly !== undefined) $('#scopeOnly').checked = !o.disableScopeOnly;
  } catch {
    // Ignore invalid local storage.
  }
}

async function updateCommandPreview() {
  try {
    const payload = { ...formPayload(), authorized: true };
    if (!payload.target) payload.target = 'example.com';
    const preview = await api('/api/preview', { method: 'POST', body: JSON.stringify(payload) });
    els.commandPreview.textContent = preview.preview;
  } catch {
    els.commandPreview.textContent = 'Complete the form to preview the command.';
  }
}

async function startRun(payload) {
  if (state.activeSource) state.activeSource.close();
  state.consoleLines = [];
  renderConsole();
  resetRunUi();
  setStatus('running', 'Starting');
  els.runButton.disabled = true;
  els.stopButton.disabled = false;

  const run = await api('/api/run', { method: 'POST', body: JSON.stringify(payload) });
  state.activeRun = run;
  state.startedAt = new Date(run.startedAt).getTime();
  els.metaRunId.textContent = run.id;
  els.metaCommand.textContent = run.preview || `thor ${run.args.join(' ')}`;
  els.metaStarted.textContent = new Date(run.startedAt).toLocaleString();
  els.activeRunLabel.textContent = payload.command === 'scan' ? (payload.target || 'domain list scan') : payload.command;
  els.healthMeta.textContent = run.preview || 'Thor command started';
  state.timer = setInterval(updateClock, 1000);

  const source = new EventSource(`/api/runs/${run.id}/events`);
  state.activeSource = source;
  source.addEventListener('start', event => {
    const data = JSON.parse(event.data);
    addConsoleLine('system', `▶ ${data.preview || data.message}`);
    setStatus('running', 'Running');
  });
  source.addEventListener('line', event => {
    const data = JSON.parse(event.data);
    addConsoleLine(data.stream, data.line);
  });
  source.addEventListener('error', event => {
    if (event.data) {
      const data = JSON.parse(event.data);
      addConsoleLine('stderr', data.message);
    }
  });
  source.addEventListener('done', event => {
    const data = JSON.parse(event.data);
    setStatus(data.status, data.status === 'completed' ? 'Completed' : 'Failed');
    els.metaExit.textContent = String(data.exitCode);
    if (data.status === 'completed') {
      state.metrics.progress = 100;
      renderMetrics();
    }
    els.runButton.disabled = false;
    els.stopButton.disabled = true;
    source.close();
    clearInterval(state.timer);
    loadHistory();
    toast(data.status === 'completed' ? 'Thor run completed.' : 'Thor run failed. Check console output.');
  });
  source.onerror = () => {
    if (state.activeRun && state.activeRun.status === 'running') {
      addConsoleLine('stderr', 'Connection to UI event stream was interrupted. The CLI process may still be running.');
    }
  };
}

async function stopRun() {
  if (!state.activeRun) return;
  try {
    await api(`/api/runs/${state.activeRun.id}/stop`, { method: 'POST', body: '{}' });
    toast('Stop requested. Thor will save partial state if possible.');
  } catch (error) {
    toast(error.message);
  }
}

function historyStats(item) {
  const s = item.summary || {};
  return [
    `Subdomains ${s.subdomains ?? s.subdomains_found ?? 0}`,
    `URLs ${s.all_urls ?? s.urls ?? s.urls_collected ?? 0}`,
    `Findings ${s.vulnerabilities_found ?? s.dalfox_findings ?? 0}`
  ].join(' · ');
}

async function loadHistory() {
  state.history = await api('/api/history');
  renderHistory();
}

function renderHistory() {
  const query = (els.historySearch?.value || '').trim().toLowerCase();
  const items = state.history.filter(item => !query || `${item.domain} ${item.scan}`.toLowerCase().includes(query));
  if (!items.length) {
    els.historyList.innerHTML = '<div class="empty-state">No matching scan history yet.</div>';
    return;
  }
  els.historyList.innerHTML = items.map(item => `
    <button class="history-item" data-path="${escapeHtml(item.path)}">
      <span class="history-domain">${escapeHtml(item.domain)}</span>
      <strong>${escapeHtml(item.scan)}</strong>
      <small>${escapeHtml(new Date(item.modifiedAt).toLocaleString())}</small>
      <em>${escapeHtml(historyStats(item))}</em>
    </button>`).join('');
  $$('#historyList .history-item').forEach(button => {
    button.addEventListener('click', () => selectScan(button.dataset.path));
  });
}

function summaryValue(summary, keys) {
  for (const key of keys) if (summary && summary[key] !== undefined) return summary[key];
  return '—';
}

async function renderSummary(scanDir) {
  try {
    const report = await fetch(`/api/file?path=${encodeURIComponent(`${scanDir}/report.json`)}`).then(r => r.ok ? r.json() : null);
    const stats = report?.statistics || report?.summary || {};
    els.summaryCards.innerHTML = [
      ['Subdomains', summaryValue(stats, ['subdomains', 'subdomains_found'])],
      ['Live Hosts', summaryValue(stats, ['live_hosts', 'live_hosts_found'])],
      ['URLs', summaryValue(stats, ['all_urls', 'urls', 'urls_collected'])],
      ['Findings', summaryValue(stats, ['vulnerabilities_found', 'dalfox_findings'])]
    ].map(([label, value]) => `<div class="summary-card"><span>${label}</span><strong>${escapeHtml(value)}</strong></div>`).join('');
  } catch {
    els.summaryCards.innerHTML = '';
  }
}

async function selectScan(scanDir) {
  state.selectedScanDir = scanDir;
  els.selectedRun.textContent = scanDir;
  switchPanel('reports');
  await renderSummary(scanDir);
  await loadFiles();
}

async function loadFiles() {
  if (!state.selectedScanDir) return;
  const files = await api(`/api/files?scanDir=${encodeURIComponent(state.selectedScanDir)}`);
  if (!files.length) {
    els.fileList.innerHTML = '<div class="empty-state">No generated files found for this scan.</div>';
    els.recentFiles.textContent = 'No files found.';
    return;
  }
  els.fileList.innerHTML = files.map(file => `
    <button class="file-item" data-path="${escapeHtml(file.path)}" data-name="${escapeHtml(file.name)}">
      <strong>${escapeHtml(file.name)}</strong>
      <span>${fmtBytes(file.size)} · ${escapeHtml(new Date(file.modifiedAt).toLocaleString())}</span>
    </button>`).join('');
  els.recentFiles.innerHTML = files.slice(0, 8).map(file => `<div>${escapeHtml(file.name)} <small>${fmtBytes(file.size)}</small></div>`).join('');
  $$('#fileList .file-item').forEach(button => {
    button.addEventListener('click', () => openFile(button.dataset.path, button.dataset.name));
  });
}

async function openFile(filePath, name) {
  state.selectedFilePath = filePath;
  const content = await fetch(`/api/file?path=${encodeURIComponent(filePath)}`).then(async response => {
    if (!response.ok) throw new Error((await response.json()).error || 'Could not read file.');
    return response.text();
  });
  state.selectedFileContent = content;
  els.viewerTitle.textContent = name;
  if (name.endsWith('.json')) {
    try {
      els.fileViewer.textContent = JSON.stringify(JSON.parse(content), null, 2);
    } catch {
      els.fileViewer.textContent = content;
    }
  } else {
    els.fileViewer.textContent = content;
  }
}

function switchPanel(panel) {
  $$('.nav-item').forEach(button => {
    const active = button.dataset.panel === panel;
    button.classList.toggle('active', active);
    button.setAttribute('aria-pressed', String(active));
  });
  $$('.panel').forEach(item => item.classList.toggle('active', item.id === `panel-${panel}`));
}

async function loadMetadata() {
  const meta = await api('/api/metadata');
  els.healthMeta.textContent = `${meta.platform} · Node ${meta.node}`;
  const configEntries = Object.entries(meta.config || {}).slice(0, 24);
  els.settingsGrid.innerHTML = `
    <div class="setting-card"><span>Thor Root</span><strong>${escapeHtml(meta.thorRoot)}</strong></div>
    <div class="setting-card"><span>UI Version</span><strong>${escapeHtml(meta.version || '1.4.0')}</strong></div>
    <div class="setting-card"><span>Platform</span><strong>${escapeHtml(meta.platform)}</strong></div>
    <div class="setting-card"><span>Node</span><strong>${escapeHtml(meta.node)}</strong></div>
    ${configEntries.map(([key, value]) => `<div class="setting-card"><span>${escapeHtml(key)}</span><strong>${escapeHtml(value)}</strong></div>`).join('')}
  `;
}

function applyTheme(theme) {
  document.documentElement.dataset.theme = theme;
  localStorage.setItem('thorWorkbenchTheme', theme);
  els.themeToggle.textContent = theme === 'light' ? 'Switch to forge dark' : 'Switch to light mode';
}

function initEvents() {
  $$('.nav-item').forEach(button => button.addEventListener('click', () => switchPanel(button.dataset.panel)));
  $$('.preset').forEach(button => button.addEventListener('click', () => applyPreset(button.dataset.preset)));

  $('#scanForm').addEventListener('submit', async event => {
    event.preventDefault();
    try {
      const payload = formPayload();
      savePreferences();
      await startRun(payload);
    } catch (error) {
      toast(error.message);
      setStatus('failed', 'Validation failed');
      els.runButton.disabled = false;
      els.stopButton.disabled = true;
    }
  });

  $$('#scanForm input, #scanForm textarea, #scanForm select').forEach(input => {
    input.addEventListener('input', () => { savePreferences(); updateCommandPreview(); });
    input.addEventListener('change', () => { savePreferences(); updateCommandPreview(); });
  });

  els.stopButton.addEventListener('click', stopRun);
  els.doctorButton.addEventListener('click', () => startRun({ command: 'doctor', authorized: true }));
  els.versionButton.addEventListener('click', () => startRun({ command: 'version', authorized: true }));
  els.versionButtonTop.addEventListener('click', () => startRun({ command: 'version', authorized: true }));
  els.refreshHistory.addEventListener('click', loadHistory);
  els.refreshFiles.addEventListener('click', loadFiles);
  els.consoleSearch.addEventListener('input', renderConsole);
  els.historySearch.addEventListener('input', renderHistory);
  els.clearConsole.addEventListener('click', () => { state.consoleLines = []; renderConsole(); });

  $$('.segment').forEach(button => {
    button.addEventListener('click', () => {
      state.streamFilter = button.dataset.stream;
      $$('.segment').forEach(b => b.classList.toggle('active', b === button));
      renderConsole();
    });
  });

  els.copyOutputButton.addEventListener('click', async () => {
    await navigator.clipboard.writeText(state.consoleLines.map(item => item.line).join('\n'));
    toast('Console copied.');
  });
  els.copyCommandButton.addEventListener('click', async () => {
    await navigator.clipboard.writeText(els.commandPreview.textContent);
    toast('Command copied.');
  });
  els.copyFileButton.addEventListener('click', async () => {
    await navigator.clipboard.writeText(state.selectedFileContent || '');
    toast('File content copied.');
  });
  els.downloadFileButton.addEventListener('click', () => {
    if (!state.selectedFilePath) return toast('Select a file first.');
    window.location.href = `/api/download?path=${encodeURIComponent(state.selectedFilePath)}`;
  });
  els.themeToggle.addEventListener('click', () => applyTheme(document.documentElement.dataset.theme === 'light' ? 'dark' : 'light'));

  document.addEventListener('keydown', event => {
    if ((event.ctrlKey || event.metaKey) && event.key === 'Enter') {
      event.preventDefault();
      els.runButton.click();
    }
    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'k') {
      event.preventDefault();
      els.target.focus();
    }
    if (event.key === 'Escape') stopRun();
  });
}

async function init() {
  applyTheme(localStorage.getItem('thorWorkbenchTheme') || 'dark');
  loadPreferences();
  initEvents();
  await loadMetadata().catch(error => toast(error.message));
  await loadHistory().catch(() => {});
  await updateCommandPreview();
  setStatus('idle', 'Local UI ready');
}

init().catch(error => toast(error.message));
