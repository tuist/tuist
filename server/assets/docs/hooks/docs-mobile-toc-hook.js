function toggleToc(toc) {
  const isOpen = toc.getAttribute("data-state") === "open";
  toc.setAttribute("data-state", isOpen ? "closed" : "open");
}

const DocsMobileTocHook = {
  mounted() {
    const toc = document.getElementById("docs-mobile-toc");

    this.el.addEventListener("click", () => {
      if (toc) toggleToc(toc);
    });

    toc?.addEventListener("click", (e) => {
      if (e.target.closest("[data-part='mobile-toc-item'], .noora-link-button")) {
        toc.setAttribute("data-state", "closed");
      }
    });
  },
};

export default DocsMobileTocHook;
