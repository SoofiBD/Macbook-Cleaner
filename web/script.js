/**
 * Apple Cleanup Dashboard — Refined frontend
 * ───────────────────────────────────────────
 * Same API surface as before. Falls back to realistic mock data
 * when the Python backend isn't reachable (e.g. opened as a static
 * file) so the UI demos end-to-end.
 */

(() => {
  'use strict';

  /* ──────────────────────────────────────────────────────────
     Constants & data
     ────────────────────────────────────────────────────────── */
  const CATEGORIES = [
    {
      key: 'user_cache',    index: 1,  name: 'Kullanıcı Cache',
      desc: 'Uygulama önbellek dosyaları',
      icon: 'i-cache', color: '#4d8eff', defaultChecked: true, danger: false, tags: [],
    },
    {
      key: 'system_cache',  index: 2,  name: 'Sistem Cache',
      desc: 'Sistem seviyesi önbellek',
      icon: 'i-cpu', color: '#6f6ff7', defaultChecked: true, danger: false,
      tags: [{ icon: 'i-lock', label: 'sudo', style: 'amber' }],
    },
    {
      key: 'app_leftovers', index: 3,  name: 'Uygulama Kalıntıları',
      desc: 'Kaldırılmış uygulama artıkları',
      icon: 'i-leftover', color: '#a26bf7', defaultChecked: true, danger: false, tags: [],
    },
    {
      key: 'logs',          index: 4,  name: 'Loglar',
      desc: 'Sistem ve uygulama kayıtları',
      icon: 'i-log', color: '#0bb8c9', defaultChecked: true, danger: false, tags: [],
    },
    {
      key: 'temp_files',    index: 5,  name: 'Geçici Dosyalar',
      desc: 'Geçici ve ara dosyalar',
      icon: 'i-temp', color: '#16a34a', defaultChecked: true, danger: false, tags: [],
    },
    {
      key: 'developer',     index: 6,  name: 'Geliştirici',
      desc: 'Xcode DerivedData ve bozuk linkler',
      icon: 'i-dev', color: '#d97706', defaultChecked: true, danger: false, tags: [],
    },
    {
      key: 'trash',         index: 7,  name: 'Çöp Kutusu',
      desc: 'Çöp kutusundaki dosyalar',
      icon: 'i-trash', color: '#8b8f99', defaultChecked: true, danger: false, tags: [],
    },
    {
      key: 'browser_cache', index: 8,  name: 'Tarayıcı Cache',
      desc: 'Sadece önbellek — çerezler & oturumlar korunur',
      icon: 'i-browser', color: '#f59e0b', defaultChecked: false, danger: false, tags: [],
    },
    {
      key: 'browser_full',  index: 9,  name: 'Tarayıcı Tüm Veri',
      desc: 'Çerezler, geçmiş ve profil verisi',
      icon: 'i-browser-warn', color: '#dc2626', defaultChecked: false, danger: true,
      tags: [{ icon: 'i-warn', label: 'oturumlar kapanır', style: 'red' }],
    },
    {
      key: 'ios_backups',   index: 10, name: 'iOS Yedekleri',
      desc: 'iPhone/iPad MobileSync yedekleri',
      icon: 'i-phone', color: '#ef4444', defaultChecked: false, danger: true,
      tags: [{ icon: 'i-warn', label: 'silmeden önce kontrol', style: 'red' }],
    },
    {
      key: 'app_uninstaller', index: 11, name: 'Tam Uygulama Kaldırıcı',
      desc: '/Applications uygulamaları ve tüm kalıntıları',
      icon: 'i-uninstall', color: '#c2410c', defaultChecked: false, danger: true,
      tags: [{ icon: 'i-warn', label: 'uygulamayı siler', style: 'red' }],
    },
    {
      key: 'mail_downloads', index: 12, name: 'Mail İndirilenleri',
      desc: 'Mail eklentilerinden indirilen dosyalar',
      icon: 'i-mail', color: '#0ea5e9', defaultChecked: true, danger: false, tags: [],
    },
  ];

  const KEY_BY_INDEX = Object.fromEntries(CATEGORIES.map((c) => [c.index, c.key]));
  const CAT_BY_KEY   = Object.fromEntries(CATEGORIES.map((c) => [c.key, c]));

  /* ──────────────────────────────────────────────────────────
     DOM
     ────────────────────────────────────────────────────────── */
  const $  = (s, p = document) => p.querySelector(s);
  const $$ = (s, p = document) => Array.from(p.querySelectorAll(s));

  const el = {
    themeToggle:   $('#themeToggle'),
    sysVersion:    $('#sysVersion'),
    sysUser:       $('#sysUser'),
    sysDiskFree:   $('#sysDiskFree'),
    diskBarFill:   $('#diskBarFill'),
    donutFill:     $('#donutFill'),
    donutNum:      $('#donutNum'),

    hero:          $('#hero'),
    heroEyebrow:   $('#heroEyebrow'),
    heroTitle:     $('#heroTitle'),
    heroLead:      $('#heroLead'),
    heroNumber:    $('#heroNumber'),
    hnValue:       $('#hnValue'),
    hnUnit:        $('#hnUnit'),
    heroBar:       $('#heroBar'),
    heroBarTrack:  $('#heroBarTrack'),
    heroBarLegend: $('#heroBarLegend'),

    btnScan:       $('#btnScan'),
    btnClean:      $('#btnClean'),
    btnSelectAll:  $('#btnSelectAll'),
    btnSelectNone: $('#btnSelectNone'),

    resultsPanel:  $('#resultsPanel'),
    resultsTitle:  $('#resultsTitle'),
    resultsSub:    $('#resultsSubtitle'),
    resultsFreed:  $('#resultsFreed'),
    resultsChips:  $('#resultsDetails'),
    resultsClose:  $('#resultsClose'),

    term:          $('#term'),
    termHead:      $('#termHead'),
    termBody:      $('#terminalBody'),
    termCount:     $('#termCount'),

    btnSpotlight:  $('#btnSpotlight'),
    categoryCount: $('#categoryCount'),
    catList:       $('#catList'),
  };

  /* ──────────────────────────────────────────────────────────
     State
     ────────────────────────────────────────────────────────── */
  let scanData = null;
  let isLoading = false;
  let useMock = false;          // toggled after first failed fetch
  let termLineCount = 0;
  const accentByKey = Object.fromEntries(CATEGORIES.map((c) => [c.key, c.color]));

  /* ──────────────────────────────────────────────────────────
     Theme + accent
     ────────────────────────────────────────────────────────── */
  const PALETTES = {
    blue:   { accent: '#2466e8', accent2: '#4d8eff' },
    indigo: { accent: '#5b54e6', accent2: '#8b7df5' },
    green:  { accent: '#16a34a', accent2: '#22c55e' },
    rose:   { accent: '#e11d6b', accent2: '#f5587f' },
    slate:  { accent: '#334155', accent2: '#64748b' },
  };

  function initTheme() {
    const t = localStorage.getItem('ac-theme') || 'light';
    document.documentElement.setAttribute('data-theme', t);
    const p = localStorage.getItem('ac-palette') || 'blue';
    applyPalette(p);
  }

  function toggleTheme() {
    const cur = document.documentElement.getAttribute('data-theme');
    const next = cur === 'dark' ? 'light' : 'dark';
    document.documentElement.setAttribute('data-theme', next);
    localStorage.setItem('ac-theme', next);
    termLog(`Tema değiştirildi: ${next === 'dark' ? 'koyu' : 'açık'}`, 'info');
  }

  function applyPalette(name) {
    const p = PALETTES[name] || PALETTES.blue;
    document.documentElement.style.setProperty('--accent', p.accent);
    document.documentElement.style.setProperty('--accent-2', p.accent2);
    localStorage.setItem('ac-palette', name);
    // Update tweaks panel active state
    $$('.tweaks-sw').forEach((sw) => {
      sw.classList.toggle('active', sw.dataset.palette === name);
    });
  }

  initTheme();
  el.themeToggle.addEventListener('click', toggleTheme);

  /* ──────────────────────────────────────────────────────────
     Terminal log
     ────────────────────────────────────────────────────────── */
  function termLog(msg, type = '') {
    const now = new Date();
    const time = now.toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit', second: '2-digit' });
    const line = document.createElement('div');
    line.className = 'term-line';
    const tEl = document.createElement('span');
    tEl.className = 'term-time';
    tEl.textContent = time;
    const mEl = document.createElement('span');
    mEl.className = 'term-msg ' + type;
    mEl.textContent = msg;
    line.appendChild(tEl);
    line.appendChild(mEl);
    el.termBody.appendChild(line);
    el.termBody.scrollTop = el.termBody.scrollHeight;
    termLineCount++;
    el.termCount.textContent = String(termLineCount);
  }

  el.termHead.addEventListener('click', () => {
    const open = el.term.getAttribute('data-open') === 'true';
    el.term.setAttribute('data-open', String(!open));
    el.termHead.setAttribute('aria-expanded', String(!open));
  });

  /* ──────────────────────────────────────────────────────────
     Render categories
     ────────────────────────────────────────────────────────── */
  function renderCategories() {
    CATEGORIES.forEach((cat) => {
      const li = document.createElement('li');
      li.className = ['cat', cat.defaultChecked && 'selected', cat.danger && 'cat-danger']
        .filter(Boolean).join(' ');
      li.dataset.category = cat.key;
      li.dataset.index    = String(cat.index);

      const tagsHtml = cat.tags.map((t) =>
        `<span class="tag tag-${t.style}"><svg class="ic"><use href="#${t.icon}"/></svg>${escapeHtml(t.label)}</span>`
      ).join('');

      li.innerHTML = `
        <button class="cat-row" type="button" data-role="row">
          <span class="cat-ic"><svg class="ic"><use href="#${cat.icon}"/></svg></span>
          <span class="cat-meta">
            <span class="cat-name">${escapeHtml(cat.name)}${tagsHtml ? ' ' + tagsHtml : ''}</span>
            <span class="cat-desc">${escapeHtml(cat.desc)}</span>
          </span>
          <span class="cat-bar"><span class="cat-bar-fill"></span></span>
          <span class="cat-size" data-size="${cat.key}">—</span>
          <label class="switch" onclick="event.stopPropagation()">
            <input type="checkbox" ${cat.defaultChecked ? 'checked' : ''} />
            <span class="switch-slider"></span>
          </label>
          <svg class="ic cat-chev"><use href="#i-chev"/></svg>
        </button>
      `;
      el.catList.appendChild(li);
    });

    el.cats = $$('.cat[data-category]');
    if (el.categoryCount) el.categoryCount.textContent = `${CATEGORIES.length} kategori`;
  }

  /* ──────────────────────────────────────────────────────────
     Utilities
     ────────────────────────────────────────────────────────── */
  function formatBytes(bytes) {
    if (!bytes || bytes === 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.min(units.length - 1, Math.floor(Math.log(bytes) / Math.log(1024)));
    return (bytes / Math.pow(1024, i)).toFixed(i === 0 ? 0 : 1) + ' ' + units[i];
  }

  // Split a human-readable size into [value, unit] for the big number
  function splitSize(human) {
    if (!human) return ['0', 'B'];
    const m = String(human).match(/^([\d.,]+)\s*([A-Za-z]+)?$/);
    if (!m) return [String(human), ''];
    return [m[1].replace(',', '.'), m[2] || 'B'];
  }

  function setLoading(btn, on) {
    if (!btn) return;
    btn.classList.toggle('loading', !!on);
    btn.disabled = !!on;
  }

  function getSelectedIndices() {
    return el.cats
      .filter((c) => $('input[type="checkbox"]', c).checked)
      .map((c) => parseInt(c.dataset.index, 10));
  }

  function getSelectedSubitems(categoryKey) {
    const out = [];
    const container = $(`.subitems[data-cat="${categoryKey}"]`);
    if (!container) return out;
    $$('input[type="checkbox"]', container).forEach((cb) => {
      if (cb.checked) out.push(cb.dataset.subId);
    });
    return out;
  }

  /* ──────────────────────────────────────────────────────────
     Tween helpers
     ────────────────────────────────────────────────────────── */
  function tween(from, to, dur, onUpdate, onDone) {
    const t0 = performance.now();
    function tick(now) {
      const t = Math.min(1, (now - t0) / dur);
      const eased = 1 - Math.pow(1 - t, 3);
      onUpdate(from + (to - from) * eased);
      if (t < 1) requestAnimationFrame(tick);
      else if (onDone) onDone();
    }
    requestAnimationFrame(tick);
  }

  function tweenNumber(elTarget, fromBytes, toBytes, dur = 900) {
    tween(fromBytes, toBytes, dur, (v) => {
      const [val, unit] = splitSize(formatBytes(v));
      elTarget.firstElementChild.textContent = val;          // hnValue
      elTarget.children[1].textContent = unit;               // hnUnit
    });
  }

  /* ──────────────────────────────────────────────────────────
     API + mock
     ────────────────────────────────────────────────────────── */
  async function apiFetch(url, options = {}) {
    if (useMock) return mockApi(url, options);
    try {
      const res = await fetch(url, {
        headers: { 'Content-Type': 'application/json' },
        ...options,
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();
      if (!data.success && data.error) throw new Error(data.error);
      return data;
    } catch (err) {
      // First failure → switch to mock for the rest of the session
      if (!useMock) {
        useMock = true;
        termLog('Sunucu erişilemez — demo verisiyle çalışıyor.', 'info');
      }
      return mockApi(url, options);
    }
  }

  /* Mock API — realistic numbers a typical Mac might see */
  async function mockApi(url, options = {}) {
    await new Promise((r) => setTimeout(r, url === '/api/scan' ? 1200 : 450));

    if (url === '/api/status') {
      return {
        success: true,
        macos_version: 'Sequoia 15.4',
        user: 'ahmet',
        disk_free: '184 GB',
        disk_used_pct: 62,
      };
    }

    if (url === '/api/scan') {
      const sizes = {
        user_cache:      2.4 * 1024 * 1024 * 1024,
        system_cache:    680 * 1024 * 1024,
        app_leftovers:   1.1 * 1024 * 1024 * 1024,
        logs:            410 * 1024 * 1024,
        temp_files:      920 * 1024 * 1024,
        developer:       6.8 * 1024 * 1024 * 1024,
        trash:           3.2 * 1024 * 1024 * 1024,
        browser_cache:   1.6 * 1024 * 1024 * 1024,
        browser_full:    3.8 * 1024 * 1024 * 1024,
        ios_backups:     12.4 * 1024 * 1024 * 1024,
        app_uninstaller: 4.2 * 1024 * 1024 * 1024,
        mail_downloads:  350 * 1024 * 1024,
      };
      const total = Object.values(sizes).reduce((a, b) => a + b, 0);
      const scan = {};
      Object.entries(sizes).forEach(([k, v]) => {
        scan[k] = { size_bytes: v, size_human: formatBytes(v) };
      });
      // Sub-items for select categories
      scan.app_leftovers.subitems = [
        { id: 'Slack',           name: 'Slack',             size_human: '420 MB', is_orphaned: true },
        { id: 'Zoom',            name: 'zoom.us',           size_human: '380 MB', is_orphaned: false },
        { id: 'OldApp',          name: 'Pixelmator Pro',    size_human: '210 MB', is_orphaned: true },
        { id: 'AnotherApp',      name: 'Notion Calendar',   size_human: '95 MB',  is_orphaned: false },
      ];
      scan.developer.subitems = [
        { id: 'DerivedData', name: 'Xcode DerivedData', size_human: '4.2 GB', is_orphaned: true },
        { id: 'iOS DeviceSupport', name: 'iOS DeviceSupport', size_human: '2.1 GB', is_orphaned: true },
        { id: 'Broken links', name: 'Bozuk semboller (12)',  size_human: '512 KB', is_orphaned: true },
      ];
      scan.browser_full.subitems = [
        { id: 'Safari Profile', name: 'Safari profili',  size_human: '1.8 GB' },
        { id: 'Chrome Profile', name: 'Chrome profili',  size_human: '1.4 GB' },
        { id: 'Firefox Profile', name: 'Firefox profili', size_human: '620 MB' },
      ];
      scan.ios_backups.subitems = [
        { id: 'aaaa1111', name: 'iPhone 15 Pro — 2024-12-04', size_human: '6.8 GB' },
        { id: 'bbbb2222', name: 'iPad Pro — 2024-09-22',       size_human: '5.1 GB' },
        { id: 'cccc3333', name: 'iPhone 13 — 2023-06-12',      size_human: '512 MB' },
      ];
      scan.app_uninstaller.subitems = [
        { id: 'Slack',          name: 'Slack',          bundle_id: 'com.tinyspeck.slackmacgap', size_human: '1.2 GB' },
        { id: 'Zoom',           name: 'Zoom',           bundle_id: 'us.zoom.xos',              size_human: '850 MB' },
        { id: 'Spotify',        name: 'Spotify',        bundle_id: 'com.spotify.client',       size_human: '680 MB' },
        { id: 'Microsoft Word', name: 'Microsoft Word', bundle_id: 'com.microsoft.Word',       size_human: '1.5 GB' },
      ];
      scan.mail_downloads.subitems = [
        { id: 'report.pdf',  name: 'report.pdf',  size_human: '140 MB' },
        { id: 'photo.jpg',   name: 'photo.jpg',   size_human: '85 MB'  },
        { id: 'archive.zip', name: 'archive.zip', size_human: '125 MB' },
      ];

      return {
        success: true,
        macos_version: 'Sequoia 15.4',
        user: 'ahmet',
        disk_free: '184 GB',
        disk_used_pct: 62,
        total_bytes: total,
        total_human: formatBytes(total),
        scan,
      };
    }

    if (url === '/api/clean') {
      const payload = JSON.parse(options.body || '{}');
      const cats = payload.categories || [];
      let freed = 0;
      const details = [];
      cats.forEach((idx) => {
        const key = KEY_BY_INDEX[idx];
        const size = (scanData && scanData.scan[key]?.size_bytes) || 0;
        if (size > 0) {
          details.push({ category: key, freed: formatBytes(size) });
          freed += size;
        }
      });
      return {
        success: true,
        freed_bytes: freed,
        freed_human: formatBytes(freed),
        items_cleaned: cats.length,
        disk_free: formatBytes((184 * 1024 * 1024 * 1024) + freed),
        details,
        errors: [],
      };
    }

    if (url === '/api/spotlight-reindex') {
      return { success: true };
    }

    return { success: true };
  }

  /* ──────────────────────────────────────────────────────────
     System status
     ────────────────────────────────────────────────────────── */
  async function fetchStatus() {
    termLog('Sistem bilgileri alınıyor…', 'info');
    try {
      const data = await apiFetch('/api/status');
      el.sysVersion.textContent = data.macos_version || '—';
      el.sysUser.textContent = data.user || '—';
      el.sysDiskFree.textContent = data.disk_free || '—';
      [el.sysVersion, el.sysUser, el.sysDiskFree].forEach((e) => e.classList.remove('loading'));

      // Disk donut
      const usedPct = Math.min(100, Math.max(0, data.disk_used_pct ?? 35));
      animateDonut(usedPct);
      el.diskBarFill.style.width = usedPct + '%';

      termLog(`macOS ${data.macos_version} · ${data.user} · ${data.disk_free} boş`, 'success');
    } catch (err) {
      termLog(`Sistem bilgisi alınamadı: ${err.message}`, 'error');
      [el.sysVersion, el.sysUser, el.sysDiskFree].forEach((e) => {
        e.textContent = '—';
        e.classList.remove('loading');
      });
    }
  }

  function animateDonut(pct) {
    el.donutFill.setAttribute('stroke-dasharray', `${pct} ${100 - pct}`);
    tween(0, pct, 900, (v) => {
      el.donutNum.textContent = Math.round(v) + '%';
    });
  }

  /* ──────────────────────────────────────────────────────────
     Scan flow
     ────────────────────────────────────────────────────────── */
  async function handleScan() {
    if (isLoading) return;
    isLoading = true;
    setLoading(el.btnScan, true);
    el.btnClean.disabled = true;
    el.resultsPanel.hidden = true;
    el.hero.setAttribute('data-state', 'scanning');
    el.heroEyebrow.textContent = 'Tarama yapılıyor…';
    $$('.subitems').forEach((s) => s.remove());
    el.cats.forEach((c) => c.removeAttribute('data-open'));

    termLog('Tarama başlatılıyor…', 'info');

    try {
      const data = await apiFetch('/api/scan');
      scanData = data;

      if (data.disk_free) el.sysDiskFree.textContent = data.disk_free;
      if (data.macos_version) el.sysVersion.textContent = data.macos_version;
      if (data.user) el.sysUser.textContent = data.user;
      [el.sysVersion, el.sysUser, el.sysDiskFree].forEach((e) => e.classList.remove('loading'));

      const scan = data.scan || {};
      const totalBytes = data.total_bytes || Object.values(scan).reduce((a, s) => a + (s.size_bytes || 0), 0);
      const maxBytes = Math.max(...Object.values(scan).map((s) => s.size_bytes || 0), 1);

      // Update each category row
      Object.entries(scan).forEach(([key, info]) => {
        const card = $(`.cat[data-category="${key}"]`);
        if (!card) return;
        const sizeEl = $(`.cat-size[data-size="${key}"]`, card);
        if (sizeEl) sizeEl.textContent = info.size_human || formatBytes(info.size_bytes || 0);
        const fill = $('.cat-bar-fill', card);
        if (fill) {
          fill.classList.remove('size-lg', 'size-xl');
          if (info.size_bytes > 5 * 1024 * 1024 * 1024) fill.classList.add('size-xl');
          else if (info.size_bytes > 1024 * 1024 * 1024) fill.classList.add('size-lg');
          requestAnimationFrame(() => {
            fill.style.width = Math.max(2, (info.size_bytes / maxBytes) * 100) + '%';
          });
        }

        termLog(`  ${CAT_BY_KEY[key]?.name || key}: ${info.size_human || formatBytes(info.size_bytes)}`);

        if (info.subitems && info.subitems.length > 0) {
          renderSubitems(card, key, info.subitems);
        }
      });

      // Hero number + stacked bar
      revealHeroResult(scan, totalBytes);

      el.heroEyebrow.textContent = `Tarama tamamlandı · ${data.total_human || formatBytes(totalBytes)} temizlenebilir`;
      el.hero.setAttribute('data-state', 'scanned');
      termLog(`Tarama tamamlandı — toplam ${data.total_human || formatBytes(totalBytes)}`, 'success');

      el.btnClean.disabled = false;
    } catch (err) {
      termLog(`Tarama hatası: ${err.message}`, 'error');
      el.hero.setAttribute('data-state', 'idle');
      el.heroEyebrow.textContent = 'Hata · Tarama tamamlanamadı';
    } finally {
      setLoading(el.btnScan, false);
      isLoading = false;
    }
  }

  function revealHeroResult(scan, totalBytes) {
    // Title / lead transform
    el.heroTitle.textContent = 'Hazır temizlenmeye.';
    el.heroLead.textContent = 'Aşağıdaki kategorilerden istediğinizi seçin. Tüm değişiklikler onayınızdan sonra uygulanır.';

    // Big number with count-up
    el.heroNumber.hidden = false;
    tweenNumber(el.heroNumber, 0, totalBytes, 1000);

    // Stacked bar
    el.heroBar.hidden = false;
    el.heroBarTrack.innerHTML = '';
    el.heroBarLegend.innerHTML = '';

    const sortedEntries = Object.entries(scan)
      .filter(([, v]) => v.size_bytes > 0)
      .sort((a, b) => b[1].size_bytes - a[1].size_bytes);

    sortedEntries.forEach(([key, info]) => {
      const pct = (info.size_bytes / totalBytes) * 100;
      const seg = document.createElement('span');
      seg.style.background = accentByKey[key];
      el.heroBarTrack.appendChild(seg);
      requestAnimationFrame(() => { seg.style.width = pct + '%'; });
    });

    // Legend — top 5
    sortedEntries.slice(0, 5).forEach(([key, info]) => {
      const item = document.createElement('span');
      item.className = 'lg';
      const sw = document.createElement('span');
      sw.className = 'sw';
      sw.style.background = accentByKey[key];
      const txt = document.createElement('span');
      txt.innerHTML = `${escapeHtml(CAT_BY_KEY[key]?.name || key)} <b>${escapeHtml(info.size_human)}</b>`;
      item.appendChild(sw);
      item.appendChild(txt);
      el.heroBarLegend.appendChild(item);
    });
  }

  /* Sub-items rendering — table form below row */
  function renderSubitems(card, key, subitems) {
    const wrap = document.createElement('div');
    wrap.className = 'subitems';
    wrap.dataset.cat = key;

    subitems.forEach((sub) => {
      const row = document.createElement('div');
      row.className = 'subitem-row';

      let checkedAttr = '';
      if (key === 'app_leftovers') checkedAttr = sub.is_orphaned ? 'checked' : '';
      else if (key === 'developer') checkedAttr = 'checked';
      else if (key === 'browser_full') checkedAttr = '';
      else if (key === 'ios_backups') checkedAttr = '';
      else if (key === 'app_uninstaller') checkedAttr = '';
      else if (key === 'mail_downloads') checkedAttr = 'checked';

      let badge = '';
      if (key === 'app_leftovers') {
        const cls = sub.is_orphaned ? 'orphaned' : 'installed';
        const label = sub.is_orphaned ? 'kalıntı' : 'yüklü';
        badge = `<span class="subitem-badge ${cls}">${label}</span>`;
      } else if (key === 'ios_backups') {
        badge = `<span class="subitem-badge orphaned">yedek</span>`;
      } else if (key === 'app_uninstaller') {
        badge = `<span class="subitem-badge orphaned">uygulama</span>`;
      }

      row.innerHTML = `
        <input type="checkbox" data-sub-id="${escapeAttr(sub.id)}" ${checkedAttr}>
        <span class="subitem-name" title="${escapeAttr(sub.name)}">
          <b>${escapeHtml(sub.name)}</b>
        </span>
        ${badge}
        <span class="subitem-size">${escapeHtml(sub.size_human || '')}</span>
      `;
      wrap.appendChild(row);
    });

    card.appendChild(wrap);

    // Sync parent toggle with sub-items
    const parentCb = $('.switch input[type="checkbox"]', card);
    const subCbs = $$('input[type="checkbox"]', wrap);
    subCbs.forEach((scb) => {
      scb.addEventListener('change', (e) => {
        e.stopPropagation();
        const anyChecked = subCbs.some((cb) => cb.checked);
        parentCb.checked = anyChecked;
        card.classList.toggle('selected', anyChecked);
      });
    });
    parentCb.addEventListener('change', () => {
      subCbs.forEach((scb) => (scb.checked = parentCb.checked));
    });
    const anyChecked = subCbs.some((cb) => cb.checked);
    parentCb.checked = anyChecked;
    card.classList.toggle('selected', anyChecked);
  }

  /* ──────────────────────────────────────────────────────────
     Clean flow
     ────────────────────────────────────────────────────────── */
  async function handleClean() {
    if (isLoading) return;
    const selected = getSelectedIndices();
    if (selected.length === 0) {
      termLog('Lütfen en az bir kategori seçin.', 'error');
      return;
    }
    const names = selected.map((idx) => CAT_BY_KEY[KEY_BY_INDEX[idx]]?.name || `#${idx}`);
    const confirmed = confirm(
      `Şu kategoriler temizlenecek:\n\n${names.map((n) => `• ${n}`).join('\n')}\n\nDevam etmek istiyor musunuz?`
    );
    if (!confirmed) {
      termLog('Temizlik iptal edildi.', 'info');
      return;
    }

    isLoading = true;
    setLoading(el.btnClean, true);
    setLoading(el.btnScan, true);
    el.resultsPanel.hidden = true;
    el.hero.setAttribute('data-state', 'cleaning');
    el.heroEyebrow.textContent = 'Temizlik yapılıyor…';
    termLog(`Temizlik başlatılıyor (${selected.length} kategori)…`, 'info');

    try {
      const payload = {
        categories: selected,
        app_leftovers_selected: getSelectedSubitems('app_leftovers'),
        browser_full_selected: getSelectedSubitems('browser_full'),
        developer_selected: getSelectedSubitems('developer'),
        ios_backups_selected: getSelectedSubitems('ios_backups'),
        app_uninstaller_selected: getSelectedSubitems('app_uninstaller'),
      };
      const data = await apiFetch('/api/clean', {
        method: 'POST',
        body: JSON.stringify(payload),
      });

      el.resultsPanel.hidden = false;
      el.resultsPanel.classList.remove('error');
      el.resultsTitle.textContent = 'Temizlik tamamlandı';
      const freedText = data.freed_human || formatBytes(data.freed_bytes || 0);
      el.resultsFreed.textContent = freedText;
      el.resultsSub.textContent = `${data.items_cleaned || selected.length} kategori · Yeni boş alan ${data.disk_free || '—'}`;
      if (data.disk_free) el.sysDiskFree.textContent = data.disk_free;

      el.resultsChips.innerHTML = '';
      (data.details || []).forEach((d) => {
        const name = CAT_BY_KEY[d.category]?.name || d.category;
        const chip = document.createElement('div');
        chip.className = 'result-chip';
        chip.innerHTML = `${escapeHtml(name)} <span class="chip-freed">${escapeHtml(d.freed)}</span>`;
        el.resultsChips.appendChild(chip);
        termLog(`  ✓ ${name}: ${d.freed}`, 'success');
      });

      (data.errors || []).forEach((e) => termLog(`  ✗ Hata: ${e}`, 'error'));

      termLog(`Toplam ${freedText} alan kazanıldı.`, 'success');

      // Reset categories' bars
      $$('.cat-bar-fill').forEach((b) => { b.style.width = '0%'; b.classList.remove('size-lg', 'size-xl'); });
      $$('.cat-size').forEach((s) => { s.textContent = '—'; });
      $$('.subitems').forEach((s) => s.remove());
      scanData = null;

      el.hero.setAttribute('data-state', 'idle');
      el.heroEyebrow.textContent = 'Temizlik tamamlandı · Tekrar tarayın';
      el.heroNumber.hidden = true;
      el.heroBar.hidden = true;
      el.heroTitle.textContent = "Mac'iniz daha hızlı.";
      el.heroLead.textContent = 'Yeniden tarayarak daha fazla temizlenebilir dosya keşfedin.';
    } catch (err) {
      termLog(`Temizlik hatası: ${err.message}`, 'error');
      el.resultsPanel.hidden = false;
      el.resultsPanel.classList.add('error');
      el.resultsTitle.textContent = 'Hata oluştu';
      el.resultsFreed.textContent = '';
      el.resultsSub.textContent = err.message;
      el.resultsChips.innerHTML = '';
      el.hero.setAttribute('data-state', 'idle');
      el.heroEyebrow.textContent = 'Hata · Temizlik tamamlanamadı';
    } finally {
      setLoading(el.btnClean, false);
      setLoading(el.btnScan, false);
      el.btnClean.disabled = true;
      isLoading = false;
    }
  }

  el.resultsClose.addEventListener('click', () => {
    el.resultsPanel.hidden = true;
  });

  /* ──────────────────────────────────────────────────────────
     Spotlight reindex
     ────────────────────────────────────────────────────────── */
  async function handleSpotlight() {
    if (el.btnSpotlight.disabled) return;
    setLoading(el.btnSpotlight, true);
    termLog('Spotlight yeniden indeksleme tetikleniyor…', 'info');
    try {
      await apiFetch('/api/spotlight-reindex', { method: 'POST', body: '{}' });
      termLog('Spotlight indeksleme arka planda başladı. Birkaç dakika sürebilir.', 'success');
    } catch (err) {
      termLog(`Spotlight hatası: ${err.message}`, 'error');
    } finally {
      setLoading(el.btnSpotlight, false);
    }
  }

  /* ──────────────────────────────────────────────────────────
     Bindings
     ────────────────────────────────────────────────────────── */
  el.btnScan.addEventListener('click', handleScan);
  el.btnClean.addEventListener('click', handleClean);
  if (el.btnSpotlight) el.btnSpotlight.addEventListener('click', handleSpotlight);

  // Keyboard shortcuts
  document.addEventListener('keydown', (e) => {
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 's' && !isLoading) {
      e.preventDefault(); handleScan();
    }
    if ((e.metaKey || e.ctrlKey) && (e.key === 'Enter' || e.key === '\n') && !el.btnClean.disabled) {
      e.preventDefault(); handleClean();
    }
  });

  /* ──────────────────────────────────────────────────────────
     Escapers
     ────────────────────────────────────────────────────────── */
  function escapeHtml(s) {
    const d = document.createElement('div');
    d.textContent = String(s ?? '');
    return d.innerHTML;
  }
  function escapeAttr(s) {
    return String(s ?? '').replace(/"/g, '&quot;').replace(/</g, '&lt;');
  }

  /* ──────────────────────────────────────────────────────────
     Tweaks (in-page palette picker — host-aware)
     ────────────────────────────────────────────────────────── */
  function buildTweaks() {
    const panel = document.createElement('div');
    panel.className = 'tweaks';
    panel.innerHTML = `
      <div class="tweaks-head">
        <span class="tweaks-title">Tweaks</span>
        <button class="icon-btn" id="tweaksClose" aria-label="Kapat"><svg class="ic"><use href="#i-x"/></svg></button>
      </div>
      <div class="tweaks-row">
        <span>Aksent</span>
        <span class="tweaks-swatches">
          <span class="tweaks-sw" data-palette="blue"   style="background:#2466e8"></span>
          <span class="tweaks-sw" data-palette="indigo" style="background:#5b54e6"></span>
          <span class="tweaks-sw" data-palette="green"  style="background:#16a34a"></span>
          <span class="tweaks-sw" data-palette="rose"   style="background:#e11d6b"></span>
          <span class="tweaks-sw" data-palette="slate"  style="background:#334155"></span>
        </span>
      </div>
      <div class="tweaks-row">
        <span>Tema</span>
        <button class="chip-btn" id="tweaksTheme">Değiştir</button>
      </div>
    `;
    document.body.appendChild(panel);

    panel.querySelectorAll('.tweaks-sw').forEach((sw) => {
      sw.addEventListener('click', () => applyPalette(sw.dataset.palette));
    });
    panel.querySelector('#tweaksClose').addEventListener('click', () => {
      panel.classList.remove('open');
      try { window.parent.postMessage({ type: '__edit_mode_dismissed' }, '*'); } catch {}
    });
    panel.querySelector('#tweaksTheme').addEventListener('click', toggleTheme);

    applyPalette(localStorage.getItem('ac-palette') || 'blue');

    // Host-mode listeners (toggle visibility)
    window.addEventListener('message', (ev) => {
      const d = ev.data || {};
      if (d.type === '__activate_edit_mode') panel.classList.add('open');
      if (d.type === '__deactivate_edit_mode') panel.classList.remove('open');
    });
    try { window.parent.postMessage({ type: '__edit_mode_available' }, '*'); } catch {}
  }
  buildTweaks();

  /* ──────────────────────────────────────────────────────────
     Init
     ────────────────────────────────────────────────────────── */
  el.term.setAttribute('data-open', 'false');
  renderCategories();

  // Wire card interactions now that el.cats is populated
  el.cats.forEach((card) => {
    const row = $('[data-role="row"]', card);
    const cb  = $('input[type="checkbox"]', card);

    cb.addEventListener('change', () => {
      card.classList.toggle('selected', cb.checked);
    });

    row.addEventListener('click', (e) => {
      if (e.target.closest('.switch')) return;
      const hasSubs = card.querySelector('.subitems');
      if (hasSubs) {
        const open = card.getAttribute('data-open') === 'true';
        card.setAttribute('data-open', String(!open));
      } else {
        cb.checked = !cb.checked;
        cb.dispatchEvent(new Event('change'));
      }
    });
  });

  el.btnSelectAll.addEventListener('click', () => {
    el.cats.forEach((card) => {
      const cb = $('input[type="checkbox"]', card);
      cb.checked = true;
      card.classList.add('selected');
      $$('.subitems input[type="checkbox"]', card).forEach((s) => (s.checked = true));
    });
    termLog('Tüm kategoriler seçildi.', 'info');
  });

  el.btnSelectNone.addEventListener('click', () => {
    el.cats.forEach((card) => {
      const cb = $('input[type="checkbox"]', card);
      cb.checked = false;
      card.classList.remove('selected');
      $$('.subitems input[type="checkbox"]', card).forEach((s) => (s.checked = false));
    });
    termLog('Tüm seçimler kaldırıldı.', 'info');
  });

  termLog('Apple Cleanup başlatıldı.', 'success');
  fetchStatus();
})();
