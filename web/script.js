/**
 * Apple Cleanup — Modern Web Dashboard Controller
 * ──────────────────────────────────────────────────────────
 * Full integration with Python server backend & rich safety controls.
 */
(() => {
  'use strict';

  /* ══════════════════════════════════════════════════════════
     Category Definitions & Safety Risks
     ══════════════════════════════════════════════════════════ */
  const CATEGORIES = [
    {
      key: 'user_cache', name: 'User Caches',
      desc: 'Application temporary cache files (~/Library/Caches)',
      risk: 'safe', icon: 'ic-sparkles', color: 'var(--cat-cache)',
      defaultChecked: true, tags: [{ label: 'Safe to remove', type: 'safe' }]
    },
    {
      key: 'system_cache', name: 'System Caches',
      desc: 'System-level caches (/Library/Caches)',
      risk: 'caution', icon: 'ic-wrench', color: 'var(--cat-system)',
      defaultChecked: false, tags: [{ label: 'Rebuilt automatically', type: 'caution' }]
    },
    {
      key: 'logs', name: 'System & User Logs',
      desc: 'Crash logs, diagnostics, and diagnostic reports',
      risk: 'safe', icon: 'ic-sparkles', color: 'var(--cat-logs)',
      defaultChecked: true, tags: [{ label: 'Safe to remove', type: 'safe' }]
    },
    {
      key: 'temp_files', name: 'Temporary Files',
      desc: 'Old temporary items in /tmp and /var/folders',
      risk: 'safe', icon: 'ic-sparkles', color: 'var(--cat-temp)',
      defaultChecked: true, tags: [{ label: 'Safe to remove', type: 'safe' }]
    },
    {
      key: 'diagnostic_reports', name: 'Diagnostic Reports',
      desc: 'Crash reports and diagnostic data',
      risk: 'safe', icon: 'ic-wrench', color: 'var(--cat-xcode)',
      defaultChecked: true, tags: [{ label: 'Diagnostic data', type: 'safe' }]
    },
    {
      key: 'mail_downloads', name: 'Mail Attachments & Downloads',
      desc: 'Cached copies of opened email attachments',
      risk: 'caution', icon: 'ic-hard-drive', color: 'var(--cat-mail)',
      defaultChecked: false, tags: [{ label: 'Caution', type: 'caution' }]
    },
    {
      key: 'browser_cache', name: 'Browser Caches',
      desc: 'Safari, Chrome, Edge, Firefox cached web data',
      risk: 'safe', icon: 'ic-sparkles', color: 'var(--cat-browser)',
      defaultChecked: true, tags: [{ label: 'Fast reload cache', type: 'safe' }]
    },
    {
      key: 'browser_full', name: 'Complete Browser Data',
      desc: 'Cookies, history, and stored session data',
      risk: 'danger', icon: 'ic-alert-triangle', color: 'var(--danger)',
      defaultChecked: false, tags: [{ label: 'Permanent / Logouts', type: 'danger' }]
    },
    {
      key: 'trash', name: 'Main User Trash',
      desc: 'Items in your macOS ~/.Trash folder',
      risk: 'danger', icon: 'ic-trash', color: 'var(--cat-trash)',
      defaultChecked: false, tags: [{ label: 'Permanent deletion', type: 'caution' }]
    },
    {
      key: 'app_leftovers', name: 'App Leftover Files',
      desc: 'Orphaned preferences & containers from uninstalled apps',
      risk: 'caution', icon: 'ic-package-x', color: 'var(--cat-developer)',
      defaultChecked: false, tags: [{ label: 'Orphaned items', type: 'caution' }]
    },
    {
      key: 'developer', name: 'Developer Tool Caches',
      desc: 'Build caches, package stores, containers and downloaded models',
      risk: 'caution', icon: 'ic-wrench', color: 'var(--cat-developer)',
      defaultChecked: false, tags: [{ label: 'Review selected items', type: 'caution' }]
    },
    {
      key: 'quicklook_cache', name: 'QuickLook Thumbnail Cache',
      desc: 'Finder preview thumbnail database',
      risk: 'safe', icon: 'ic-sparkles', color: 'var(--cat-cache)',
      defaultChecked: true, tags: [{ label: 'Re-generated on demand', type: 'safe' }]
    },
    {
      key: 'ios_backups', name: 'Old iOS Device Backups',
      desc: 'Local iPhone and iPad backups in MobileSync',
      risk: 'danger', icon: 'ic-alert-triangle', color: 'var(--cat-ios)',
      defaultChecked: false, tags: [{ label: 'Permanent', type: 'danger' }]
    },
    {
      key: 'app_uninstaller', name: 'Installed Applications',
      desc: 'Targeted removal of complete app bundles',
      risk: 'caution', icon: 'ic-package-x', color: 'var(--cat-developer)',
      defaultChecked: false, tags: [{ label: 'Explicit select', type: 'caution' }]
    },
    {
      key: 'other_trash', name: 'Trash on External Volumes',
      desc: 'Hidden trash bins on connected external drives',
      risk: 'danger', icon: 'ic-alert-triangle', color: 'var(--danger)',
      defaultChecked: false, tags: [{ label: 'Permanent', type: 'danger' }]
    },
    {
      key: 'project_artifacts', name: 'Project Build Folders',
      desc: 'Old node_modules, target/, .build directories in user projects',
      risk: 'caution', icon: 'ic-wrench', color: 'var(--cat-developer)',
      defaultChecked: false, tags: [{ label: 'Explicit select', type: 'caution' }]
    },
    {
      key: 'installer_artifacts', name: 'Installer Packages & DMGs',
      desc: 'Large .dmg, .pkg, and .iso files in Downloads folder',
      risk: 'caution', icon: 'ic-hard-drive', color: 'var(--cat-system)',
      defaultChecked: false, tags: [{ label: 'Explicit select', type: 'caution' }]
    }
  ];

  CATEGORIES.push({ key: 'saved_app_state', name: 'Saved Application State',
    desc: 'Saved windows and application resume state', risk: 'caution',
    icon: 'ic-package-x', color: 'var(--cat-system)', defaultChecked: false,
    tags: [{ label: 'Caution', type: 'caution' }] });

  const CAT_BY_KEY = Object.fromEntries(CATEGORIES.map(c => [c.key, c]));

  /* ══════════════════════════════════════════════════════════
     DOM Selectors & State
     ══════════════════════════════════════════════════════════ */
  const $ = (s, p = document) => p.querySelector(s);
  const $$ = (s, p = document) => Array.from(p.querySelectorAll(s));

  const state = {
    activeTab: 'dashboard',
    dryRun: false,
    scanData: null,
    backendOnline: false,
    selectedCategories: new Set(CATEGORIES.filter(c => c.defaultChecked).map(c => c.key)),
    selectedSubitems: {}, // { categoryKey: Set(subitemIds) }
    terminalLines: 0,
    appsList: [],
    largeFiles: [],
    dupGroups: [],
    historyList: [],
    cleanTasks: [],
    cleanProgressTab: 'active'
  };

  /* ══════════════════════════════════════════════════════════
     Helper Utilities
     ══════════════════════════════════════════════════════════ */
  function formatBytes(bytes, useDecimal = false) {
    if (!bytes || bytes <= 0) return '0 B';
    const base = useDecimal ? 1000 : 1024;
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.max(0, Math.min(units.length - 1, Math.floor(Math.log(bytes) / Math.log(base))));
    return (bytes / Math.pow(base, i)).toFixed(i === 0 ? 0 : 1) + ' ' + units[i];
  }

  function escapeHtml(str) {
    if (!str) return '';
    const div = document.createElement('div');
    div.textContent = String(str);
    return div.innerHTML.replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }


  /* ══════════════════════════════════════════════════════════
     Terminal Logger
     ══════════════════════════════════════════════════════════ */
  function termLog(msg, type = 'info') {
    const term = $('#terminalOutput');
    const badge = $('#termCountBadge');
    if (!term) return;

    const time = new Date().toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', second: '2-digit' });
    const line = document.createElement('div');
    line.className = `terminal-line ${type}`;
    line.textContent = `[${time}] ${msg}`;
    term.appendChild(line);
    term.scrollTop = term.scrollHeight;

    state.terminalLines++;
    if (badge) badge.textContent = `${state.terminalLines} lines`;
  }

  /* ══════════════════════════════════════════════════════════
     Toast Notification System
     ══════════════════════════════════════════════════════════ */
  function showToast(options) {
    const opts = typeof options === 'string' ? { message: options } : (options || {});
    const type = opts.type || 'info'; // 'success' | 'error' | 'warning' | 'info'
    const title = opts.title || (type === 'success' ? 'Success' : type === 'error' ? 'Error' : type === 'warning' ? 'Notice' : 'System');
    const rawMessage = opts.message || '';
    const duration = typeof opts.duration === 'number' ? opts.duration : (type === 'error' ? 6000 : 4500);

    // If running in headless VM test environment without real DOM, trigger test alert capture
    if (typeof alert === 'function' && (typeof window === 'undefined' || !window.document || !document.getElementById)) {
      alert(title ? `[${title}]\n${rawMessage}` : rawMessage);
      return;
    }

    let container = document.getElementById('toastContainer');
    if (!container) {
      container = document.createElement('div');
      container.id = 'toastContainer';
      container.className = 'toast-container';
      container.setAttribute('aria-live', 'polite');
      container.setAttribute('aria-atomic', 'true');
      (document.body || document.documentElement).appendChild(container);
    }

    // Split message if multi-line or long
    const lines = String(rawMessage).trim().split('\n');
    const mainMsg = lines[0] || '';
    const extraDetails = lines.length > 1 ? lines.slice(1).join('\n').trim() : (opts.details || '');

    const toast = document.createElement('div');
    toast.className = `toast toast-${type}`;
    toast.setAttribute('role', 'alert');

    const iconMap = {
      success: 'ic-check',
      error: 'ic-alert-triangle',
      warning: 'ic-alert-triangle',
      info: 'ic-info-circle'
    };
    const iconId = iconMap[type] || 'ic-info-circle';

    const tagMap = {
      success: 'Success',
      error: 'Error',
      warning: 'Notice',
      info: 'System'
    };
    const tagText = opts.tag || tagMap[type] || 'Tool';

    let detailsHtml = '';
    if (extraDetails) {
      detailsHtml = `
        <details class="toast-details">
          <summary>View Output Details</summary>
          <pre>${escapeHtml(extraDetails)}</pre>
        </details>
      `;
    }

    toast.innerHTML = `
      <div class="toast-icon">
        <svg><use href="#${iconId}"/></svg>
      </div>
      <div class="toast-content">
        <div class="toast-meta">
          <span class="toast-tag">${escapeHtml(tagText)}</span>
          <span class="toast-time">Just now</span>
        </div>
        <div class="toast-title">${escapeHtml(title)}</div>
        <div class="toast-message">${escapeHtml(mainMsg)}</div>
        ${detailsHtml}
      </div>
      <button class="toast-close-btn" aria-label="Close notification" title="Close">
        <svg><use href="#ic-x"/></svg>
      </button>
      <div class="toast-progress">
        <div class="toast-progress-bar" style="animation-duration:${duration}ms;"></div>
      </div>
    `;

    // Close logic
    let timer = null;
    let remaining = duration;
    let startTime = Date.now();
    let isPaused = false;

    function closeToast() {
      if (toast.classList.contains('toast-closing')) return;
      toast.classList.add('toast-closing');
      clearTimeout(timer);
      setTimeout(() => {
        toast.remove();
      }, 260);
    }

    const closeBtn = toast.querySelector('.toast-close-btn');
    if (closeBtn) {
      closeBtn.addEventListener('click', (e) => {
        e.stopPropagation();
        closeToast();
      });
    }

    // Pause timer on hover so user can read comfortable
    toast.addEventListener('mouseenter', () => {
      isPaused = true;
      clearTimeout(timer);
      remaining -= (Date.now() - startTime);
      const progressBar = toast.querySelector('.toast-progress-bar');
      if (progressBar) progressBar.style.animationPlayState = 'paused';
    });

    toast.addEventListener('mouseleave', () => {
      if (!isPaused) return;
      isPaused = false;
      startTime = Date.now();
      const progressBar = toast.querySelector('.toast-progress-bar');
      if (progressBar) progressBar.style.animationPlayState = 'running';
      timer = setTimeout(closeToast, Math.max(remaining, 500));
    });

    if (duration > 0) {
      timer = setTimeout(closeToast, duration);
    }

    container.appendChild(toast);
    return toast;
  }

  if (typeof window !== 'undefined') {
    window.showToast = showToast;
  }

  // Toggle terminal drawer
  $('#btnToggleTerminal')?.addEventListener('click', () => {
    $('#terminalDrawer')?.classList.toggle('open');
  });
  $('#terminalHeader')?.addEventListener('click', () => {
    $('#terminalDrawer')?.classList.toggle('open');
  });

  /* ══════════════════════════════════════════════════════════
     Theme Controller
     ══════════════════════════════════════════════════════════ */
  function initTheme() {
    const saved = localStorage.getItem('ac-web-theme') || 'light';
    document.documentElement.setAttribute('data-theme', saved);
    updateThemeToggleUI(saved);
  }

  function toggleTheme() {
    const cur = document.documentElement.getAttribute('data-theme');
    const next = cur === 'dark' ? 'light' : 'dark';
    document.documentElement.setAttribute('data-theme', next);
    localStorage.setItem('ac-web-theme', next);
    updateThemeToggleUI(next);
    termLog(`Theme changed to ${next} mode.`, 'info');
  }

  function updateThemeToggleUI(theme) {
    const btn = $('#themeToggle');
    if (!btn) return;
    const sun = btn.querySelector('.ic-sun');
    const moon = btn.querySelector('.ic-moon');
    if (theme === 'dark') {
      if (sun) sun.style.display = 'block';
      if (moon) moon.style.display = 'none';
    } else {
      if (sun) sun.style.display = 'none';
      if (moon) moon.style.display = 'block';
    }
  }

  initTheme();
  $('#themeToggle')?.addEventListener('click', toggleTheme);

  /* ══════════════════════════════════════════════════════════
     API Bridge
     ══════════════════════════════════════════════════════════ */
  function getCleanupToken() {
    return $('meta[name="cleanup-token"]')?.content || '';
  }

  async function apiFetch(url, options = {}) {
    const token = getCleanupToken();
    const headers = {
      'Content-Type': 'application/json',
      'X-Cleanup-Token': token,
      ...(options.headers || {}),
    };

    let res;
    try {
      res = await fetch(url, {
        ...options,
        headers,
      });
    } catch (netErr) {
      throw new Error(`Network connection failed: ${netErr.message || 'Check if server is running'}`);
    }

    if (!res.ok) {
      let msg = `Server HTTP error ${res.status}`;
      try {
        const errJson = await res.json();
        if (errJson?.error) msg = errJson.error;
      } catch {}
      throw new Error(msg);
    }

    let data;
    try {
      data = await res.json();
    } catch (parseErr) {
      throw new Error(`Invalid JSON response from server`);
    }

    if (data?.success === false) {
      const itemErrors = Array.isArray(data.errors) ? data.errors.map(e => e?.message).filter(Boolean) : [];
      const err = new Error(data.error || data.message || itemErrors.join('; ') || 'Operation failed.');
      err.data = data; // partial results (e.g. freed_human) for callers that report them
      throw err;
    }
    return data;
  }

  /* ══════════════════════════════════════════════════════════
     Tab Navigation Controller
     ══════════════════════════════════════════════════════════ */
  function switchTab(tabId) {
    state.activeTab = tabId;

    // Update sidebar buttons
    $$('.nav-item').forEach(btn => {
      btn.classList.toggle('active', btn.dataset.tab === tabId);
    });

    // Update tab panes
    $$('.tab-pane').forEach(pane => {
      pane.classList.toggle('active', pane.id === `tab-${tabId}`);
    });

    // Lazy load tab data
    if (tabId === 'smart-clean') renderSmartCleanView();
    if (tabId === 'uninstaller') loadUninstallerApps();
    if (tabId === 'large-files') loadLargeFiles();
    if (tabId === 'duplicates') loadDuplicateFiles();
    if (tabId === 'history') loadHistoryRecords();

    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  $('#sidebarMenu')?.addEventListener('click', (e) => {
    const btn = e.target.closest('.nav-item');
    if (btn?.dataset.tab) switchTab(btn.dataset.tab);
  });

  // Action links
  document.addEventListener('click', (e) => {
    const link = e.target.closest('[data-tab-link]');
    if (link?.dataset.tabLink) switchTab(link.dataset.tabLink);
  });
  $('#btnGoClean')?.addEventListener('click', () => switchTab('smart-clean'));

  /* ══════════════════════════════════════════════════════════
     Dry-run Global Switch
     ══════════════════════════════════════════════════════════ */
  const dryRunSwitch = $('#dryRunToggleGlobal');
  dryRunSwitch?.addEventListener('change', (e) => {
    state.dryRun = e.target.checked;
    termLog(`Dry Run Simulation mode is now ${state.dryRun ? 'ENABLED' : 'DISABLED'}.`, state.dryRun ? 'warning' : 'info');
  });

  /* ══════════════════════════════════════════════════════════
     Dashboard & Storage Ring
     ══════════════════════════════════════════════════════════ */
  function renderEmptyStorageRing() {
    const svg = $('#storageRingSvg');
    if (!svg) return;
    const size = 200, stroke = 12;
    const radius = (size - stroke) / 2;
    const cx = size / 2, cy = size / 2;

    svg.innerHTML = `
      <circle cx="${cx}" cy="${cy}" r="${radius}" fill="none" stroke="var(--surface-3)" stroke-width="${stroke}"/>
    `;

    $('#dashRingVal').innerHTML = `— <span class="ring-big-unit">GB</span>`;
    $('#dashRingSub').textContent = `Ready to scan`;
    const badge = $('#dashRingBadge');
    if (badge) {
      badge.textContent = 'Standby';
      badge.className = 'tag-badge tag-safe';
    }
    $('#metricUsed').textContent = '—';
    $('#metricFree').textContent = '—';
    $('#headDiskFree').textContent = '—';
  }

  function renderStorageRing(usedBytes, totalBytes) {
    const svg = $('#storageRingSvg');
    if (!svg || !totalBytes) {
      renderEmptyStorageRing();
      return;
    }

    const size = 200, stroke = 12;
    const radius = (size - stroke) / 2;
    const circumference = 2 * Math.PI * radius;
    const cx = size / 2, cy = size / 2;

    const usedPct = Math.min(100, Math.max(0, (usedBytes / totalBytes) * 100));
    const usedDash = (usedPct / 100) * circumference;

    let ringColor = 'var(--accent)';
    const badge = $('#dashRingBadge');
    if (badge) {
      if (usedPct > 90) {
        badge.textContent = 'Critical (90%+)';
        badge.className = 'tag-badge tag-danger';
        ringColor = 'var(--danger)';
      } else if (usedPct > 75) {
        badge.textContent = 'High Space Usage';
        badge.className = 'tag-badge tag-caution';
        ringColor = 'var(--warning)';
      } else {
        badge.textContent = 'Normal';
        badge.className = 'tag-badge tag-safe';
        ringColor = 'var(--accent)';
      }
    }

    const bulletUsed = $('#bulletUsed');
    if (bulletUsed) {
      bulletUsed.style.background = ringColor;
    }

    svg.innerHTML = `
      <circle cx="${cx}" cy="${cy}" r="${radius}" fill="none" stroke="var(--surface-3)" stroke-width="${stroke}"/>
      <circle cx="${cx}" cy="${cy}" r="${radius}" fill="none" stroke="${ringColor}" stroke-width="${stroke}"
        stroke-linecap="round" stroke-dasharray="${usedDash} ${circumference}"
        style="transition: stroke-dasharray 1s ease-out;"/>
    `;

    const usedGB = (usedBytes / 1e9).toFixed(1);
    const totalGB = (totalBytes / 1e9).toFixed(1);
    const freeBytes = Math.max(0, totalBytes - usedBytes);

    $('#dashRingVal').innerHTML = `${usedGB} <span class="ring-big-unit">GB</span>`;
    $('#dashRingSub').textContent = `${usedPct.toFixed(0)}% of ${totalGB} GB Used`;

    $('#metricUsed').textContent = formatBytes(usedBytes, true);
    $('#metricFree').textContent = formatBytes(freeBytes, true);
    $('#headDiskFree').textContent = formatBytes(freeBytes, true);
  }

  function renderDashboardCleanableTiles() {
    const grid = $('#dashCategoriesSubgrid');
    if (!grid) return;

    const totalBytes = ScanUtil.computeTotalBytes(state.scanData);
    const scan = state.scanData?.scan || {};

    const tilesHtml = CATEGORIES.slice(0, 8).map(cat => {
      const info = scan[cat.key];
      const bytes = info?.size_bytes || 0;

      return `
        <div class="cat-stat-tile" data-tab-link="smart-clean">
          <div class="tile-icon" style="background:var(--surface-3);color:${cat.color};">
            <svg><use href="#${cat.icon}"/></svg>
          </div>
          <div style="flex:1;min-width:0;">
            <div style="font-weight:600;font-size:13px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${escapeHtml(cat.name)}</div>
            <div style="font-size:12px;color:var(--text-3);font-family:var(--font-mono);margin-top:2px;">${formatBytes(bytes)}</div>
          </div>
        </div>
      `;
    }).join('');

    grid.innerHTML = tilesHtml;
    $('#dashCleanableTotal').textContent = formatBytes(totalBytes);
  }

  /* ══════════════════════════════════════════════════════════
     Smart Clean View & Logic
     ══════════════════════════════════════════════════════════ */
  function renderSmartCleanView() {
    const container = $('#smartCleanCategoriesList');
    if (!container) return;

    const scan = state.scanData?.scan || {};

    const html = CATEGORIES.map(cat => {
      const info = scan[cat.key];
      const bytes = info?.size_bytes || 0;
      const available = !!info;
      const isChecked = available && state.selectedCategories.has(cat.key);
      const riskClass = cat.risk === 'danger' ? 'danger-category' : (cat.risk === 'caution' ? 'caution-category' : '');
      const subitems = Array.isArray(info?.subitems) ? info.subitems : [];

      const tagsHtml = cat.tags.map(t =>
        `<span class="tag-badge tag-${t.type}">${escapeHtml(t.label)}</span>`
      ).join(' ');

      return `
        <div class="cat-item-card ${riskClass}" data-cat-key="${cat.key}">
          <div class="cat-item-header" data-toggle-accordion="${cat.key}">
            <div class="cat-left-meta">
              <input type="checkbox" class="cat-checkbox" ${available ? '' : 'disabled'} ${isChecked ? 'checked' : ''} data-cat-check="${cat.key}" />
              <div>
                <div class="cat-name-row">
                  <span>${escapeHtml(cat.name)}</span>
                  ${tagsHtml}
                </div>
                <div class="cat-desc-text">${escapeHtml(cat.desc)}</div>
              </div>
            </div>
            <div class="cat-right-meta">
              <span class="cat-size-pill">${available ? formatBytes(bytes) : 'Unavailable'}</span>
              ${subitems.length > 0 ? `<svg width="18" height="18" style="color:var(--text-3);"><use href="#ic-chevron-down"/></svg>` : ''}
            </div>
          </div>

          ${subitems.length > 0 ? `
            <div class="subitems-tray">
              <div style="font-size:11px;font-weight:700;color:var(--text-3);text-transform:uppercase;margin-bottom:8px;">Sub-items (${subitems.length})</div>
              ${subitems.map(sub => `
                <div class="subitem-entry">
                  <div class="subitem-left">
                    ${ScanUtil.FILELIST_CATEGORIES.includes(cat.key) ? `<input type="checkbox" class="cat-checkbox" ${isChecked && state.selectedSubitems[cat.key]?.has(sub.id) ? 'checked' : ''} data-sub-cat="${cat.key}" data-sub-id="${escapeHtml(sub.id)}" aria-label="Select ${escapeHtml(sub.name || sub.id)}" />` : ''}
                    <div>
                      <div class="subitem-name">${escapeHtml(sub.name || sub.id)}</div>
                      <div class="subitem-path">${escapeHtml(sub.path || '')}</div>
                    </div>
                  </div>
                  <strong style="font-family:var(--font-mono);font-size:12px;">${escapeHtml(sub.size_human || formatBytes(sub.size_bytes))}</strong>
                </div>
              `).join('')}
            </div>
          ` : ''}
        </div>
      `;
    }).join('');

    container.innerHTML = html;
    updateSmartCleanSelectedSummary();
  }

  function updateSmartCleanSelectedSummary() {
    let totalBytes = 0;
    let count = 0;
    const scan = state.scanData?.scan || {};

    state.selectedCategories.forEach(key => {
      if (!scan[key]) return;
      const items = scan[key].subitems;
      totalBytes += ScanUtil.FILELIST_CATEGORIES.includes(key) && Array.isArray(items)
        ? items.reduce((sum, item) => sum + (state.selectedSubitems[key]?.has(item.id) ? (item.size_bytes || 0) : 0), 0)
        : scan[key].size_bytes || 0;
      count++;
    });

    $('#smartSelectedSummary').textContent = `${count} categories selected`;
    $('#smartTotalSelectedSize').textContent = formatBytes(totalBytes);
  }

  // Accordion toggle & selection events
  $('#smartCleanCategoriesList')?.addEventListener('click', (e) => {
    if (e.target.dataset.subCat) {
      const key = e.target.dataset.subCat;
      if (!state.selectedCategories.has(key)) state.selectedSubitems[key] = new Set();
      const selected = state.selectedSubitems[key] ||= new Set();
      if (e.target.checked) selected.add(e.target.dataset.subId);
      else selected.delete(e.target.dataset.subId);
      if (selected.size) state.selectedCategories.add(key);
      else state.selectedCategories.delete(key);
      const checkbox = $(`[data-cat-check="${key}"]`);
      if (checkbox) checkbox.checked = selected.size > 0;
      updateSmartCleanSelectedSummary();
      return;
    }
    // Checkbox clicked
    if (e.target.dataset.catCheck) {
      const key = e.target.dataset.catCheck;
      if (!state.scanData?.scan?.[key]) return;
      if (e.target.checked) {
        state.selectedCategories.add(key);
        state.selectedSubitems[key] = new Set((state.scanData.scan[key].subitems || []).map(item => item.id));
      }
      else state.selectedCategories.delete(key);
      $$(`[data-sub-cat="${key}"]`).forEach(checkbox => {
        checkbox.checked = e.target.checked;
      });
      if (!e.target.checked) state.selectedSubitems[key] = new Set();
      updateSmartCleanSelectedSummary();
      return;
    }

    // Header accordion toggle
    const header = e.target.closest('[data-toggle-accordion]');
    if (header) {
      const card = header.closest('.cat-item-card');
      const open = card.getAttribute('data-open') === 'true';
      card.setAttribute('data-open', String(!open));
    }
  });

  // Select all safe categories
  $('#smartSelectAll')?.addEventListener('change', (e) => {
    const isChecked = e.target.checked;
    CATEGORIES.forEach(c => {
      if (!isChecked) state.selectedCategories.delete(c.key);
      else if (c.risk === 'safe' && state.scanData?.scan?.[c.key]) {
        state.selectedCategories.add(c.key);
        state.selectedSubitems[c.key] = new Set((state.scanData.scan[c.key].subitems || []).map(item => item.id));
      }
    });
    renderSmartCleanView();
  });

  /* ══════════════════════════════════════════════════════════
     Execute Cleaning Action
     ══════════════════════════════════════════════════════════ */
  $('#btnExecuteClean')?.addEventListener('click', () => {
    if (state.selectedCategories.size === 0) {
      showToast({
        type: 'warning',
        tag: 'Selection Required',
        title: 'No Categories Selected',
        message: 'Please select at least one category to clean.'
      });
      return;
    }

    // Check if high-risk categories selected
    const selectedCats = Array.from(state.selectedCategories).map(k => CAT_BY_KEY[k]).filter(Boolean);
    const hasDanger = selectedCats.some(c => c.risk === 'danger');

    if (hasDanger && !state.dryRun) {
      showSafetyModal(
        'Permanent Cleanup Confirmation',
        `You have selected high-risk categories (such as iOS Backups or Trash). Files deleted in these categories cannot be recovered. Are you sure you want to permanently delete them?`,
        () => performClean()
      );
    } else {
      performClean();
    }
  });

  // One request per category so the progress panel can report each as it
  // finishes. Trash categories go first: emptying Trash after another category
  // moved items there would permanently delete them.
  const TRASH_CATEGORIES = ['trash', 'other_trash'];
  const CLEAN_DONE_STATES = ['done', 'skipped', 'failed'];

  function renderCleanProgress(finished = false) {
    const tasks = state.cleanTasks;
    const done = tasks.filter(t => CLEAN_DONE_STATES.includes(t.status));
    const active = tasks.filter(t => !CLEAN_DONE_STATES.includes(t.status));
    const shown = state.cleanProgressTab === 'done' ? done : active;

    $('#cleanProgressTitle').textContent = finished
      ? (state.dryRun ? 'Dry run finished' : 'Cleanup finished')
      : (state.dryRun ? 'Simulating cleanup…' : 'Cleaning…');
    $('#cleanProgressCount').textContent = `${done.length} of ${tasks.length} done`;
    $('#cleanProgressFill').style.width = `${tasks.length ? (done.length / tasks.length) * 100 : 0}%`;
    $('#cleanTabActiveCount').textContent = String(active.length);
    $('#cleanTabDoneCount').textContent = String(done.length);
    $('#cleanTabActive')?.setAttribute('aria-selected', String(state.cleanProgressTab === 'active'));
    $('#cleanTabDone')?.setAttribute('aria-selected', String(state.cleanProgressTab === 'done'));

    const icon = { done: 'ic-check', failed: 'ic-alert-triangle', skipped: 'ic-info-circle', pending: 'ic-history' };
    const label = t => ({
      pending: 'Queued',
      running: 'In progress',
      done: `${state.dryRun ? 'Would remove' : 'Removed'} ${t.size}${t.note ? ` · ${t.note}` : ''}`,
      skipped: t.note || 'Skipped',
      failed: t.note || 'Failed',
    })[t.status];
    $('#cleanProgressList').innerHTML = shown.length
      ? shown.map(t => `
          <li class="clean-task clean-task-${t.status}">
            ${t.status === 'running'
              ? '<span class="clean-task-spinner" aria-hidden="true"></span>'
              : `<svg class="clean-task-icon" aria-hidden="true"><use href="#${icon[t.status]}"/></svg>`}
            <span>${escapeHtml(t.name)}</span>
            <span class="clean-task-detail">${escapeHtml(label(t))}</span>
          </li>`).join('')
      : `<li class="clean-progress-empty">${state.cleanProgressTab === 'done' ? 'Nothing finished yet.' : 'No tasks in progress.'}</li>`;
  }

  $('#cleanProgress')?.addEventListener('click', (e) => {
    const tab = e.target.closest('[data-progress-tab]');
    if (!tab) return;
    state.cleanProgressTab = tab.dataset.progressTab;
    renderCleanProgress(!state.cleanTasks.some(t => !CLEAN_DONE_STATES.includes(t.status)));
  });

  async function cleanOneCategory(task) {
    try {
      const payload = {
        ...ScanUtil.buildSelectedCleanPayload(state.scanData, [task.key], state.selectedSubitems),
        dry_run: state.dryRun
      };
      const res = await apiFetch('/api/clean', { method: 'POST', body: JSON.stringify(payload) });
      // estimated_bytes is what was removed or moved to Trash; the df-based
      // freed_bytes stays 0 for Trash moves, which free nothing until emptied.
      task.bytes = res.estimated_bytes || 0;
      task.size = res.estimated_human || formatBytes(task.bytes);
      const detail = Array.isArray(res.details) ? res.details[0]?.status : '';
      if (detail === 'skipped') {
        task.status = 'skipped';
        task.note = 'Skipped (needs administrator access)';
      } else {
        task.status = 'done';
        if (detail === 'partial') task.note = 'some items in use were skipped';
      }
    } catch (err) {
      task.status = 'failed';
      task.bytes = err.data?.estimated_bytes || 0;
      task.note = err.data?.estimated_human ? `${err.message} (removed ${err.data.estimated_human})` : err.message;
    }
  }

  async function performClean() {
    const btn = $('#btnExecuteClean');
    if (btn) { btn.disabled = true; btn.textContent = state.dryRun ? 'Simulating...' : 'Cleaning...'; }
    // A scan finishing mid-clean would cache and display pre-clean results.
    const scanButtons = [$('#btnQuickScan'), $('#btnSmartRescan')].filter(Boolean);
    scanButtons.forEach(b => { b.disabled = true; });

    const categories = Array.from(state.selectedCategories).filter(k => state.scanData?.scan?.[k]);
    categories.sort((a, b) => TRASH_CATEGORIES.includes(b) - TRASH_CATEGORIES.includes(a));
    termLog(`Initiating ${state.dryRun ? 'DRY-RUN simulation' : 'cleaning'} for ${categories.length} categories...`, 'warning');

    if (!state.backendOnline) {
      showToast({ type: 'error', tag: 'Clean Error', title: 'Cleanup Failed',
        message: 'Backend unavailable. No cleanup was performed.', duration: 6500 });
      scanButtons.forEach(b => { b.disabled = false; });
      if (btn) { btn.disabled = false; btn.textContent = 'Clean Selected Space'; }
      return;
    }

    state.cleanTasks = categories.map(key => ({ key, name: CAT_BY_KEY[key]?.name || key, status: 'pending', size: '', note: '' }));
    state.cleanProgressTab = 'active';
    const panel = $('#cleanProgress');
    if (panel) panel.hidden = false;
    renderCleanProgress();

    try {
      for (const task of state.cleanTasks) {
        task.status = 'running';
        renderCleanProgress();
        await cleanOneCategory(task);
        termLog(`${task.name}: ${task.status}${task.note ? ` (${task.note})` : ''}`, task.status === 'failed' ? 'error' : 'success');
        renderCleanProgress();
      }
    } finally {
      state.cleanProgressTab = 'done';
      renderCleanProgress(true);
      scanButtons.forEach(b => { b.disabled = false; });
      if (btn) { btn.disabled = false; btn.textContent = 'Clean Selected Space'; }
    }

    const failed = state.cleanTasks.filter(t => t.status === 'failed');
    const total = formatBytes(state.cleanTasks.reduce((sum, t) => sum + (t.bytes || 0), 0));
    showToast({
      type: failed.length ? 'error' : 'success',
      tag: state.dryRun ? 'Dry Run' : 'Clean Complete',
      title: failed.length ? 'Cleanup Partially Failed' : (state.dryRun ? 'Dry Run Simulation Finished' : 'Cleanup Complete'),
      message: failed.length
        ? `${failed.length} of ${state.cleanTasks.length} categories failed: ${failed.map(t => `${t.name}: ${t.note}`).join('; ')}. Removed: ${total}.`
        : (state.dryRun ? `Simulation finished. Would remove approximately ${total}.` : `Removed ${total}.`),
      duration: failed.length ? 6500 : 5500
    });
    // Refresh in the background; the results above are already final.
    triggerScan();
  }


  /* ══════════════════════════════════════════════════════════
     System Maintenance Tools Execution
     ══════════════════════════════════════════════════════════ */
  async function runSystemTool(endpoint, toolName, btn) {
    const origHtml = btn ? btn.innerHTML : '';
    if (btn) {
      btn.disabled = true;
      btn.innerHTML = `<svg style="animation:spin 1s linear infinite;"><use href="#ic-refresh"/></svg> Running...`;
    }
    termLog(`Starting maintenance tool: ${toolName}...`, 'info');

    const startTime = Date.now();
    try {
      if (state.backendOnline) {
        const res = await apiFetch(endpoint, { method: 'POST', body: '{}' });
        const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);
        const successMsg = res.message || res.status || res.note || 'Operation completed successfully.';
        termLog(`${toolName} succeeded (${elapsed}s): ${successMsg}`, 'success');
        showToast({
          type: 'success',
          tag: 'System Tool',
          title: toolName,
          message: successMsg,
          duration: 5000
        });
      } else {
        throw new Error('Backend unavailable. No maintenance was performed.');
      }
    } catch (err) {
      termLog(`${toolName} error: ${err.message}`, 'error');
      showToast({
        type: 'error',
        tag: 'Tool Error',
        title: toolName,
        message: err.message,
        duration: 6500
      });
    } finally {
      if (btn) {
        btn.disabled = false;
        btn.innerHTML = origHtml;
      }
    }
  }

  $('#btnToolSpotlight')?.addEventListener('click', function() {
    runSystemTool('/api/spotlight-reindex', 'Rebuild Spotlight Index', this);
  });
  $('#btnToolFlushDns')?.addEventListener('click', function() {
    runSystemTool('/api/flush-dns', 'Flush DNS Cache', this);
  });
  $('#btnToolPurgeRam')?.addEventListener('click', function() {
    runSystemTool('/api/purge-ram', 'Purge Inactive Memory', this);
  });
  $('#btnToolLaunchAgents')?.addEventListener('click', function() {
    runSystemTool('/api/launchagents-clean', 'Clean Broken LaunchAgents', this);
  });
  $('#btnToolThinSnapshots')?.addEventListener('click', function() {
    runSystemTool('/api/thin-snapshots', 'Thin APFS Local Snapshots', this);
  });
  $('#btnToolWeeklySchedule')?.addEventListener('click', async function() {
    const origHtml = this.innerHTML;
    this.disabled = true;
    this.innerHTML = `<svg style="animation:spin 1s linear infinite;"><use href="#ic-refresh"/></svg> Updating...`;
    try {
      if (state.backendOnline) {
        const status = await apiFetch('/api/schedule-status');
        const nextState = !(status.enabled || status.scheduled);
        const res = await apiFetch('/api/schedule-weekly', {
          method: 'POST',
          body: JSON.stringify({ enabled: nextState })
        });
        const isEnabled = res.enabled ?? nextState;
        const msg = isEnabled
          ? 'Weekly background cleanup scheduled for Sundays at 03:00.'
          : 'Weekly background cleanup has been disabled.';
        termLog(`Weekly automation: ${msg}`, 'success');
        showToast({
          type: 'success',
          tag: 'Automation',
          title: 'Weekly Cleanup Automation',
          message: msg,
          duration: 5000
        });
      } else {
        throw new Error('Backend unavailable. No maintenance was performed.');
      }
    } catch (err) {
      termLog(`Weekly automation error: ${err.message}`, 'error');
      showToast({
        type: 'error',
        tag: 'Automation Error',
        title: 'Weekly Automation Failed',
        message: err.message,
        duration: 6500
      });
    } finally {
      this.disabled = false;
      this.innerHTML = origHtml;
    }
  });

  /* ══════════════════════════════════════════════════════════
     App Uninstaller View
     ══════════════════════════════════════════════════════════ */
  async function loadUninstallerApps() {
    const container = $('#uninstallerAppList');
    if (!container) return;

    container.innerHTML = '<div style="padding:40px;text-align:center;color:var(--text-3);">Scanning installed applications...</div>';

    try {
      if (state.backendOnline) {
        const data = await apiFetch('/api/apps');
        state.appsList = data.apps || [];
      } else {
        state.appsList = [];
        throw new Error('Backend unavailable. Start the local server and reconnect.');
      }
      renderAppsGrid();
    } catch (err) {
      container.innerHTML = `<div style="padding:40px;text-align:center;color:var(--danger);">Failed to load applications: ${escapeHtml(err.message)}</div>`;
    }
  }

  function renderAppsGrid(query = '') {
    const container = $('#uninstallerAppList');
    if (!container) return;

    const filtered = state.appsList.filter(a =>
      a.name.toLowerCase().includes(query.toLowerCase())
    );

    if (filtered.length === 0) {
      container.innerHTML = '<div style="padding:40px;text-align:center;color:var(--text-3);">No matching applications found.</div>';
      return;
    }

    container.innerHTML = `
      <div class="apps-grid">
        ${filtered.map(app => `
          <div class="app-card-box">
            <div>
              <div style="font-weight:700;font-size:15px;">${escapeHtml(app.name)}</div>
              <div style="font-size:12px;color:var(--text-3);margin-top:2px;">Version ${escapeHtml(app.version || '—')}</div>
            </div>
            <div style="display:flex;align-items:center;justify-content:space-between;border-top:1px solid var(--border);padding-top:10px;margin-top:4px;">
              <strong style="font-family:var(--font-mono);font-size:14px;color:var(--accent);">${formatBytes(app.size_bytes)}</strong>
              <button class="btn btn-danger" style="padding:6px 12px;font-size:12px;" data-uninstall-app="${escapeHtml(app.name)}" data-target-id="${escapeHtml(app.target_id || '')}">
                <svg width="14" height="14"><use href="#ic-trash"/></svg> Uninstall
              </button>
            </div>
          </div>
        `).join('')}
      </div>
    `;
  }

  $('#appSearchInput')?.addEventListener('input', (e) => {
    renderAppsGrid(e.target.value);
  });

  $('#uninstallerAppList')?.addEventListener('click', (e) => {
    const btn = e.target.closest('[data-uninstall-app]');
    if (!btn) return;
    const appName = btn.dataset.uninstallApp;
    const targetId = btn.dataset.targetId;

    showSafetyModal(
      `Uninstall Application: ${appName}`,
      `This will completely delete ${appName} and all associated cache and configuration files from ~/Library. Are you sure?`,
      async () => {
        termLog(`Uninstalling app: ${appName}...`, 'warning');
        btn.disabled = true;
        try {
          if (!state.backendOnline) throw new Error('Backend unavailable. No application was removed.');
          await apiFetch('/api/uninstall', {
            method: 'POST',
            body: JSON.stringify({ target_id: targetId, app_name: appName })
          });
          termLog(`App ${appName} uninstalled successfully.`, 'success');
          state.appsList = state.appsList.filter(a => targetId ? a.target_id !== targetId : a.name !== appName);
          renderAppsGrid($('#appSearchInput')?.value || '');
          showToast({
            type: 'success',
            tag: 'Uninstaller',
            title: 'Application Removed',
            message: `Application "${appName}" removed.`
          });
        } catch (err) {
          btn.disabled = false;
          showToast({
            type: 'error',
            tag: 'Uninstall Error',
            title: 'Failed to Uninstall',
            message: err.message
          });
        }
      }
    );
  });

  /* ══════════════════════════════════════════════════════════
     Large Files & Duplicates — live, read-only inventory
     ══════════════════════════════════════════════════════════ */
  const fileScanPending = new Set();
  function loadLargeFiles() { return loadFileInventory('large'); }
  function loadDuplicateFiles() { return loadFileInventory('duplicates'); }

  async function loadFileInventory(kind) {
    const container = $(kind === 'large' ? '#largeFilesContainer' : '#duplicatesContainer');
    if (!container || fileScanPending.has(kind)) return;
    fileScanPending.add(kind);
    container.setAttribute('aria-busy', 'true');
    container.innerHTML = '<div class="card file-scan-card" role="status">Scanning current files… This may take up to 20 seconds.</div>';
    try {
      const data = await apiFetch(kind === 'large' ? '/api/large-files' : '/api/duplicates');
      const results = data.results || [];
      const notice = data.partial
        ? `Partial scan: ${data.limit_reason || 'some files could not be read or changed during the scan'}. ${data.skipped_errors} unreadable or changed entries.`
        : `Scan complete. ${data.scanned_files} files checked.`;
      const rows = kind === 'large'
        ? results.map(file => `<tr><td><strong>${escapeHtml(file.name)}</strong></td><td class="file-scan-path">${escapeHtml(file.path)}</td><td>${formatBytes(file.size_bytes)}</td></tr>`).join('')
        : results.map(group => `<tr><td class="file-scan-path">${group.files.map(file => escapeHtml(file.path)).join('<br>')}</td><td>${group.files.length}</td><td>${formatBytes(group.duplicate_bytes)}</td></tr>`).join('');
      container.innerHTML = `<div class="card file-scan-card">
        <button class="btn btn-secondary" data-refresh-files="${kind}">Scan again</button>
        <p role="status">${escapeHtml(notice)}${data.truncated ? ' Showing the first 200 results.' : ''}</p>
        <p>${escapeHtml(data.scope)}</p>
        <p>${kind === 'large' ? `Files at least ${formatBytes(data.large_min_bytes)}.` : 'Identical content verified with SHA-256; hard links count once. No copy is assumed to be the original.'} Review paths in Finder to manage files. This view does not delete files.</p>
        ${results.length ? `<div class="table-wrap"><table class="data-table"><thead><tr>${kind === 'large' ? '<th>Filename</th><th>Location</th><th>Size</th>' : '<th>Matching files</th><th>Copies</th><th>Extra copy size</th>'}</tr></thead><tbody>${rows}</tbody></table></div>` : `<p>${data.partial ? 'No matches found in the portion scanned.' : 'No matching files found in the scanned locations.'}</p>`}
      </div>`;
    } catch (err) {
      container.innerHTML = `<div class="card file-scan-card"><p role="alert">Could not scan files: ${escapeHtml(err.message)}</p><button class="btn btn-secondary" data-refresh-files="${kind}">Try again</button></div>`;
    } finally {
      fileScanPending.delete(kind);
      container.setAttribute('aria-busy', 'false');
    }
  }
  document.addEventListener('click', event => {
    const button = event.target.closest('[data-refresh-files]');
    if (button) loadFileInventory(button.dataset.refreshFiles);
  });

  /* ══════════════════════════════════════════════════════════
     Operations History
     ══════════════════════════════════════════════════════════ */
  async function loadHistoryRecords() {
    const tbody = $('#historyTableBody');
    if (!tbody) return;

    try {
      if (state.backendOnline) {
        const rows = await apiFetch('/api/history');
        if (!Array.isArray(rows) || rows.length === 0) {
          tbody.innerHTML = '<tr><td colspan="5" style="text-align:center;color:var(--text-3);padding:32px;">No historical operations recorded yet.</td></tr>';
          return;
        }

        tbody.innerHTML = rows.map(r => `
          <tr>
            <td>${escapeHtml(r.ts ? new Date(r.ts * 1000).toLocaleString() : '—')}</td>
            <td><strong>${escapeHtml(r.action || 'Clean')}</strong></td>
            <td>${escapeHtml(r.category || '—')}</td>
            <td><strong style="color:var(--safe);">${formatBytes(r.bytes || 0)}</strong></td>
            <td><span class="tag-badge tag-caution">${escapeHtml(r.action || 'RECORDED')}</span></td>
          </tr>
        `).join('');
      } else {
        throw new Error('Backend unavailable. History could not be loaded.');
      }
    } catch (err) {
      tbody.innerHTML = `<tr><td colspan="5" style="text-align:center;color:var(--danger);padding:32px;">Could not load history: ${escapeHtml(err.message)}</td></tr>`;
    }
  }

  $('#btnRefreshHistory')?.addEventListener('click', loadHistoryRecords);

  /* ══════════════════════════════════════════════════════════
     Safety Confirmation Modal
     ══════════════════════════════════════════════════════════ */
  let modalConfirmCallback = null;

  function showSafetyModal(title, message, onConfirm) {
    const modal = $('#safetyConfirmModal');
    if (!modal) return;

    $('#modalTitle').textContent = title;
    $('#modalBody').textContent = message;
    modalConfirmCallback = onConfirm;

    modal.classList.add('open');
  }

  function hideSafetyModal() {
    $('#safetyConfirmModal')?.classList.remove('open');
    modalConfirmCallback = null;
  }

  $('#modalBtnCancel')?.addEventListener('click', hideSafetyModal);
  $('#modalBtnConfirm')?.addEventListener('click', () => {
    if (typeof modalConfirmCallback === 'function') {
      modalConfirmCallback();
    }
    hideSafetyModal();
  });

  /* ══════════════════════════════════════════════════════════
     Trigger Scan & Init
     ══════════════════════════════════════════════════════════ */
  async function triggerScan() {
    termLog('Scanning macOS system caches and storage...', 'info');
    try {
      if (state.backendOnline) {
        const scanResult = await apiFetch('/api/scan');
        state.scanData = scanResult;
        // Keep only items the user still has checked; never re-select by default.
        const previous = state.selectedSubitems;
        state.selectedSubitems = Object.fromEntries(Object.entries(scanResult.scan || {}).map(([key, info]) =>
          [key, new Set((info.subitems || []).map(item => item.id).filter(id => previous[key]?.has(id)))]));
        state.selectedCategories = new Set([...state.selectedCategories].filter(key => scanResult.scan?.[key]
          && (!ScanUtil.FILELIST_CATEGORIES.includes(key) || state.selectedSubitems[key].size > 0)));
        termLog(scanResult.partial ? 'Partial scan: unavailable categories have been disabled.' : 'Scan completed successfully.', scanResult.partial ? 'warning' : 'success');
      } else {
        state.scanData = { scan: {} };
        state.selectedCategories.clear();
      }
      renderDashboardCleanableTiles();
      if (state.activeTab === 'smart-clean') renderSmartCleanView();
    } catch (err) {
      state.scanData = { scan: {} };
      state.selectedCategories.clear();
      renderDashboardCleanableTiles();
      if (state.activeTab === 'smart-clean') renderSmartCleanView();
      termLog(`Scan error: ${err.message}`, 'error');
    }
  }

  $('#btnQuickScan')?.addEventListener('click', triggerScan);
  $('#btnSmartRescan')?.addEventListener('click', triggerScan);

  async function init() {
    // Start with clean empty ring state (no fake numbers)
    renderEmptyStorageRing();
    termLog('Connecting to Apple Cleanup backend...', 'info');

    try {
      await apiFetch('/api/health');
      state.backendOnline = true;
      termLog('Backend connection established (Online).', 'success');

      // Fetch live status from backend
      const status = await apiFetch('/api/status');
      if (status) {
        if (status.macos_version) $('#headMacVer').textContent = status.macos_version;
        if (status.chip) $('#sysChipName').textContent = status.chip;
        if (status.user) $('#sysUser').textContent = status.user;
        if (status.memory) $('#sysMemory').textContent = status.memory;

        if (status.disk_total_bytes && status.disk_used_bytes) {
          renderStorageRing(status.disk_used_bytes, status.disk_total_bytes);
        } else {
          renderEmptyStorageRing();
        }
      }
    } catch (e) {
      state.backendOnline = false;
      termLog('Backend unavailable. Start the local server and reload to reconnect.', 'error');
      renderEmptyStorageRing();
    }

    await triggerScan();
  }

  init();
})();
