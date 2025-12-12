import { codeToHtml } from "shiki";

const ShikiHighlight = {
  async mounted() {
    // Find all shiki-highlight elements
    const codeBlocks = this.el.querySelectorAll("shiki-highlight");

    for (const block of codeBlocks) {
      const language = block.getAttribute("language") || "text";
      const code = block.textContent.trim();

      try {
        // Highlight the code using Shiki
        const html = await codeToHtml(code, {
          lang: language,
          theme: "github-light",
        });

        // Extract just the <pre> content from the generated HTML
        const tempDiv = document.createElement("div");
        tempDiv.innerHTML = html;
        const pre = tempDiv.querySelector("pre");

        if (pre) {
          // Replace the shiki-highlight element with the highlighted code
          block.innerHTML = pre.innerHTML;
        }
      } catch (error) {
        console.error(`Failed to highlight code for language: ${language}`, error);
        // Keep the original text if highlighting fails
      }
    }
  },
};

export { ShikiHighlight };
