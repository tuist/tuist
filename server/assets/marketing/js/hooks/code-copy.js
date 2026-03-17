const CodeCopy = {
  mounted() {
    const copyButtons = this.el.querySelectorAll(
      '#marketing-window [data-part="copy"]',
    );

    copyButtons.forEach((button) => {
      button.addEventListener("click", () => {
        const window = button.closest("#marketing-window");
        const codeBlock = window.querySelector('[data-part="code"]');

        if (codeBlock) {
          const code = codeBlock.textContent.trim();

          navigator.clipboard
            .writeText(code)
            .then(() => {
              const copyIcon = button.querySelector('[data-icon="copy"]');
              const checkIcon = button.querySelector('[data-icon="copy-check"]');

              copyIcon.style.display = "none";
              checkIcon.style.display = "";

              setTimeout(() => {
                checkIcon.style.display = "none";
                copyIcon.style.display = "";
              }, 2000);
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
