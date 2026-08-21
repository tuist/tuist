const IncrementalityModelsDiagram = {
  mounted() {
    this.observer = new IntersectionObserver(
      ([entry]) => {
        this.el.classList.toggle("is-visible", entry.isIntersecting);
      },
      { threshold: 0.35 },
    );

    this.observer.observe(this.el);
  },

  destroyed() {
    this.observer?.disconnect();
  },
};

export { IncrementalityModelsDiagram };
