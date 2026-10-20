// Phone marquee speed in CSS px per second (the old rAF loop moved 0.5px
// per frame, i.e. 30px/s at 60fps).
const MARQUEE_SPEED = 30;

export const LogoTransition = {
  mounted() {
    // A bfcache restore re-mounts hooks without ever calling destroyed() on
    // the previous instance; tear its timers down first so two loops don't
    // fight over the same logo groups (stuck, overlapping logos).
    if (this.el.logoTransitionTeardown) {
      this.el.logoTransitionTeardown();
    }
    this.teardownRef = () => this.teardown();
    this.el.logoTransitionTeardown = this.teardownRef;

    this.currentIndex = 0;
    this.isAnimating = false;
    this.intervalId = null;
    this.cleanupTimeout = null;
    this.originalHTML = this.el.innerHTML;
    this.currentMode = null;

    this.handleResize = this.handleResize.bind(this);
    window.addEventListener("resize", this.handleResize);
    // Hidden tabs throttle timers and don't paint transitions, which can
    // strand a crossfade halfway; stop the loop while hidden and restart
    // from a clean state on return.
    this.handleVisibility = this.handleVisibility.bind(this);
    document.addEventListener("visibilitychange", this.handleVisibility);
    // A bfcache restore does NOT fire visibilitychange — the page was frozen
    // in the "visible" state. pageshow with persisted=true is the only
    // signal, and the restored page resumes whatever half-finished crossfade
    // it was frozen with; reset it.
    this.handlePageshow = (event) => {
      if (event.persisted && this.currentMode === "desktop") {
        this.setupDesktopAnimation();
      }
    };
    this.handlePagehide = () => this.stopDesktopLoop();
    window.addEventListener("pageshow", this.handlePageshow);
    window.addEventListener("pagehide", this.handlePagehide);
    this.init();
  },

  handleVisibility() {
    if (document.hidden) {
      this.stopDesktopLoop();
    } else if (this.currentMode === "desktop") {
      this.setupDesktopAnimation();
    }
  },

  stopDesktopLoop() {
    if (this.intervalId) {
      clearInterval(this.intervalId);
      this.intervalId = null;
    }
    if (this.cleanupTimeout) {
      clearTimeout(this.cleanupTimeout);
      this.cleanupTimeout = null;
    }
    this.isAnimating = false;
  },

  init() {
    const isDesktop = window.innerWidth >= 1024;

    if (isDesktop && this.currentMode !== "desktop") {
      this.cleanupMobile();
      this.setupDesktopAnimation();
      this.currentMode = "desktop";
    } else if (!isDesktop && this.currentMode !== "mobile") {
      this.cleanupDesktop();
      this.setupMobileScroll();
      this.currentMode = "mobile";
    }
  },

  restoreOriginal() {
    if (!this.el.querySelector('[data-part="logo-group"]') && this.originalHTML) {
      this.el.innerHTML = this.originalHTML;
    }
  },

  setupDesktopAnimation() {
    this.stopDesktopLoop();
    this.restoreOriginal();
    this.el.setAttribute("data-animation-mode", "desktop");
    const groups = Array.from(this.el.querySelectorAll('[data-part="logo-group"]'));

    groups.forEach((group, groupIndex) => {
      const logos = Array.from(group.querySelectorAll('[data-part="org-logo"]'));

      if (groupIndex === 0) {
        group.setAttribute("data-state", "active");
        logos.forEach((logo) => {
          logo.style.transitionDelay = "0ms";
          logo.setAttribute("data-state", "visible");
        });
      } else {
        group.setAttribute("data-state", "hidden");
        logos.forEach((logo) => {
          logo.style.transitionDelay = "0ms";
          logo.setAttribute("data-state", "hidden");
        });
      }
    });

    this.groups = groups;
    this.currentIndex = 0;
    this.intervalId = setInterval(() => this.transition(), 3000);
  },

  setupMobileScroll() {
    const container = this.el;

    if (container.querySelector('[data-part="track"]')) {
      return;
    }

    this.restoreOriginal();
    container.setAttribute("data-animation-mode", "mobile");
    const allLogos = Array.from(container.querySelectorAll('[data-part="org-logo"]'));
    const uniqueLogos = [];
    const seenLabels = new Set();

    allLogos.forEach((logo) => {
      const label = logo.getAttribute("aria-label");
      if (!seenLabels.has(label)) {
        seenLabels.add(label);
        uniqueLogos.push(logo);
      }
    });

    // Two identical sets in one track; the CSS animation (home.css) slides
    // the track by one set, so the loop is seamless and runs on the
    // compositor instead of a rAF loop nudging a transform every frame.
    container.innerHTML = "";
    const track = document.createElement("div");
    track.setAttribute("data-part", "track");

    const buildSet = (hidden) => {
      const set = document.createElement("div");
      set.setAttribute("data-part", "logo-set");
      if (hidden) set.setAttribute("aria-hidden", "true");
      uniqueLogos.forEach((logo) => {
        const clone = logo.cloneNode(true);
        if (hidden) clone.setAttribute("tabindex", "-1");
        set.appendChild(clone);
      });
      return set;
    };
    track.appendChild(buildSet(false));
    track.appendChild(buildSet(true));

    container.appendChild(track);
    container.setAttribute("data-animation-mode", "mobile");

    // Constant speed regardless of how many logos there are: one set's
    // width at MARQUEE_SPEED px/s.
    const setWidth = track.scrollWidth / 2;
    if (setWidth > 0) {
      track.style.setProperty("--marquee-duration", `${setWidth / MARQUEE_SPEED}s`);
    }
  },

  transition() {
    if (this.isAnimating || !this.groups || this.groups.length <= 1) return;

    this.isAnimating = true;

    const currentGroup = this.groups[this.currentIndex];
    const nextIndex = (this.currentIndex + 1) % this.groups.length;
    const nextGroup = this.groups[nextIndex];

    // Self-heal before animating: if a lost cleanup timer (throttled tab,
    // bfcache freeze) left extra groups visible, hide everything that isn't
    // part of this crossfade.
    this.groups.forEach((group, index) => {
      if (index === this.currentIndex || index === nextIndex) return;
      group.setAttribute("data-state", "hidden");
      group.querySelectorAll('[data-part="org-logo"]').forEach((logo) => {
        logo.style.transitionDelay = "0ms";
        logo.setAttribute("data-state", "hidden");
      });
    });

    const currentLogos = Array.from(currentGroup.querySelectorAll('[data-part="org-logo"]'));
    const nextLogos = Array.from(nextGroup.querySelectorAll('[data-part="org-logo"]'));

    currentLogos.forEach((logo, i) => {
      logo.style.transitionDelay = `${i * 40}ms`;
      logo.setAttribute("data-state", "exiting");
    });

    nextLogos.forEach((logo, i) => {
      logo.style.transitionDelay = `${i * 40}ms`;
      logo.setAttribute("data-state", "visible");
    });

    currentGroup.setAttribute("data-state", "active");
    nextGroup.setAttribute("data-state", "active");

    this.currentIndex = nextIndex;

    const maxDelay = Math.max(currentLogos.length, nextLogos.length) * 40 + 500;

    this.cleanupTimeout = setTimeout(() => {
      this.cleanupTimeout = null;
      this.isAnimating = false;

      this.groups.forEach((group, index) => {
        if (index !== this.currentIndex) {
          group.setAttribute("data-state", "hidden");
          const logos = Array.from(group.querySelectorAll('[data-part="org-logo"]'));
          logos.forEach((logo) => {
            logo.style.transitionDelay = "0ms";
            logo.setAttribute("data-state", "hidden");
          });
        }
      });
    }, maxDelay);
  },

  cleanupDesktop() {
    this.stopDesktopLoop();

    this.el.removeAttribute("data-animation-mode");

    if (this.groups) {
      this.groups.forEach((group) => {
        group.removeAttribute("data-state");
        const logos = Array.from(group.querySelectorAll('[data-part="org-logo"]'));
        logos.forEach((logo) => {
          logo.removeAttribute("data-state");
          logo.style.transitionDelay = "";
        });
      });
    }
  },

  cleanupMobile() {
    // The marquee is a CSS animation on the track; restoring the original
    // markup (restoreOriginal) is all the teardown it needs.
  },

  handleResize() {
    this.init();
  },

  teardown() {
    this.stopDesktopLoop();
    this.cleanupMobile();
    window.removeEventListener("resize", this.handleResize);
    document.removeEventListener("visibilitychange", this.handleVisibility);
    window.removeEventListener("pageshow", this.handlePageshow);
    window.removeEventListener("pagehide", this.handlePagehide);
    if (this.el.logoTransitionTeardown === this.teardownRef) {
      delete this.el.logoTransitionTeardown;
    }
  },

  destroyed() {
    this.cleanupDesktop();
    this.teardown();
  },
};
