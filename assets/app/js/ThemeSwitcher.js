function setTheme(theme) {
  const resolvedColorScheme = window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
  document.documentElement.style.setProperty("color-scheme", theme === "system" ? "light dark" : theme);
  document.documentElement.setAttribute("data-theme", theme === "system" ? resolvedColorScheme : theme);
  localStorage.setItem("preferred-theme", theme);
  window.dispatchEvent(new CustomEvent("changed-preferred-theme", { detail: theme }));
}

function getPreferredTheme() {
  const preferredTheme = localStorage.getItem("preferred-theme");
  return preferredTheme === "null" ? "system" : preferredTheme;
}

export function observeThemeChanges() {
  window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", (e) => {
    setTheme(getPreferredTheme());
  });

  setTheme(getPreferredTheme());
}

export default {
  mounted() {
    setTimeout(() => {
      this.el.checked = getPreferredTheme() === this.el.value;
    }, 100);

    const handleInput = () => {
      setTheme(this.el.value);
    };

    this.el.addEventListener("input", handleInput);

    this.handleInput = handleInput;
  },

  destroyed() {
    if (this.el && this.handleInput) {
      this.el.removeEventListener("input", this.handleInput);
    }
  },
};
