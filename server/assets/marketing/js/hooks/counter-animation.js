const CounterAnimation = {
  mounted() {
    this.currentValue = 0;
    this.targetValue = parseInt(this.el.dataset.counterTarget, 10) || 0;
    this.duration = parseInt(this.el.dataset.counterDuration, 10) || 2000;
    this.locale = this.el.dataset.counterLocale || "en-US";
    this.animationId = null;

    this.observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting && this.currentValue !== this.targetValue) {
            this.animateCounter(this.currentValue, this.targetValue);
          }
        });
      },
      { threshold: 0.1 }
    );

    this.observer.observe(this.el);
  },

  updated() {
    const newTarget = parseInt(this.el.dataset.counterTarget, 10) || 0;

    if (newTarget !== this.targetValue) {
      const oldValue = this.targetValue;
      this.targetValue = newTarget;

      // If element is visible, animate to new value
      if (this.isElementVisible()) {
        this.animateCounter(oldValue, newTarget);
      } else {
        // Update immediately if not visible, will animate when scrolled into view
        this.currentValue = newTarget;
        this.el.textContent = newTarget.toLocaleString(this.locale);
      }
    }
  },

  destroyed() {
    if (this.observer) {
      this.observer.disconnect();
    }
    if (this.animationId) {
      cancelAnimationFrame(this.animationId);
    }
  },

  isElementVisible() {
    const rect = this.el.getBoundingClientRect();
    return (
      rect.top < window.innerHeight &&
      rect.bottom > 0 &&
      rect.left < window.innerWidth &&
      rect.right > 0
    );
  },

  animateCounter(startValue, endValue) {
    // Cancel any ongoing animation
    if (this.animationId) {
      cancelAnimationFrame(this.animationId);
    }

    const startTime = performance.now();
    // Use shorter duration for updates (value is already non-zero)
    const duration = startValue === 0 ? this.duration : this.duration / 2;

    const animate = (currentTime) => {
      const elapsed = currentTime - startTime;
      const progress = Math.min(elapsed / duration, 1);

      // Ease-out cubic for smooth deceleration
      const easedProgress = 1 - Math.pow(1 - progress, 3);

      this.currentValue = Math.floor(
        startValue + (endValue - startValue) * easedProgress
      );
      this.el.textContent = this.currentValue.toLocaleString(this.locale);

      if (progress < 1) {
        this.animationId = requestAnimationFrame(animate);
      } else {
        this.currentValue = endValue;
        this.el.textContent = endValue.toLocaleString(this.locale);
        this.animationId = null;
      }
    };

    this.animationId = requestAnimationFrame(animate);
  },
};

export { CounterAnimation };
