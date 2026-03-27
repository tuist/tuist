const CounterAnimation = {
  mounted() {
    this.currentValue = 0;
    this.targetValue = parseInt(this.el.dataset.counterTarget, 10) || 0;
    this.duration = parseInt(this.el.dataset.counterDuration, 10) || 2000;
    this.animationId = null;

    this.observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            this.animateCounter(this.currentValue, this.targetValue);
          }
        });
      },
      { threshold: 0.1 },
    );

    this.observer.observe(this.el);
  },

  updated() {
    const newTarget = parseInt(this.el.dataset.counterTarget, 10) || 0;

    if (newTarget !== this.targetValue) {
      const oldValue = this.targetValue;
      this.targetValue = newTarget;
      this.animateCounter(oldValue, newTarget);
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

      this.currentValue = Math.floor(startValue + (endValue - startValue) * easedProgress);
      this.el.textContent = this.currentValue.toLocaleString();

      if (progress < 1) {
        this.animationId = requestAnimationFrame(animate);
      } else {
        this.currentValue = endValue;
        this.el.textContent = endValue.toLocaleString();
        this.animationId = null;
      }
    };

    this.animationId = requestAnimationFrame(animate);
  },
};

export { CounterAnimation };
