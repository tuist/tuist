export const LogoTransition = {
  mounted() {
    this.currentIndex = 0;
    this.isAnimating = false;
    this.intervalId = null;
    this.animationFrame = null;
    this.originalHTML = this.el.innerHTML;
    this.currentMode = null;

    this.handleResize = this.handleResize.bind(this);
    window.addEventListener("resize", this.handleResize);
    this.init();
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
    this.restoreOriginal();
    this.el.setAttribute("data-animation-mode", "desktop");
    const groups = Array.from(this.el.querySelectorAll('[data-part="logo-group"]'));

    groups.forEach((group, groupIndex) => {
      const logos = Array.from(group.querySelectorAll('[data-part="org-logo"]'));

      if (groupIndex === 0) {
        group.setAttribute("data-state", "active");
        logos.forEach((logo) => {
          logo.setAttribute("data-state", "visible");
        });
      } else {
        group.setAttribute("data-state", "hidden");
        logos.forEach((logo) => {
          logo.setAttribute("data-state", "hidden");
        });
      }
    });

    this.groups = groups;

    if (this.intervalId) {
      clearInterval(this.intervalId);
    }

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

    container.innerHTML = "";
    const track = document.createElement("div");
    track.setAttribute("data-part", "track");

    uniqueLogos.forEach((logo) => {
      track.appendChild(logo.cloneNode(true));
    });

    uniqueLogos.forEach((logo) => {
      const clone = logo.cloneNode(true);
      clone.setAttribute("aria-hidden", "true");
      clone.setAttribute("tabindex", "-1");
      track.appendChild(clone);
    });

    container.appendChild(track);
    container.setAttribute("data-animation-mode", "mobile");

    let scrollPosition = 0;
    const scroll = () => {
      scrollPosition += 0.5;

      const maxScroll = track.scrollWidth / 2;
      if (scrollPosition >= maxScroll) {
        scrollPosition = 0;
      }

      track.style.transform = `translateX(-${scrollPosition}px)`;
      this.animationFrame = requestAnimationFrame(scroll);
    };

    this.animationFrame = requestAnimationFrame(scroll);
  },

  transition() {
    if (this.isAnimating || !this.groups || this.groups.length <= 1) return;

    this.isAnimating = true;

    const currentGroup = this.groups[this.currentIndex];
    const nextIndex = (this.currentIndex + 1) % this.groups.length;
    const nextGroup = this.groups[nextIndex];

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

    setTimeout(() => {
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
    if (this.intervalId) {
      clearInterval(this.intervalId);
      this.intervalId = null;
    }

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
    if (this.animationFrame) {
      cancelAnimationFrame(this.animationFrame);
      this.animationFrame = null;
    }
  },

  handleResize() {
    this.init();
  },

  destroyed() {
    this.cleanupDesktop();
    this.cleanupMobile();
    window.removeEventListener("resize", this.handleResize);
  }
};
