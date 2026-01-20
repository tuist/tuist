const ScrollToTop = {
  mounted() {
    this.handleEvent("scroll-to-target", () => {
      // Use requestAnimationFrame to ensure DOM is updated
      requestAnimationFrame(() => {
        this.scrollToSection();
      });
    });
  },
  scrollToSection() {
    // Get the target selector from data-scroll-target attribute, default to top of page
    const targetSelector = this.el.dataset.scrollTarget;

    if (targetSelector) {
      const targetElement = document.querySelector(targetSelector);
      if (targetElement) {
        // Get the absolute position of the element from the top of the document
        const elementTop = targetElement.offsetTop;

        // Scroll to position with offset
        window.scrollTo({
          top: elementTop - 20,
          behavior: "smooth",
        });
        return;
      }
    }

    // Fallback to scrolling to top
    window.scrollTo({ top: 0, behavior: "smooth" });
  },
};

export { ScrollToTop };
