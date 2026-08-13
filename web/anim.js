/* ==========================================================================
   Apple Cleanup motion system
   Motion explains hierarchy and state. It stays short, interruptible, and
   collapses cleanly when the user prefers reduced motion.
   ========================================================================== */
(function () {
  'use strict';

  const gsap = window.gsap;
  if (!gsap) {
    window.AppAnim = new Proxy({}, {
      get: () => (maybeRender) => {
        if (typeof maybeRender === 'function') maybeRender();
        return false;
      },
    });
    return;
  }

  const ScrollTrigger = window.ScrollTrigger;
  const Flip = window.Flip;
  if (ScrollTrigger) gsap.registerPlugin(ScrollTrigger);
  if (Flip) gsap.registerPlugin(Flip);

  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const context = gsap.context(() => {});
  const $ = (selector, parent = document) => parent.querySelector(selector);
  const $$ = (selector, parent = document) => Array.from(parent.querySelectorAll(selector));

  document.documentElement.classList.add('gsap-on');
  gsap.defaults({ duration: .38, ease: 'power2.out' });

  function finishImmediately(callback) {
    if (typeof callback === 'function') callback();
  }

  const AppAnim = {
    intro() {
      if (reduceMotion) return;
      context.add(() => {
        const timeline = gsap.timeline({ defaults: { overwrite: 'auto' } });
        timeline
          .from('.brand, .sysbar, .theme-toggle', {
            y: -7,
            opacity: 0,
            duration: .34,
            stagger: .045,
          })
          .from('.nav-label, .tab-btn', {
            x: -8,
            opacity: 0,
            duration: .3,
            stagger: .035,
          }, '-=.18')
          .from('.hero', {
            y: 9,
            opacity: 0,
            duration: .46,
          }, '-=.16')
          .from('.hero-eyebrow, .hero-title, .hero-lead, .hero-assurance, .hero-actions', {
            y: 8,
            opacity: 0,
            duration: .34,
            stagger: .045,
          }, '-=.27')
          .from('.hero-right', {
            opacity: 0,
            duration: .4,
          }, '-=.28');
      });
    },

    revealCards() {
      if (reduceMotion || !ScrollTrigger) return;
      context.add(() => {
        const cards = $$('.cat-list .cat');
        gsap.set(cards, { opacity: 0, y: 8 });
        ScrollTrigger.batch(cards, {
          start: 'top 94%',
          once: true,
          onEnter: (batch) => gsap.to(batch, {
            y: 0,
            opacity: 1,
            duration: .34,
            stagger: .025,
            overwrite: true,
          }),
        });
        ScrollTrigger.refresh();
      });
    },

    expand(card, willOpen) {
      const content = card && card.querySelector('.subitems');
      if (!content) return false;
      if (reduceMotion) {
        card.setAttribute('data-open', String(willOpen));
        return true;
      }

      gsap.killTweensOf(content);
      if (willOpen) {
        card.setAttribute('data-open', 'true');
        gsap.set(content, { height: 'auto', opacity: 1 });
        gsap.from(content, {
          height: 0,
          opacity: 0,
          duration: .3,
          ease: 'power2.out',
          onComplete: () => gsap.set(content, { clearProps: 'height,opacity' }),
        });
      } else {
        gsap.to(content, {
          height: 0,
          opacity: 0,
          duration: .24,
          ease: 'power1.inOut',
          onComplete: () => {
            card.setAttribute('data-open', 'false');
            gsap.set(content, { clearProps: 'height,opacity' });
          },
        });
      }
      return true;
    },

    afterScan() {
      if (reduceMotion) return;
      const heroParts = ['#heroTitle', '#heroNumber', '#heroBar'].map((selector) => $(selector)).filter(Boolean);
      gsap.from(heroParts, {
        y: 7,
        opacity: 0,
        duration: .38,
        stagger: .045,
        overwrite: true,
      });
      gsap.from('.hero-bar-legend .lg', {
        opacity: 0,
        y: 4,
        duration: .28,
        stagger: .035,
        delay: .16,
      });
      $$('.cat-size[data-bytes]').forEach((element) => {
        const target = Number(element.dataset.bytes) || 0;
        if (target <= 0 || !window.formatBytesShared) return;
        const value = { current: 0 };
        gsap.to(value, {
          current: target,
          duration: .72,
          ease: 'power1.out',
          onUpdate: () => { element.textContent = window.formatBytesShared(value.current); },
        });
      });
      ScrollTrigger?.refresh();
    },

    flipApps(render) {
      if (!Flip || reduceMotion) {
        finishImmediately(render);
        return;
      }
      const state = Flip.getState('.app-item', { props: 'opacity' });
      render();
      Flip.from(state, {
        duration: .3,
        ease: 'power1.inOut',
        absolute: true,
        onEnter: (elements) => gsap.fromTo(elements, { opacity: 0, y: 4 }, { opacity: 1, y: 0, duration: .22 }),
        onLeave: (elements) => gsap.to(elements, { opacity: 0, duration: .16 }),
      });
    },

    revealList(container) {
      if (reduceMotion || !container) return;
      const visibleRows = Array.from(container.children).slice(0, 18);
      gsap.from(visibleRows, {
        y: 6,
        opacity: 0,
        duration: .28,
        stagger: .022,
        overwrite: true,
      });
    },

    revealTreemap(nodes) {
      if (reduceMotion || !nodes?.length) return;
      gsap.from(nodes, {
        opacity: 0,
        scale: .98,
        transformOrigin: '50% 50%',
        duration: .3,
        ease: 'power1.out',
        stagger: .018,
        overwrite: true,
      });
    },

    panel(panel) {
      if (reduceMotion || !panel) return;
      gsap.fromTo(panel, { opacity: 0, y: 5 }, {
        opacity: 1,
        y: 0,
        duration: .26,
        overwrite: true,
      });
    },

    pop(element) {
      if (reduceMotion || !element) return;
      gsap.from(element, { y: 7, opacity: 0, duration: .32, overwrite: true });
    },

    donut(percent) {
      const fill = $('#donutFill');
      const label = $('#donutNum');
      const target = Math.max(0, Math.min(100, Number(percent) || 0));
      if (reduceMotion) {
        fill?.setAttribute('stroke-dasharray', `${target} ${100 - target}`);
        if (label) label.textContent = `${Math.round(target)}%`;
        return true;
      }
      if (fill) {
        gsap.fromTo(fill,
          { attr: { 'stroke-dasharray': '0 100' } },
          { attr: { 'stroke-dasharray': `${target} ${100 - target}` }, duration: .8, ease: 'power2.out' });
      }
      if (label) {
        const value = { current: 0 };
        gsap.to(value, {
          current: target,
          duration: .8,
          ease: 'power1.out',
          onUpdate: () => { label.textContent = `${Math.round(value.current)}%`; },
        });
      }
      return true;
    },

    themeSwitch() {
      if (reduceMotion) return;
      gsap.fromTo('.app', { opacity: .82 }, { opacity: 1, duration: .22, overwrite: true });
    },

  };

  window.addEventListener('pagehide', () => context.revert(), { once: true });
  window.AppAnim = AppAnim;
})();
