const CodeCopy = {
  mounted() {
    // Find all copy buttons in marketing windows
    const copyButtons = this.el.querySelectorAll('#marketing-window [data-part="copy"]');

    copyButtons.forEach((button) => {
      button.style.cursor = "pointer";

      button.addEventListener("click", () => {
        // Find the code block within the same marketing window
        const window = button.closest("#marketing-window");
        const codeBlock = window.querySelector('[data-part="code"]');

        if (codeBlock) {
          // Get the text content from the code block and trim leading/trailing whitespace
          const code = codeBlock.textContent.trim();

          // Copy to clipboard
          navigator.clipboard
            .writeText(code)
            .then(() => {
              // Visual feedback - briefly change the button appearance
              button.style.opacity = "0.5";
              setTimeout(() => {
                button.style.opacity = "1";
              }, 200);
            })
            .catch((err) => {
              console.error("Failed to copy code:", err);
            });
        }
      });
    });
  },
};

export { CodeCopy };
