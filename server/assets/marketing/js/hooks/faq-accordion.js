/**
 * FaqAccordion Hook
 *
 * Manages FAQ accordion expand/collapse functionality. Handles button clicks,
 * keyboard navigation (Enter/Space), and manages ARIA attributes for accessibility.
 * Only one FAQ can be expanded at a time.
 */
export const FaqAccordion = {
  mounted() {
    const button = this.el;
    const questionContainer = button.closest('[data-part="question"]');
    const answerId = button.getAttribute("aria-controls");
    const answer = document.getElementById(answerId);

    if (!questionContainer || !answer) {
      console.error("FAQ accordion: Missing question container or answer element");
      return;
    }

    const toggleAccordion = (e) => {
      e.preventDefault();
      e.stopPropagation();

      const isExpanded = button.getAttribute("aria-expanded") === "true";

      if (isExpanded) {
        // Collapse this question
        button.setAttribute("aria-expanded", "false");
        questionContainer.setAttribute("data-expanded", "false");
      } else {
        // Collapse all other questions first
        const allQuestions = document.querySelectorAll('[data-part="question"]');
        allQuestions.forEach((q) => {
          const btn = q.querySelector('[data-part="header"]');
          if (btn) {
            btn.setAttribute("aria-expanded", "false");
            q.setAttribute("data-expanded", "false");
          }
        });

        // Expand this question
        button.setAttribute("aria-expanded", "true");
        questionContainer.setAttribute("data-expanded", "true");
      }
    };

    // Handle keyboard navigation
    const handleKeydown = (e) => {
      if (e.key === "Enter" || e.key === " ") {
        toggleAccordion(e);
      }
    };

    // Attach event listeners
    button.addEventListener("click", toggleAccordion);
    button.addEventListener("keydown", handleKeydown);

    // Cleanup
    this.destroyed = () => {
      button.removeEventListener("click", toggleAccordion);
      button.removeEventListener("keydown", handleKeydown);
    };
  },
};
