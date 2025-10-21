export default {
  mounted() {
    // Store original HTML content
    this.originalHTML = this.el.innerHTML;
    this.init();
    window.addEventListener("resize", () => this.init());
  },

  init() {
    const container = this.el;
    const isSmallViewport = window.innerWidth < 768;

    if (!isSmallViewport) {
      // Reset on larger viewports
      if (this.animationFrame) {
        cancelAnimationFrame(this.animationFrame);
        this.animationFrame = null;
      }

      // Restore original HTML if it was modified
      if (!container.querySelector('[data-part="rows"]')) {
        container.innerHTML = this.originalHTML;
      }

      return;
    }

    // Only rebuild if not already in scroll mode
    if (container.querySelector('[data-part="track"]')) {
      return;
    }

    // Clone all logos for seamless looping
    const rows = Array.from(container.querySelectorAll('[data-part="rows"]'));
    const allLogos = rows.flatMap((row) => Array.from(row.children));

    // Clear existing content and create single scrolling track
    container.innerHTML = "";
    const track = document.createElement("div");
    track.setAttribute("data-part", "track");

    // Add original logos
    allLogos.forEach((logo) => {
      track.appendChild(logo.cloneNode(true));
    });

    // Add duplicated logos for seamless loop
    allLogos.forEach((logo) => {
      const clone = logo.cloneNode(true);
      clone.setAttribute("aria-hidden", "true");
      clone.setAttribute("tabindex", "-1");
      track.appendChild(clone);
    });

    container.appendChild(track);

    // Start animation
    let scrollPosition = 0;
    const scroll = () => {
      scrollPosition += 0.5; // Adjust speed here

      const maxScroll = track.scrollWidth / 2;
      if (scrollPosition >= maxScroll) {
        scrollPosition = 0;
      }

      track.style.transform = `translateX(-${scrollPosition}px)`;
      this.animationFrame = requestAnimationFrame(scroll);
    };

    this.animationFrame = requestAnimationFrame(scroll);
  },

  destroyed() {
    if (this.animationFrame) {
      cancelAnimationFrame(this.animationFrame);
    }
    window.removeEventListener("resize", () => this.init());
  },
};
