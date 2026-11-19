export default function languageDropdown(NooraDropdown) {
  return {
    ...NooraDropdown,
    mounted() {
      NooraDropdown.mounted.call(this);
      this.handleLanguageKeydown = (event) => {
        if (!event.isTrusted || event.defaultPrevented || !["Enter", " "].includes(event.key)) return;
        if (!this.menu.api.open || !event.target.closest('[role="menu"]')) return;
        if (event.key === " " && this.menu.machine.computed("isTypingAhead")) return;

        // Zag navigates keyboard choices with an untrusted click, which Glossia
        // ignores. Record the highlighted choice during the trusted keydown;
        // pointer choices remain delegated to the SDK to avoid duplicate events.
        const link = this.el.querySelector("a[data-glossia-language][data-highlighted]");
        if (link && !link.hasAttribute("data-disabled")) {
          globalThis.glossia?.selectLanguage(link.dataset.glossiaLanguage);
        }
      };
      this.el.addEventListener("keydown", this.handleLanguageKeydown, true);
    },
    destroyed() {
      this.el.removeEventListener("keydown", this.handleLanguageKeydown, true);
      NooraDropdown.destroyed.call(this);
    },
  };
}
