/* ============================================================================
   anim.js — GSAP animation layer for the Apple Cleanup dashboard.

   Loads AFTER the vendored GSAP core + plugins and BEFORE script.js, exposing
   a small `window.AppAnim` API that script.js calls at lifecycle points
   (intro, card reveal, category expand, post-scan, list filtering, draggable).

   Design goals:
   - Fail safe: if GSAP didn't load, every method becomes a no-op and the
     dashboard works exactly as before (CSS handles the static states).
   - Respect prefers-reduced-motion: animations collapse to final state.
   - Stay decoupled: no knowledge of API/business logic, only the DOM.
   ============================================================================ */
(function () {
  'use strict';

  const g = window.gsap;

  // ── Graceful degradation ──────────────────────────────────────────────────
  // If GSAP is unavailable, hand script.js a stub API so nothing breaks. Any
  // method that takes a callback (e.g. flipApps) still runs it, so DOM updates
  // happen even without animation.
  if (!g) {
    window.AppAnim = new Proxy({}, {
      get: () => (maybeFn) => { if (typeof maybeFn === 'function') maybeFn(); },
    });
    return;
  }

  // Register every plugin we use, once.
  const plugins = ['ScrollTrigger', 'Flip', 'Draggable', 'InertiaPlugin', 'SplitText'];
  plugins.forEach((name) => { if (window[name]) g.registerPlugin(window[name]); });
  const { ScrollTrigger, Flip, Draggable, SplitText } = window;

  const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  document.documentElement.classList.add('gsap-on');

  g.defaults({ ease: 'power3.out', duration: 0.6 });

  const $  = (s, p = document) => p.querySelector(s);
  const $$ = (s, p = document) => Array.from(p.querySelectorAll(s));

  // Keep SplitText instances so we can revert before re-splitting.
  const splits = new WeakMap();

  function splitReveal(elTarget, opts = {}) {
    if (!elTarget || !SplitText) return;
    if (reduce) return;
    const prev = splits.get(elTarget);
    if (prev) prev.revert();
    const split = SplitText.create(elTarget, { type: 'chars, words', aria: 'auto' });
    splits.set(elTarget, split);
    g.from(split.chars, {
      yPercent: 110, opacity: 0, ease: 'back.out(1.7)',
      duration: 0.5, stagger: 0.018, delay: opts.delay || 0,
      onComplete: () => { /* leave split in place; revert on next call */ },
    });
  }

  const AppAnim = {
    /* One-time entrance choreography for the whole shell. */
    intro() {
      if (reduce) return;
      const tl = g.timeline();
      tl.from('.topbar', { y: -24, opacity: 0, duration: 0.5 })
        .from('.nav-tabs', { y: 12, opacity: 0, duration: 0.45 }, '-=0.25')
        .from('.hero-eyebrow', { y: 14, opacity: 0, duration: 0.4 }, '-=0.15')
        .add(() => splitReveal($('#heroTitle')), '<')
        .from('.hero-lead', { y: 14, opacity: 0, duration: 0.4 }, '-=0.1')
        .from('.hero-actions > *', { y: 16, opacity: 0, stagger: 0.08, duration: 0.4 }, '-=0.15')
        .from('.hero-right', { scale: 0.85, opacity: 0, duration: 0.6, ease: 'back.out(1.4)' }, '-=0.5');
    },

    /* Reveal category cards + maintenance/section blocks as they scroll in. */
    revealCards() {
      if (reduce || !ScrollTrigger) return;
      // Hide first, then reveal on enter — avoids a flash for in-view cards.
      g.set('.cat-list .cat', { opacity: 0, y: 18 });
      ScrollTrigger.batch('.cat-list .cat', {
        start: 'top 96%',
        onEnter: (batch) => g.to(batch, {
          opacity: 1, y: 0, duration: 0.5, stagger: 0.05, overwrite: true,
        }),
      });
      $$('.section').forEach((sec) => {
        g.from(sec.querySelector('.section-head'), {
          scrollTrigger: { trigger: sec, start: 'top 90%' },
          y: 16, opacity: 0, duration: 0.5,
        });
      });
      ScrollTrigger.refresh();
    },

    /* Smooth accordion expand/collapse for a category card's sub-items. */
    expand(card, willOpen) {
      const subs = card && card.querySelector('.subitems');
      if (!subs) { return false; }      // caller falls back to plain toggle
      if (reduce) { card.setAttribute('data-open', String(willOpen)); return true; }

      g.killTweensOf(subs);
      if (willOpen) {
        card.setAttribute('data-open', 'true');       // CSS sets display:block
        g.set(subs, { height: 'auto', opacity: 1 });
        g.from(subs, {
          height: 0, opacity: 0, duration: 0.4, ease: 'power2.out',
          onComplete: () => g.set(subs, { height: 'auto' }),
        });
        const rows = subs.querySelectorAll('.subitem-row');
        if (rows.length) g.from(rows, { y: -6, opacity: 0, duration: 0.3, stagger: 0.025, delay: 0.05 });
      } else {
        g.to(subs, {
          height: 0, opacity: 0, duration: 0.32, ease: 'power2.in',
          onComplete: () => { card.setAttribute('data-open', 'false'); g.set(subs, { clearProps: 'height,opacity' }); },
        });
      }
      return true;
    },

    /* Post-scan flourish: re-reveal the (now changed) hero title, stagger the
       distribution legend, and count category sizes up to their real values. */
    afterScan() {
      if (reduce) return;
      splitReveal($('#heroTitle'));
      g.from('.hero-bar-legend .lg', { opacity: 0, y: 8, stagger: 0.06, duration: 0.4, delay: 0.2 });
      $$('.cat-size[data-bytes]').forEach((elx) => {
        const to = parseFloat(elx.dataset.bytes) || 0;
        if (to <= 0 || !window.formatBytesShared) return;
        const o = { v: 0 };
        g.to(o, {
          v: to, duration: 0.9, ease: 'power1.out',
          onUpdate: () => { elx.textContent = window.formatBytesShared(o.v); },
        });
      });
      if (ScrollTrigger) ScrollTrigger.refresh();
    },

    /* Animate the app list re-layout when filtering (Flip). `render` rebuilds
       the list; surviving items (matched by data-flip-id) glide to their new
       positions while removed/added ones fade out/in. */
    flipApps(render) {
      if (!Flip || reduce) { render(); return; }
      const state = Flip.getState('.app-item', { props: 'opacity' });
      render();
      Flip.from(state, {
        duration: 0.4, ease: 'power2.out', absolute: true,
        onEnter: (els) => g.fromTo(els, { opacity: 0, scale: 0.92 }, { opacity: 1, scale: 1, duration: 0.3 }),
        onLeave: (els) => g.to(els, { opacity: 0, scale: 0.92, duration: 0.2 }),
      });
    },

    /* Animate a freshly inserted list (apps list) in with a stagger. */
    revealList(container) {
      if (reduce || !container) return;
      g.from(container.children, { y: 14, duration: 0.4, stagger: 0.03, overwrite: true });
    },

    /* Make the terminal drawer and results panel draggable (throw with inertia),
       grabbed by their header. Real clicks still toggle (Draggable passes them). */
    setupDraggable() {
      if (!Draggable) return;
      const make = (el, handle) => {
        if (!el || !handle) return;
        handle.style.cursor = 'grab';
        Draggable.create(el, {
          type: 'x,y', trigger: handle, bounds: 'body',
          inertia: true, edgeResistance: 0.65, dragClickables: false,
          onPress() { handle.style.cursor = 'grabbing'; },
          onRelease() { handle.style.cursor = 'grab'; },
        });
      };
      make($('#term'), $('#termHead'));
      // Results panel can be repositioned once it appears; (re)bind on demand.
      this._bindResultsDrag = () => make($('#resultsPanel'), $('.results-head'));
    },

    bindResultsDrag() { if (this._bindResultsDrag) this._bindResultsDrag(); },

    /* Small attention pulse for a freshly shown panel. */
    pop(el) {
      if (reduce || !el) return;
      g.from(el, { y: 18, opacity: 0, scale: 0.98, duration: 0.45, ease: 'back.out(1.3)' });
    },

    /* Organic infinite drift for the background glass blobs (transforms only). */
    blobs() {
      if (reduce) return;
      const defs = [
        ['.blob-a', 60, 40, 20],
        ['.blob-b', -50, 30, 24],
        ['.blob-c', 30, -50, 22],
      ];
      defs.forEach(([sel, x, y, dur]) => {
        if (!$(sel)) return;
        g.to(sel, { x, y, duration: dur, ease: 'sine.inOut', repeat: -1, yoyo: true });
      });
    },

    /* Sweep the disk donut to `pct` (0-100) and count the % label up.
       Returns true when it handled the update, false to let the caller fall back. */
    donut(pct) {
      const fill = $('#donutFill'), num = $('#donutNum');
      const p = Math.max(0, Math.min(100, pct || 0));
      if (reduce) {
        if (fill) fill.setAttribute('stroke-dasharray', p + ' ' + (100 - p));
        if (num) num.textContent = Math.round(p) + '%';
        return true;
      }
      if (fill) {
        g.fromTo(fill, { attr: { 'stroke-dasharray': '0 100' } },
          { attr: { 'stroke-dasharray': p + ' ' + (100 - p) }, duration: 1, ease: 'power2.out' });
      }
      if (num) {
        const o = { v: 0 };
        g.to(o, { v: p, duration: 1, ease: 'power1.out',
          onUpdate: () => { num.textContent = Math.round(o.v) + '%'; } });
      }
      return true;
    },

    /* Brief cross-fade pulse on the shell when the theme flips. */
    themeSwitch() {
      if (reduce) return;
      g.fromTo('.app', { opacity: 0.6 }, { opacity: 1, duration: 0.35, ease: 'power2.out' });
    },
  };

  window.AppAnim = AppAnim;
})();
