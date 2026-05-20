/**
 * Apple Cleanup Dashboard — Frontend Logic
 * ─────────────────────────────────────────
 */

(() => {
  'use strict';

  /* ── Constants ──────────────────────────────────────────── */
  const API_BASE = '';
  const CATEGORY_MAP = {
    user_cache:    { index: 1, name: 'Kullanıcı Cache' },
    system_cache:  { index: 2, name: 'Sistem Cache' },
    app_leftovers: { index: 3, name: 'Uygulama Kalıntıları' },
    logs:          { index: 4, name: 'Loglar' },
    temp_files:    { index: 5, name: 'Geçici Dosyalar' },
    developer:     { index: 6, name: 'Geliştirici' },
    trash:         { index: 7, name: 'Çöp Kutusu' },
  };

  /* ── DOM References ─────────────────────────────────────── */
  const $ = (sel) => document.querySelector(sel);
  const $$ = (sel) => document.querySelectorAll(sel);

  const themeToggle = $('#themeToggle');
  const sysVersion  = $('#sysVersion');
  const sysUser     = $('#sysUser');
  const sysDiskFree = $('#sysDiskFree');
  const diskBarFill = $('#diskBarFill');
  const totalSizeEl = $('#totalSize');
  const btnScan     = $('#btnScan');
  const btnClean    = $('#btnClean');
  const btnSelectAll  = $('#btnSelectAll');
  const btnSelectNone = $('#btnSelectNone');
  const resultsPanel  = $('#resultsPanel');
  const resultsTitle  = $('#resultsTitle');
  const resultsSubtitle = $('#resultsSubtitle');
  const resultsFreed    = $('#resultsFreed');
  const resultsDetails  = $('#resultsDetails');
  const terminalBody    = $('#terminalBody');
  const cards = $$('.category-card');

  /* ── State ──────────────────────────────────────────────── */
  let scanData  = null;
  let isLoading = false;

  /* ── Theme ──────────────────────────────────────────────── */
  function initTheme() {
    const saved = localStorage.getItem('apple-cleanup-theme');
    const theme = saved || 'dark';
    document.documentElement.setAttribute('data-theme', theme);
  }

  function toggleTheme() {
    const current = document.documentElement.getAttribute('data-theme');
    const next = current === 'dark' ? 'light' : 'dark';
    document.documentElement.setAttribute('data-theme', next);
    localStorage.setItem('apple-cleanup-theme', next);
  }

  initTheme();
  themeToggle.addEventListener('click', toggleTheme);

  /* ── Terminal Log ───────────────────────────────────────── */
  function termLog(message, type = '') {
    const now = new Date();
    const time = now.toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit', second: '2-digit' });

    const line = document.createElement('div');
    line.className = 'terminal-line';
    line.innerHTML = `
      <span class="terminal-time">${time}</span>
      <span class="terminal-msg ${type}">${escapeHtml(message)}</span>
    `;
    terminalBody.appendChild(line);
    terminalBody.scrollTop = terminalBody.scrollHeight;
  }

  function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  /* ── Utilities ──────────────────────────────────────────── */
  function formatBytes(bytes) {
    if (bytes === 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(1024));
    return (bytes / Math.pow(1024, i)).toFixed(1) + ' ' + units[i];
  }

  function setLoadingState(button, loading) {
    if (loading) {
      button.classList.add('loading');
      button.disabled = true;
    } else {
      button.classList.remove('loading');
      button.disabled = false;
    }
  }

  function getSelectedCategories() {
    const selected = [];
    cards.forEach((card) => {
      const checkbox = card.querySelector('input[type="checkbox"]');
      if (checkbox.checked) {
        selected.push(parseInt(card.dataset.index, 10));
      }
    });
    return selected;
  }

  /* ── API Calls ──────────────────────────────────────────── */
  async function apiFetch(url, options = {}) {
    try {
      const res = await fetch(`${API_BASE}${url}`, {
        headers: { 'Content-Type': 'application/json' },
        ...options,
      });
      const data = await res.json();
      if (!data.success && data.error) {
        throw new Error(data.error);
      }
      return data;
    } catch (err) {
      throw err;
    }
  }

  /* ── System Status ──────────────────────────────────────── */
  async function fetchStatus() {
    termLog('Sistem bilgileri alınıyor…', 'info');
    try {
      const data = await apiFetch('/api/status');
      sysVersion.textContent = data.macos_version || '—';
      sysVersion.classList.remove('loading');
      sysUser.textContent = data.user || '—';
      sysUser.classList.remove('loading');
      sysDiskFree.textContent = data.disk_free || '—';
      sysDiskFree.classList.remove('loading');

      // Animate disk bar (estimate ~30% used as placeholder)
      diskBarFill.style.width = '30%';

      termLog(`macOS ${data.macos_version} • ${data.user} • ${data.disk_free} boş alan`, 'success');
    } catch (err) {
      termLog(`Sistem bilgisi alınamadı: ${err.message}`, 'error');
      sysVersion.textContent = '—';
      sysUser.textContent = '—';
      sysDiskFree.textContent = '—';
      [sysVersion, sysUser, sysDiskFree].forEach(el => el.classList.remove('loading'));
    }
  }

  /* ── Scan ────────────────────────────────────────────────── */
  async function handleScan() {
    if (isLoading) return;
    isLoading = true;

    setLoadingState(btnScan, true);
    btnClean.disabled = true;
    resultsPanel.classList.remove('visible');
    termLog('Tarama başlatılıyor…', 'info');

    try {
      const data = await apiFetch('/api/scan');
      scanData = data;

      // Update system info
      if (data.disk_free) {
        sysDiskFree.textContent = data.disk_free;
        sysDiskFree.classList.remove('loading');
      }
      if (data.macos_version) {
        sysVersion.textContent = data.macos_version;
        sysVersion.classList.remove('loading');
      }
      if (data.user) {
        sysUser.textContent = data.user;
        sysUser.classList.remove('loading');
      }

      // Update category sizes with animation
      const scan = data.scan || {};
      Object.entries(scan).forEach(([key, info]) => {
        const badge = document.querySelector(`.size-badge[data-size="${key}"]`);
        if (!badge) return;

        const sizeText = info.size_human || formatBytes(info.size_bytes || 0);
        badge.textContent = sizeText;
        badge.classList.add('has-size', 'size-animate');

        // Color coding based on size
        badge.classList.remove('large', 'xlarge');
        if (info.size_bytes > 500 * 1024 * 1024) {
          badge.classList.add('xlarge');
        } else if (info.size_bytes > 50 * 1024 * 1024) {
          badge.classList.add('large');
        }

        // Remove animation class after it plays
        setTimeout(() => badge.classList.remove('size-animate'), 500);

        termLog(`  ${CATEGORY_MAP[key]?.name || key}: ${sizeText}`, '');
      });

      // Total size
      const totalText = data.total_human || formatBytes(data.total_bytes || 0);
      totalSizeEl.innerHTML = `Toplam: <span>${totalText}</span>`;

      termLog(`Tarama tamamlandı — toplam ${totalText} temizlenebilir`, 'success');

      // Enable clean button
      btnClean.disabled = false;
    } catch (err) {
      termLog(`Tarama hatası: ${err.message}`, 'error');
    } finally {
      setLoadingState(btnScan, false);
      isLoading = false;
    }
  }

  /* ── Clean ───────────────────────────────────────────────── */
  async function handleClean() {
    if (isLoading) return;

    const selected = getSelectedCategories();
    if (selected.length === 0) {
      termLog('Lütfen en az bir kategori seçin.', 'error');
      return;
    }

    // Build category names for confirmation
    const names = selected.map((idx) => {
      const entry = Object.entries(CATEGORY_MAP).find(([, v]) => v.index === idx);
      return entry ? entry[1].name : `#${idx}`;
    });

    const confirmed = confirm(
      `Şu kategoriler temizlenecek:\n\n${names.map(n => `• ${n}`).join('\n')}\n\nDevam etmek istiyor musunuz?`
    );
    if (!confirmed) {
      termLog('Temizlik iptal edildi.', 'info');
      return;
    }

    isLoading = true;
    setLoadingState(btnClean, true);
    setLoadingState(btnScan, true);
    resultsPanel.classList.remove('visible');

    termLog(`Temizlik başlatılıyor (${selected.length} kategori)…`, 'info');

    try {
      const data = await apiFetch('/api/clean', {
        method: 'POST',
        body: JSON.stringify({ categories: selected }),
      });

      // Show results panel
      resultsPanel.classList.remove('error');
      resultsPanel.classList.add('visible');

      const freedText = data.freed_human || formatBytes(data.freed_bytes || 0);
      resultsFreed.textContent = freedText + ' temizlendi';
      resultsTitle.textContent = 'Temizlik Tamamlandı!';
      resultsSubtitle.textContent = `${data.items_cleaned || 0} öğe temizlendi • Boş alan: ${data.disk_free || '—'}`;

      // Update disk free
      if (data.disk_free) {
        sysDiskFree.textContent = data.disk_free;
      }

      // Detail chips
      resultsDetails.innerHTML = '';
      if (data.details && data.details.length > 0) {
        data.details.forEach((d) => {
          const name = CATEGORY_MAP[d.category]?.name || d.category;
          const chip = document.createElement('div');
          chip.className = 'result-chip';
          chip.innerHTML = `${escapeHtml(name)} <span class="chip-freed">${escapeHtml(d.freed)}</span>`;
          resultsDetails.appendChild(chip);

          termLog(`  ✓ ${name}: ${d.freed}`, 'success');
        });
      }

      // Handle errors
      if (data.errors && data.errors.length > 0) {
        data.errors.forEach((e) => {
          termLog(`  ✗ Hata: ${e}`, 'error');
        });
      }

      termLog(`Toplam ${freedText} alan kazanıldı!`, 'success');

      // Smooth scroll to results
      resultsPanel.scrollIntoView({ behavior: 'smooth', block: 'center' });

      // Reset scan data so user can re-scan
      scanData = null;

      // Reset size badges
      $$('.size-badge').forEach((badge) => {
        badge.textContent = '— Taranmadı';
        badge.classList.remove('has-size', 'large', 'xlarge');
      });
      totalSizeEl.innerHTML = '';
    } catch (err) {
      termLog(`Temizlik hatası: ${err.message}`, 'error');

      // Show error in results panel
      resultsPanel.classList.add('visible', 'error');
      resultsTitle.textContent = 'Hata Oluştu';
      resultsFreed.textContent = '';
      resultsSubtitle.textContent = err.message;
      resultsDetails.innerHTML = '';
    } finally {
      setLoadingState(btnClean, false);
      setLoadingState(btnScan, false);
      btnClean.disabled = true;
      isLoading = false;
    }
  }

  /* ── Card Toggle ────────────────────────────────────────── */
  cards.forEach((card) => {
    const checkbox = card.querySelector('input[type="checkbox"]');

    // Toggle card selection via checkbox
    checkbox.addEventListener('change', () => {
      card.classList.toggle('selected', checkbox.checked);
    });

    // Click on card (not on toggle) toggles it
    card.addEventListener('click', (e) => {
      if (e.target.closest('.toggle-switch')) return;
      checkbox.checked = !checkbox.checked;
      checkbox.dispatchEvent(new Event('change'));
    });
  });

  /* ── Select All / None ──────────────────────────────────── */
  btnSelectAll.addEventListener('click', () => {
    cards.forEach((card) => {
      const cb = card.querySelector('input[type="checkbox"]');
      cb.checked = true;
      card.classList.add('selected');
    });
    termLog('Tüm kategoriler seçildi.', 'info');
  });

  btnSelectNone.addEventListener('click', () => {
    cards.forEach((card) => {
      const cb = card.querySelector('input[type="checkbox"]');
      cb.checked = false;
      card.classList.remove('selected');
    });
    termLog('Tüm seçimler kaldırıldı.', 'info');
  });

  /* ── Button Handlers ────────────────────────────────────── */
  btnScan.addEventListener('click', handleScan);
  btnClean.addEventListener('click', handleClean);

  /* ── Init ────────────────────────────────────────────────── */
  termLog('Apple Cleanup Dashboard başlatıldı.', 'success');
  termLog('Sistem bilgileri yükleniyor…', 'info');

  fetchStatus();
})();
