export const LazyIframe = {
  mounted() {
    // Find all iframes with data-visualization attribute
    const iframes = this.el.querySelectorAll('iframe[data-visualization]');

    if (iframes.length === 0) return;

    // Store original src attributes and replace with data-src
    iframes.forEach(iframe => {
      const src = iframe.getAttribute('src');
      if (src) {
        iframe.setAttribute('data-src', src);
        iframe.removeAttribute('src');
        iframe.style.minHeight = iframe.getAttribute('height') + 'px';
      }
    });

    // Create Intersection Observer with options
    const observerOptions = {
      root: null,
      rootMargin: '200px', // Start loading 200px before entering viewport
      threshold: 0
    };

    const observer = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          const iframe = entry.target;
          const dataSrc = iframe.getAttribute('data-src');

          if (dataSrc && !iframe.getAttribute('src')) {
            // Load the iframe
            iframe.setAttribute('src', dataSrc);
            iframe.removeAttribute('data-src');

            // Stop observing this iframe
            observer.unobserve(iframe);
          }
        }
      });
    }, observerOptions);

    // Observe all iframes
    iframes.forEach(iframe => {
      observer.observe(iframe);
    });

    // Clean up on destroy
    this.observer = observer;
  },

  destroyed() {
    if (this.observer) {
      this.observer.disconnect();
    }
  }
};
