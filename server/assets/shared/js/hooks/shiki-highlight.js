import { codeToHtml } from "shiki";

async function highlightCodeBlocks(el) {
  const codeBlocks = el.querySelectorAll("shiki-highlight");

  for (const block of codeBlocks) {
    const language = block.getAttribute("language") || "text";
    const code = block.textContent.trim();

    try {
      const html = await codeToHtml(code, {
        lang: language,
        theme: "github-light",
      });

      const tempDiv = document.createElement("div");
      tempDiv.innerHTML = html;
      const pre = tempDiv.querySelector("pre");

      if (pre) {
        block.innerHTML = pre.innerHTML;
      }
    } catch (error) {
      console.error(`Failed to highlight code for language: ${language}`, error);
    }
  }
}

const ShikiHighlight = {
  async mounted() {
    highlightCodeBlocks(this.el);
  },
  async updated() {
    highlightCodeBlocks(this.el);
  },
};

export { ShikiHighlight, highlightCodeBlocks };
