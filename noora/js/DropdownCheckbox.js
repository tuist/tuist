/**
 * Phoenix LiveView Hook for dropdown checkbox items.
 * Handles clicks on the checkbox to toggle without closing the dropdown,
 * while clicks on the label toggle and close the dropdown.
 */
export default {
  mounted() {
    this.handleClick = (event) => {
      const checkbox = this.el.querySelector('[data-part="checkbox"]');
      const clickedOnCheckbox = checkbox && checkbox.contains(event.target);

      // Close dropdown if clicked on label (not checkbox)
      if (!clickedOnCheckbox) {
        const dropdown = this.el.closest(".noora-dropdown");
        if (dropdown) {
          window.dispatchEvent(
            new CustomEvent("phx:close-dropdown", {
              detail: { id: dropdown.id },
            }),
          );
        }
      }
    };

    this.el.addEventListener("click", this.handleClick);
  },

  destroyed() {
    this.el.removeEventListener("click", this.handleClick);
  },
};
