const CounterAnimation = {
  mounted() {
    this.hasAnimated = false;
    this.targetValue = parseInt(this.el.dataset.counterTarget, 10) || 0;
    this.duration = parseInt(this.el.dataset.counterDuration, 10) || 2000;
    this.locale = this.el.dataset.counterLocale || "en-US";

    this.observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting && !this.hasAnimated) {
            this.hasAnimated = true;
            this.animateCounter();
          }
        });
      },
      { threshold: 0.1 }
    );

    this.observer.observe(this.el);
  },

  destroyed() {
    if (this.observer) {
      this.observer.disconnect();
    }
  },

  animateCounter() {
    const startTime = performance.now();
    const startValue = 0;
    const endValue = this.targetValue;

    const animate = (currentTime) => {
      const elapsed = currentTime - startTime;
      const progress = Math.min(elapsed / this.duration, 1);

      // Ease-out cubic for smooth deceleration
      const easedProgress = 1 - Math.pow(1 - progress, 3);

      const currentValue = Math.floor(
        startValue + (endValue - startValue) * easedProgress
      );
      this.el.textContent = currentValue.toLocaleString(this.locale);

      if (progress < 1) {
        requestAnimationFrame(animate);
      } else {
        this.el.textContent = endValue.toLocaleString(this.locale);
      }
    };

    requestAnimationFrame(animate);
  },
};

export { CounterAnimation };
