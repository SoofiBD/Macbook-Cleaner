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
    {
      key: 'diagnostic_reports', index: 13, name: 'Tanılama Raporları',
      desc: 'Çökme ve tanılama kayıtları',
      icon: 'i-log', color: '#0bb8c9', defaultChecked: true, danger: false, tags: [],
    },
    {
      key: 'quicklook_cache', index: 14, name: 'QuickLook Cache',
      desc: 'Önizleme küçük resim önbelleği',
      icon: 'i-cache', color: '#4d8eff', defaultChecked: true, danger: false, tags: [],
    },
    {
      key: 'saved_app_state', index: 15, name: 'Kaydedilmiş Uygulama Durumu',
      desc: 'Pencere/oturum geri yükleme verisi',
      icon: 'i-temp', color: '#d97706', defaultChecked: false, danger: false, tags: [],
    },
    {
      key: 'other_trash', index: 16, name: 'Diğer Ciltlerin Çöpü',
      desc: 'Harici disklerdeki çöp kutuları',
      icon: 'i-trash', color: '#8b8f99', defaultChecked: true, danger: false, tags: [],
    },
    {
      key: 'project_artifacts', index: 17, name: 'Proje Yapıları',
      desc: 'Eski node_modules, target, .build, build…',
      icon: 'i-wrench', color: '#16a34a', defaultChecked: false, danger: false, tags: [],
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
    forecastChip:  $('#forecastChip'),
    sysForecast:   $('#sysForecast'),
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
    dryRunToggle:  $('#dryRunToggle'),
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

    btnSpotlight:   $('#btnSpotlight'),
    btnFlushDns:    $('#btnFlushDns'),
    btnPurgeRam:    $('#btnPurgeRam'),
    btnLaunchAgents: $('#btnLaunchAgents'),
    btnThinSnapshots: $('#btnThinSnapshots'),
    categoryCount: $('#categoryCount'),
    catList:       $('#catList'),
  };

  /* ──────────────────────────────────────────────────────────
     State
     ────────────────────────────────────────────────────────── */
  let scanData = null;
  let isLoading = false;
  let termLineCount = 0;
  const filesSelected = new Set();   // rowIds selected in the Dosyalar tab
  let filesQuery = '';               // current Dosyalar search query
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
    const t = localStorage.getItem('ac-theme') || 'dark';
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
          <span class="cat-size" data-size="${cat.key}">—</span><span class="cat-risk" data-risk="${escapeAttr(cat.key)}"></span>
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
  // Shared with the GSAP layer (anim.js) for size count-up animations.
  window.formatBytesShared = formatBytes;

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
     API
     ────────────────────────────────────────────────────────── */
  const CLEANUP_TOKEN =
    document.querySelector('meta[name="cleanup-token"]')?.content || '';

  async function apiFetch(url, options = {}) {
    const res = await fetch(url, {
      ...options,
      headers: {
        'Content-Type': 'application/json',
        'X-Cleanup-Token': CLEANUP_TOKEN,
        ...(options.headers || {}),
      },
    });
    if (!res.ok) throw new Error(`Sunucu hatası (HTTP ${res.status})`);
    const data = await res.json();
    if (!data.success && data.error) throw new Error(data.error);
    return data;
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
    fetchForecast();
  }

  async function fetchForecast() {
    if (!el.forecastChip) return;
    try {
      const data = await apiFetch('/api/forecast');
      if (!data || !data.success) return;
      if (data.days_until_full != null) {
        el.sysForecast.textContent = `~${data.days_until_full} gün içinde dolacak`;
        el.forecastChip.hidden = false;
        termLog(`Depolama tahmini: ~${data.days_until_full} gün içinde dolabilir.`, 'info');
      } else if (data.history_points < 2) {
        // Not enough history yet — keep collecting, stay quiet in the UI.
        el.forecastChip.hidden = true;
      } else {
        el.sysForecast.textContent = 'Sabit — risk yok';
        el.forecastChip.hidden = false;
      }
    } catch (err) {
      /* forecast is best-effort; ignore failures */
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
      filesSelected.clear();   // a fresh scan invalidates prior file selections

      if (data.disk_free) el.sysDiskFree.textContent = data.disk_free;
      if (data.macos_version) el.sysVersion.textContent = data.macos_version;
      if (data.user) el.sysUser.textContent = data.user;
      [el.sysVersion, el.sysUser, el.sysDiskFree].forEach((e) => e.classList.remove('loading'));

      const scan = data.scan || {};
      const totalBytes = window.ScanUtil.computeTotalBytes(data);
      const maxBytes = Math.max(...Object.values(scan).map((s) => s.size_bytes || 0), 1);

      // Update each category row
      Object.entries(scan).forEach(([key, info]) => {
        const card = $(`.cat[data-category="${key}"]`);
        if (!card) return;
        const sizeEl = $(`.cat-size[data-size="${key}"]`, card);
        if (sizeEl) {
          sizeEl.textContent = info.size_human || formatBytes(info.size_bytes || 0);
          sizeEl.dataset.bytes = info.size_bytes || 0;
        }
        const riskEl = $(`.cat-risk[data-risk="${key}"]`, card);
        if (riskEl) {
          const risk = info.risk;
          if (risk === 'danger' || risk === 'caution') {
            riskEl.textContent = risk === 'danger' ? '⚠ Riskli' : '⚠ Dikkat';
            riskEl.className = `cat-risk risk-${risk}`;
          } else {
            riskEl.textContent = '';
            riskEl.className = 'cat-risk';
          }
        }
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

      window.AppAnim?.afterScan?.();
      el.btnClean.disabled = false;
    } catch (err) {
      termLog(`Tarama hatası: ${err.message}`, 'error');
      el.hero.setAttribute('data-state', 'idle');
      el.heroEyebrow.textContent = 'Sunucu çalışmıyor · Tarama yapılamadı';
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
  // Human-readable descriptions for developer caches (keyed by subitem id).
  // Explains what each cache is and how it comes back, so the user knows
  // exactly what they are deleting. Inspired by npkill/ClearDisk.
  const CACHE_DESCRIPTIONS = {
    derived_data: 'Xcode derleme ürünleri ve indeksleri. Proje açılınca otomatik yeniden oluşur.',
    broken_links: 'Hedefi silinmiş sembolik bağlantılar. Güvenle kaldırılabilir.',
    brew_cache: 'İndirilmiş Homebrew şişe/paket dosyaları. brew install ile tekrar iner.',
    docker_prune: 'Docker imajları, kapsayıcıları ve volume\'ları. Çalışan kapsayıcı verisi kaybolabilir!',
    npm_cache: 'npmjs.org\'dan indirilen paket arşivleri. npm install ile tekrar iner.',
    pip_cache: 'İndirilmiş Python wheel/sdist dosyaları. pip install ile tekrar iner.',
    device_support: 'Bağlı iPhone/iPad hata ayıklama sembolleri. Cihaz bağlanınca tekrar iner.',
    coresim_caches: 'CoreSimulator dyld ve framework önbellekleri. Otomatik yeniden oluşur.',
    xcode_archives: 'App Store/dağıtım için arşivlenmiş derlemeler. Xcode\'dan tekrar arşivlenir.',
    cocoapods_cache: 'İndirilmiş pod spec ve kaynakları. pod install ile tekrar iner.',
    pnpm_cache: 'İçerik adresli pnpm paket deposu. pnpm install ile tekrar iner.',
    yarn_cache: 'Önbelleğe alınmış Yarn paketleri. yarn install ile tekrar iner.',
    gradle_cache: 'İndirilmiş JAR\'lar ve derleme çıktıları. gradle build ile tekrar iner.',
    maven_repo: 'Yerel Maven deposu (.m2). mvn build ile tekrar iner.',
    simctl_unavailable: 'Kullanılamayan (eski iOS) simülatörleri siler. Yer açar.',
    xcode_products: 'Xcode ürün derleme çıktıları. Sonraki derlemede yeniden oluşur.',
    simulator_logs: 'Simülatör çökme raporları ve günlükleri. İstediğiniz zaman silinebilir.',
    simulator_devices: 'Simülatörleri fabrika durumuna sıfırlar (yüklü uygulama/veri). Cihaz kaydı korunur.',
    font_caches: 'Sistem yazı tipi önbelleği. Otomatik yeniden oluşur.',
    brew_cleanup: 'brew cleanup -s çalıştırır: eski sürümleri ve önbelleği temizler.',
    swift_pm_cache: 'İndirilmiş Swift paketleri. swift build ile tekrar iner.',
    xcode_logs: 'DerivedData içindeki Xcode derleme günlükleri. Güvenle silinir.',
    xcode_previews: 'SwiftUI önizleme simülatör verisi. Sonraki önizlemede yeniden oluşur.',
    carthage_cache: 'Carthage bağımlılık önbelleği. carthage update ile tekrar iner.',
    bun_cache: 'Önbelleğe alınmış Bun paketleri. bun install ile tekrar iner.',
    deno_cache: 'Önbelleğe alınmış Deno modülleri. deno run ile tekrar iner.',
    conda_pkgs: 'Önbelleğe alınmış Conda paketleri. conda install ile tekrar iner.',
    uv_cache: 'uv (hızlı pip) paket önbelleği. uv pip install ile tekrar iner.',
    poetry_cache: 'Önbelleğe alınmış Poetry bağımlılıkları. poetry install ile tekrar iner.',
    go_modules: 'Go modül indirme önbelleği. go mod download ile tekrar iner.',
    cargo_registry: 'Önbelleğe alınmış Rust crate kaynakları. cargo build ile tekrar iner.',
    composer_cache: 'Önbelleğe alınmış PHP paketleri. composer install ile tekrar iner.',
    gradle_wrapper: 'Gradle wrapper dağıtım ikilileri. Sonraki gradle build ile tekrar iner.',
    sbt_ivy_cache: 'sbt/Ivy ile önbelleğe alınmış Scala/Java bağımlılıkları. Tekrar iner.',
    bazel_cache: 'Bazel derleme ve repo önbellekleri. Sonraki bazel build ile yeniden oluşur.',
    flutter_pub_cache: 'Önbelleğe alınmış Dart/Flutter paketleri. flutter pub get ile tekrar iner.',
    jetbrains_cache: 'JetBrains IDE önbellekleri (IntelliJ, WebStorm vb.). IDE yeniden başlayınca oluşur.',
    playwright_cache: 'Playwright test tarayıcı ikilileri. npx playwright install ile tekrar iner.',
    puppeteer_cache: 'Puppeteer için indirilen Chromium ikilileri. Tekrar iner.',
    prisma_cache: 'Prisma ORM sorgu motoru ikilileri. npx prisma generate ile tekrar iner.',
    huggingface_cache: 'İndirilmiş AI/ML modelleri ve veri kümeleri. Tekrar iner (büyük olabilir).',
  };

  // Age-based suggestion for a cache sub-item, based on how long since it was
  // last touched and how big it is. Mirrors ClearDisk's heuristic, in Turkish.
  function suggestionFor(sub) {
    const days = sub.age_days;
    if (days == null) return '';
    const gb = (sub.size_bytes || 0) / (1024 * 1024 * 1024);
    if (days > 90 && gb >= 1) {
      return `⚠️ ${days} gündür kullanılmadı, ${sub.size_human} — güvenle temizlenebilir`;
    }
    if (days > 60) {
      return `💡 ${days} gündür kullanılmıyor — temizlemeyi düşünün`;
    }
    if (days > 30 && gb >= 5) {
      return `💡 ${days} gün önce, ${sub.size_human} ile büyük`;
    }
    return '';
  }

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
      // Project artifacts: pre-select only stale ones (untouched > 30 days)
      else if (key === 'project_artifacts') checkedAttr = sub.is_orphaned ? 'checked' : '';

      let badge = '';
      if (key === 'app_leftovers') {
        const cls = sub.is_orphaned ? 'orphaned' : 'installed';
        const label = sub.is_orphaned ? 'kalıntı' : 'yüklü';
        badge = `<span class="subitem-badge ${cls}">${label}</span>`;
      } else if (key === 'ios_backups') {
        badge = `<span class="subitem-badge orphaned">yedek</span>`;
      } else if (key === 'app_uninstaller') {
        badge = `<span class="subitem-badge orphaned">uygulama</span>`;
      } else if (key === 'project_artifacts') {
        const cls = sub.is_orphaned ? 'orphaned' : 'installed';
        const typeLabel = sub.type || 'proje';
        const ageLabel = sub.is_orphaned && sub.days_since != null
          ? ` · ${sub.days_since}g` : '';
        badge = `<span class="subitem-badge ${cls}">${escapeHtml(typeLabel)}${ageLabel}</span>`;
      }

      // Secondary line: static cache description, plus a per-project breakdown
      // (sub.detail, e.g. DerivedData "MyApp: 2.3 GB, Other: 1.1 GB") when present.
      const desc = CACHE_DESCRIPTIONS[sub.id] || '';
      const hint = suggestionFor(sub);
      const descHtml = [
        desc ? `<span class="subitem-desc">${escapeHtml(desc)}</span>` : '',
        sub.detail ? `<span class="subitem-desc subitem-detail">${escapeHtml(sub.detail)}</span>` : '',
        hint ? `<span class="subitem-desc subitem-hint">${escapeHtml(hint)}</span>` : '',
      ].join('');

      row.innerHTML = `
        <input type="checkbox" data-sub-id="${escapeAttr(sub.id)}" ${checkedAttr}>
        <span class="subitem-name" title="${escapeAttr(desc || sub.path || sub.name)}">
          <b>${escapeHtml(sub.name)}</b>
          ${descHtml}
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

    const dangerSelected = selected
      .map((idx) => KEY_BY_INDEX[idx])
      .filter((key) => scanData?.scan?.[key]?.risk === 'danger' || CAT_BY_KEY[key]?.danger === true);
    if (dangerSelected.length > 0) {
      const dnames = dangerSelected.map((k) => CAT_BY_KEY[k]?.name || k).join(', ');
      const dangerOk = confirm(
        `RİSKLİ kategoriler seçildi (${dnames}). Bu veriler kalıcı olarak silinir ve geri alınamaz. Devam edilsin mi?`
      );
      if (!dangerOk) {
        termLog('Riskli kategoriler onaylanmadı, temizlik iptal edildi.', 'info');
        return;
      }
    }

    isLoading = true;
    setLoading(el.btnClean, true);
    setLoading(el.btnScan, true);
    el.resultsPanel.hidden = true;
    el.hero.setAttribute('data-state', 'cleaning');
    el.heroEyebrow.textContent = 'Temizlik yapılıyor…';
    termLog(`Temizlik başlatılıyor (${selected.length} kategori)…`, 'info');

    try {
      const dryRun = !!(el.dryRunToggle && el.dryRunToggle.checked);
      const payload = {
        categories: selected,
        dry_run: dryRun,
        app_leftovers_selected: getSelectedSubitems('app_leftovers'),
        browser_full_selected: getSelectedSubitems('browser_full'),
        developer_selected: getSelectedSubitems('developer'),
        ios_backups_selected: getSelectedSubitems('ios_backups'),
        app_uninstaller_selected: getSelectedSubitems('app_uninstaller'),
        project_artifacts_selected: getSelectedSubitems('project_artifacts'),
      };
      const data = await apiFetch('/api/clean', {
        method: 'POST',
        body: JSON.stringify(payload),
      });

      el.resultsPanel.hidden = false;
      el.resultsPanel.classList.remove('error');
      window.AppAnim?.pop?.(el.resultsPanel);
      window.AppAnim?.bindResultsDrag?.();
      el.resultsTitle.textContent = data.dry_run
        ? 'Önizleme (hiçbir şey silinmedi)'
        : 'Temizlik tamamlandı';
      // In dry-run the disk delta is 0, so show the estimate as the headline.
      const freedText = data.dry_run
        ? (data.estimated_human || formatBytes(data.estimated_bytes || 0))
        : (data.freed_human || formatBytes(data.freed_bytes || 0));
      el.resultsFreed.textContent = freedText;
      const subParts = [`${data.items_cleaned || selected.length} kategori`,
                        `Yeni boş alan ${data.disk_free || '—'}`];
      if (data.estimated_human && data.freed_source === 'df') {
        subParts.push(`Tahmini taranan: ${data.estimated_human}`);
      }
      el.resultsSub.textContent = subParts.join(' · ');
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
    termLog('Spotlight dizini sıfırlanıyor (Videodaki Siri & Spotlight Simülasyonu)…', 'info');
    try {
      const data = await apiFetch('/api/spotlight-reindex', { method: 'POST', body: '{}' });
      if (data.success) {
        termLog('✓ Spotlight dizini arka planda başarıyla sıfırlandı ve yeniden oluşturuluyor.', 'success');
      }
    } catch (err) {
      termLog(`✗ Spotlight Sıfırlama Hatası: ${err.message}`, 'error');
    } finally {
      setLoading(el.btnSpotlight, false);
    }
  }

  /* ──────────────────────────────────────────────────────────
     Maintenance handlers
     ────────────────────────────────────────────────────────── */
  async function handleFlushDns() {
    if (el.btnFlushDns.disabled) return;
    setLoading(el.btnFlushDns, true);
    termLog('DNS önbelleği temizleniyor…', 'info');
    try {
      const data = await apiFetch('/api/flush-dns', { method: 'POST', body: '{}' });
      termLog(data.message || 'DNS önbelleği temizlendi.', 'success');
    } catch (err) {
      termLog(`DNS hatası: ${err.message}`, 'error');
    } finally {
      setLoading(el.btnFlushDns, false);
    }
  }

  async function handlePurgeRam() {
    if (el.btnPurgeRam.disabled) return;
    setLoading(el.btnPurgeRam, true);
    termLog('RAM önbelleği boşaltılıyor…', 'info');
    try {
      const data = await apiFetch('/api/purge-ram', { method: 'POST', body: '{}' });
      termLog(data.message || 'RAM önbelleği boşaltıldı.', 'success');
    } catch (err) {
      termLog(`RAM hatası: ${err.message}`, 'error');
    } finally {
      setLoading(el.btnPurgeRam, false);
    }
  }

  async function handleLaunchAgents() {
    if (el.btnLaunchAgents.disabled) return;
    setLoading(el.btnLaunchAgents, true);
    termLog('Bozuk LaunchAgents temizleniyor…', 'info');
    try {
      const data = await apiFetch('/api/launchagents-clean', { method: 'POST', body: '{}' });
      termLog(`LaunchAgents temizlendi. ${data.removed ?? 0} dosya kaldırıldı.`, 'success');
    } catch (err) {
      termLog(`LaunchAgents hatası: ${err.message}`, 'error');
    } finally {
      setLoading(el.btnLaunchAgents, false);
    }
  }

  async function handleThinSnapshots() {
    if (el.btnThinSnapshots.disabled) return;
    setLoading(el.btnThinSnapshots, true);
    termLog('Yerel snapshotlar inceltiliyor…', 'info');
    try {
      const data = await apiFetch('/api/thin-snapshots', { method: 'POST', body: '{}' });
      termLog(`Snapshot: ${data.snapshots_before} → ${data.snapshots_after} · Boş alan ${data.disk_free || '—'}`, 'success');
      if (data.disk_free) el.sysDiskFree.textContent = data.disk_free;
    } catch (err) {
      termLog(`Snapshot hatası: ${err.message}`, 'error');
    } finally {
      setLoading(el.btnThinSnapshots, false);
    }
  }

  /* ──────────────────────────────────────────────────────────
     Bindings
     ────────────────────────────────────────────────────────── */
  el.btnScan.addEventListener('click', handleScan);
  el.btnClean.addEventListener('click', handleClean);
  if (el.btnSpotlight) el.btnSpotlight.addEventListener('click', handleSpotlight);
  if (el.btnFlushDns) el.btnFlushDns.addEventListener('click', handleFlushDns);
  if (el.btnPurgeRam) el.btnPurgeRam.addEventListener('click', handlePurgeRam);
  if (el.btnLaunchAgents) el.btnLaunchAgents.addEventListener('click', handleLaunchAgents);
  if (el.btnThinSnapshots) el.btnThinSnapshots.addEventListener('click', handleThinSnapshots);

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
        const willOpen = card.getAttribute('data-open') !== 'true';
        // GSAP accordion when available; falls back to a plain toggle.
        if (!window.AppAnim?.expand?.(card, willOpen)) {
          card.setAttribute('data-open', String(willOpen));
        }
      } else {
        cb.checked = !cb.checked;
        cb.dispatchEvent(new Event('change'));
      }
    });
  });

  // GSAP entrance + scroll reveals + draggable panels (no-ops without GSAP).
  window.AppAnim?.intro?.();
  window.AppAnim?.revealCards?.();
  window.AppAnim?.setupDraggable?.();

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

  /* ──────────────────────────────────────────────────────────
     App Uninstaller Tab Navigation & Handlers
     ────────────────────────────────────────────────────────── */
  const tabCleanup = $('#tab-cleanup');
  const tabUninstaller = $('#tab-uninstaller');
  const tabFiles = $('#tab-files');
  const cleanupTabContent = $('#cleanupTabContent');
  const uninstallerTabContent = $('#uninstallerTabContent');
  const filesTabContent = $('#filesTabContent');
  const appsSearch = $('#appsSearch');

  let allApplications = [];

  function showTab(tabId) {
    const map = {
      cleanup:     [tabCleanup, cleanupTabContent],
      uninstaller: [tabUninstaller, uninstallerTabContent],
      files:       [tabFiles, filesTabContent],
    };
    Object.entries(map).forEach(([id, [btn, content]]) => {
      const active = id === tabId;
      btn.classList.toggle('active', active);
      btn.setAttribute('aria-selected', active ? 'true' : 'false');
      content.hidden = !active;
    });
    if (tabId === 'uninstaller') loadApplications();
    if (tabId === 'files') renderFileList();
  }

  tabCleanup.addEventListener('click', () => showTab('cleanup'));
  tabUninstaller.addEventListener('click', () => showTab('uninstaller'));
  tabFiles.addEventListener('click', () => showTab('files'));

  /* ──────────────────────────────────────────────────────────
     Dosyalar (cleanable files) tab
     ────────────────────────────────────────────────────────── */
  const filesSearch = $('#filesSearch');
  const filesSort = $('#filesSort');
  const filesList = $('#filesList');
  const filesEmpty = $('#filesEmpty');
  const filesCountEl = $('#filesCount');
  const filesSelectedTotalEl = $('#filesSelectedTotal');
  const btnCleanSelected = $('#btnCleanSelected');

  function currentFileRows() {
    const all = window.ScanUtil.flattenScan(scanData || {});
    all.forEach((r) => { r.catName = CAT_BY_KEY[r.catKey]?.name || r.catKey; });
    const [key, dir] = (filesSort?.value || 'size:desc').split(':');
    return window.ScanUtil.sortRows(
      window.ScanUtil.filterRows(all, filesQuery), key, dir);
  }

  function updateFilesTotal() {
    const allRows = window.ScanUtil.flattenScan(scanData || {});
    const total = window.ScanUtil.selectedTotalBytes(allRows, filesSelected);
    filesSelectedTotalEl.textContent = formatBytes(total);
    btnCleanSelected.disabled = filesSelected.size === 0;
  }

  function renderFileList() {
    if (!scanData || !scanData.scan) {
      filesList.innerHTML = '';
      filesEmpty.hidden = false;
      filesCountEl.textContent = 'Önce tarama yapın';
      updateFilesTotal();
      return;
    }
    const rows = currentFileRows();
    filesEmpty.hidden = rows.length > 0;
    filesCountEl.textContent = `${rows.length} dosya`;
    filesList.innerHTML = '';
    const badgeLabel = { danger: 'riskli', caution: 'dikkat', safe: 'güvenli' };
    rows.forEach((r) => {
      const li = document.createElement('li');
      li.className = 'file-row';
      const checked = filesSelected.has(r.rowId) ? 'checked' : '';
      const ageStr = r.ageDays != null ? ` · ${r.ageDays}g` : '';
      const pathStr = r.path ? ' · ' + escapeHtml(r.path) : '';
      li.innerHTML = `
        <input type="checkbox" data-row-id="${escapeAttr(r.rowId)}" ${checked}>
        <span class="file-main">
          <span class="file-name" title="${escapeAttr(r.name)}">${escapeHtml(r.name)}</span>
          <span class="file-path">${escapeHtml(r.catName)}${ageStr}${pathStr}</span>
        </span>
        <span class="file-badge safety-${r.safety}">${badgeLabel[r.safety] || ''}</span>
        <span class="file-size">${escapeHtml(r.sizeHuman || formatBytes(r.sizeBytes || 0))}</span>
      `;
      filesList.appendChild(li);
    });
    filesList.querySelectorAll('input[type="checkbox"]').forEach((cb) => {
      cb.addEventListener('change', () => {
        const id = cb.dataset.rowId;
        if (cb.checked) filesSelected.add(id); else filesSelected.delete(id);
        updateFilesTotal();
      });
    });
    updateFilesTotal();
  }

  if (filesSearch) filesSearch.addEventListener('input', () => {
    filesQuery = filesSearch.value; renderFileList();
  });
  if (filesSort) filesSort.addEventListener('change', renderFileList);
  if ($('#filesSelectAll')) $('#filesSelectAll').addEventListener('click', () => {
    currentFileRows().forEach((r) => filesSelected.add(r.rowId));
    renderFileList();
  });
  if ($('#filesSelectNone')) $('#filesSelectNone').addEventListener('click', () => {
    filesSelected.clear(); renderFileList();
  });

  const INDEX_BY_KEY = Object.fromEntries(CATEGORIES.map((c) => [c.key, c.index]));

  async function handleCleanSelectedFiles() {
    if (isLoading || filesSelected.size === 0) return;
    const rows = window.ScanUtil.flattenScan(scanData || {})
      .filter((r) => filesSelected.has(r.rowId));
    if (rows.length === 0) return;

    const dangerRows = rows.filter((r) => r.safety === 'danger');
    const confirmed = confirm(
      `${rows.length} öğe temizlenecek (${filesSelectedTotalEl.textContent}). Devam edilsin mi?`);
    if (!confirmed) { termLog('Temizlik iptal edildi.', 'info'); return; }
    if (dangerRows.length > 0) {
      const ok = confirm(
        `RİSKLİ öğeler seçildi (${dangerRows.length}). Bu veriler kalıcı olarak silinir ve geri alınamaz. Devam edilsin mi?`);
      if (!ok) { termLog('Riskli öğeler onaylanmadı, temizlik iptal edildi.', 'info'); return; }
    }

    isLoading = true;
    setLoading(btnCleanSelected, true);
    termLog(`Seçilen dosyalar temizleniyor (${rows.length})…`, 'info');
    try {
      const dryRun = !!(el.dryRunToggle && el.dryRunToggle.checked);
      const payload = window.ScanUtil.buildCleanPayload(rows, INDEX_BY_KEY);
      payload.dry_run = dryRun;
      const data = await apiFetch('/api/clean', {
        method: 'POST', body: JSON.stringify(payload),
      });
      el.resultsPanel.hidden = false;
      el.resultsPanel.classList.remove('error');
      el.resultsTitle.textContent = data.dry_run
        ? 'Önizleme (hiçbir şey silinmedi)' : 'Temizlik tamamlandı';
      el.resultsFreed.textContent = data.dry_run
        ? (data.estimated_human || formatBytes(data.estimated_bytes || 0))
        : (data.freed_human || formatBytes(data.freed_bytes || 0));
      if (data.disk_free) el.sysDiskFree.textContent = data.disk_free;
      termLog(`Temizlik tamamlandı — ${el.resultsFreed.textContent}`, 'success');
      if (!data.dry_run) filesSelected.clear();
      renderFileList();
    } catch (err) {
      termLog(`Temizlik hatası: ${err.message}`, 'error');
    } finally {
      setLoading(btnCleanSelected, false);
      isLoading = false;
    }
  }

  if (btnCleanSelected) btnCleanSelected.addEventListener('click', handleCleanSelectedFiles);

  if (appsSearch) {
    appsSearch.addEventListener('input', () => {
      filterApplications(appsSearch.value);
    });
  }

  async function loadApplications() {
    const appsCount = $('#appsCount');
    const appsList = $('#appsList');
    if (appsCount) appsCount.textContent = 'Taranıyor...';
    if (appsList) appsList.innerHTML = '<li class="apps-loading"><span class="spinner"></span>Uygulamalar listeleniyor...</li>';

    termLog('Yüklü uygulamalar taranıyor…', 'info');

    try {
      const data = await apiFetch('/api/apps');
      if (data && data.success) {
        allApplications = data.apps || [];
        renderApplications(allApplications);
        termLog(`Uygulama taraması tamamlandı. ${allApplications.length} uygulama bulundu.`, 'success');
      } else {
        throw new Error(data?.error || 'Uygulamalar alınamadı.');
      }
    } catch (err) {
      termLog(`Uygulama tarama hatası: ${err.message}`, 'error');
      if (appsList) appsList.innerHTML = `<li class="apps-error">Hata: ${err.message}</li>`;
      if (appsCount) appsCount.textContent = 'Hata';
    }
  }

  function renderApplications(apps, skipReveal) {
    const appsCount = $('#appsCount');
    const appsList = $('#appsList');
    if (appsCount) appsCount.textContent = `${apps.length} uygulama`;
    if (!appsList) return;

    if (apps.length === 0) {
      appsList.innerHTML = '<li class="apps-empty">Uygulama bulunamadı.</li>';
      return;
    }

    appsList.innerHTML = '';
    apps.forEach((app) => {
      const li = document.createElement('li');
      li.className = 'app-item';
      li.dataset.appId = app.id;
      li.dataset.flipId = app.id;   // lets Flip match items across filtering

      // Source badges
      let sourceBadge = '';
      if (app.source === 'brew') {
        sourceBadge = '<span class="app-src src-brew">brew</span>';
      } else if (app.source === 'brew_cask') {
        sourceBadge = '<span class="app-src src-cask">cask</span>';
      } else if (app.source === 'both') {
        sourceBadge = '<span class="app-src src-both">both</span>';
      } else {
        sourceBadge = '<span class="app-src src-dir">app</span>';
      }

      // App icon placeholder or letter icon
      const initial = app.name ? app.name.charAt(0).toUpperCase() : '?';

      li.innerHTML = `
        <div class="app-info-col">
          <div class="app-icon" style="background-color: ${getColorForString(app.name)}">${initial}</div>
          <div class="app-meta">
            <span class="app-name">${escapeHtml(app.name)}</span>
            <span class="app-details-row">
              ${app.version ? `<span class="app-version">v${escapeHtml(app.version)}</span>` : ''}
              ${app.bundle_id ? `<span class="app-bundle">${escapeHtml(app.bundle_id)}</span>` : ''}
            </span>
          </div>
        </div>
        <div class="app-action-col">
          ${sourceBadge}
          <span class="app-size-val">${escapeHtml(app.size_human)}</span>
          <button class="btn btn-danger btn-sm btn-uninstall" type="button" data-id="${escapeAttr(app.id)}" data-source="${escapeAttr(app.source)}" data-name="${escapeAttr(app.name)}" data-folder-name="${escapeAttr(app.folder_name)}">
            <span class="spinner" aria-hidden="true"></span>
            <span class="btn-text">Kaldır</span>
          </button>
        </div>
      `;
      appsList.appendChild(li);
    });

    // Wire up uninstall buttons
    $$('.btn-uninstall', appsList).forEach((btn) => {
      btn.addEventListener('click', (e) => {
        const id = btn.dataset.id;
        const source = btn.dataset.source;
        const name = btn.dataset.name;
        const folderName = btn.dataset.folderName;
        handleAppUninstall(btn, id, source, name, folderName);
      });
    });

    if (!skipReveal) {
      window.AppAnim?.revealList?.(appsList);
    }
  }

  function getColorForString(str) {
    let hash = 0;
    for (let i = 0; i < str.length; i++) {
      hash = str.charCodeAt(i) + ((hash << 5) - hash);
    }
    const colors = [
      '#4d8eff', '#6f6ff7', '#a26bf7', '#0bb8c9', '#16a34a',
      '#d97706', '#f59e0b', '#dc2626', '#ef4444', '#c2410c'
    ];
    return colors[Math.abs(hash) % colors.length];
  }

  function filterApplications(query) {
    const q = query.toLowerCase().trim();
    const next = !q ? allApplications : allApplications.filter((app) =>
      (app.name && app.name.toLowerCase().includes(q)) ||
      (app.bundle_id && app.bundle_id.toLowerCase().includes(q)) ||
      (app.id && app.id.toLowerCase().includes(q))
    );
    // Flip: matched items glide to new positions, removed/added fade out/in.
    const render = () => renderApplications(next, true);
    if (window.AppAnim && window.AppAnim.flipApps) window.AppAnim.flipApps(render);
    else renderApplications(next);
  }

  async function handleAppUninstall(btn, id, source, name, folderName) {
    const confirmed = confirm(`"${name}" uygulamasını ve ilişkili tüm dosyalarını kaldırmak istediğinize emin misiniz?`);
    if (!confirmed) return;

    setLoading(btn, true);
    termLog(`"${name}" kaldırılıyor…`, 'info');

    try {
      const data = await apiFetch('/api/uninstall', {
        method: 'POST',
        body: JSON.stringify({ id, source, folder_name: folderName }),
      });

      if (data && data.success) {
        termLog(`✓ "${name}" başarıyla kaldırıldı.`, 'success');
        if (data.details) {
          termLog(`  Detaylar: ${data.details}`, 'success');
        }
        const li = btn.closest('.app-item');
        if (li) {
          li.style.opacity = '0';
          li.style.transform = 'translateX(20px)';
          li.style.transition = 'all 0.35s ease';
          setTimeout(() => {
            li.remove();
            allApplications = allApplications.filter((a) => a.id !== id);
            const appsCount = $('#appsCount');
            if (appsCount) appsCount.textContent = `${allApplications.length} uygulama`;
          }, 350);
        }
      } else {
        throw new Error(data?.error || 'Kaldırma başarısız oldu.');
      }
    } catch (err) {
      termLog(`✗ "${name}" kaldırılırken hata oluştu: ${err.message}`, 'error');
      alert(`Hata: ${err.message}`);
    } finally {
      setLoading(btn, false);
    }
  }

  termLog('Apple Cleanup başlatıldı.', 'success');
  fetchStatus();
})();
