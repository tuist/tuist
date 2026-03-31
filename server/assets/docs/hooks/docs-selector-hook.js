/**
 * Hook for the docs account/project selector breadcrumbs.
 *
 * Breadcrumb items inside .noora-breadcrumbs skip Zag.js prop spreading,
 * so we intercept clicks on items ourselves and push events to the LiveView.
 */
export default {
  mounted() {
    this.handleClick = (event) => {
      const item = event.target.closest("[data-part='item']");
      if (!item) return;

      const value = item.dataset.value;
      if (!value) return;

      const breadcrumb = item.closest(".noora-breadcrumb");
      if (!breadcrumb) return;

      const eventName = breadcrumb.dataset.selectorEvent;
      if (!eventName) return;

      event.preventDefault();
      event.stopPropagation();
      this.pushEvent(eventName, { value });
    };

    this.el.addEventListener("click", this.handleClick);
  },

  destroyed() {
    this.el.removeEventListener("click", this.handleClick);
  },
};
