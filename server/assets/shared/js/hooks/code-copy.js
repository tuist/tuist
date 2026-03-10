const COPY_CHECK_SVG = `<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path stroke="none" d="M0 0h24v24H0z" fill="none"/><path d="M7 9.667a2.667 2.667 0 0 1 2.667 -2.667h8.666a2.667 2.667 0 0 1 2.667 2.667v8.666a2.667 2.667 0 0 1 -2.667 2.667h-8.666a2.667 2.667 0 0 1 -2.667 -2.667z" /><path d="M4.012 16.737a2 2 0 0 1 -1.012 -1.737v-10c0 -1.1 .9 -2 2 -2h10c.75 0 1.158 .385 1.5 1" /><path d="M11 14l2 2l4 -4" /></svg>`;

function flashCopyCheck(button) {
  const originalContent = button.innerHTML;
  button.innerHTML = COPY_CHECK_SVG;
  setTimeout(() => {
    button.innerHTML = originalContent;
  }, 2000);
}

function setupCodeCopy(el) {
  el.querySelectorAll('.code-window [data-part="copy"]').forEach((button) => {
    button.style.cursor = "pointer";
    button.addEventListener("click", () => {
      const codeBlock = button.closest(".code-window")?.querySelector('[data-part="code"]');
      if (!codeBlock) return;
      navigator.clipboard
        .writeText(codeBlock.textContent.trim())
        .then(() => flashCopyCheck(button))
        .catch((err) => console.error("Failed to copy code:", err));
    });
  });
}

const CodeCopy = {
  mounted() {
    setupCodeCopy(this.el);
  },
};

export { CodeCopy, setupCodeCopy, flashCopyCheck };
