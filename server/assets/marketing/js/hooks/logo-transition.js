export default {
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
    const groups = Array.from(this.el.querySelectorAll('[data-part="logo-group"]'));

    groups.forEach((group, groupIndex) => {
      group.style.position = "absolute";
      group.style.top = "0";
      group.style.left = "0";
      group.style.width = "100%";
      group.style.display = "flex";
      group.style.flexDirection = "column";
      group.style.justifyContent = "center";
      group.style.alignItems = "center";
      group.style.gap = "var(--noora-spacing-9)";
      group.style.transition = "none";
      group.style.willChange = "transform, opacity, filter";

      const logos = Array.from(group.querySelectorAll('[data-part="org-logo"]'));

      if (groupIndex === 0) {
        group.style.opacity = "1";
        logos.forEach((logo) => {
          logo.style.transform = "translateY(0)";
          logo.style.opacity = "1";
          logo.style.filter = "blur(0px)";
          logo.style.willChange = "transform, opacity, filter";
        });
      } else {
        group.style.opacity = "0";
        logos.forEach((logo) => {
          logo.style.transform = "translateY(20px)";
          logo.style.opacity = "0";
          logo.style.filter = "blur(4px)";
          logo.style.willChange = "transform, opacity, filter";
        });
      }
    });

    this.el.style.position = "relative";
    this.el.style.minHeight = "160px";
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
      logo.style.transition = `transform 0.5s ease-out ${i * 40}ms, opacity 0.5s ease-out ${i * 40}ms, filter 0.5s ease-out ${i * 40}ms`;
      logo.style.transform = "translateY(-20px)";
      logo.style.opacity = "0";
      logo.style.filter = "blur(4px)";
    });

    nextLogos.forEach((logo, i) => {
      logo.style.transition = `transform 0.5s ease-out ${i * 40}ms, opacity 0.5s ease-out ${i * 40}ms, filter 0.5s ease-out ${i * 40}ms`;
      logo.style.transform = "translateY(0)";
      logo.style.opacity = "1";
      logo.style.filter = "blur(0px)";
    });

    currentGroup.style.transition = "none";
    currentGroup.style.opacity = "1";
    nextGroup.style.transition = "none";
    nextGroup.style.opacity = "1";

    this.currentIndex = nextIndex;

    const maxDelay = Math.max(currentLogos.length, nextLogos.length) * 40 + 500;

    setTimeout(() => {
      this.isAnimating = false;

      this.groups.forEach((group, index) => {
        if (index !== this.currentIndex) {
          group.style.opacity = "0";
          const logos = Array.from(group.querySelectorAll('[data-part="org-logo"]'));
          logos.forEach((logo) => {
            logo.style.transition = "none";
            logo.style.transform = "translateY(20px)";
            logo.style.opacity = "0";
            logo.style.filter = "blur(4px)";
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

    if (this.groups) {
      this.groups.forEach((group) => {
        group.style.position = "";
        group.style.top = "";
        group.style.left = "";
        group.style.width = "";
        group.style.transition = "";
        group.style.willChange = "";
        group.style.transform = "";
        group.style.opacity = "";
        group.style.filter = "";
        group.style.display = "";
        group.style.flexDirection = "";
        group.style.justifyContent = "";
        group.style.alignItems = "";
        group.style.gap = "";

        const logos = Array.from(group.querySelectorAll('[data-part="org-logo"]'));
        logos.forEach((logo) => {
          logo.style.transform = "";
          logo.style.opacity = "";
          logo.style.filter = "";
          logo.style.transition = "";
          logo.style.willChange = "";
        });
      });
    }

    this.el.style.position = "";
    this.el.style.minHeight = "";
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
