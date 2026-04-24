export function setTheme(theme) {
  const resolvedColorScheme = window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
  document.documentElement.style.setProperty("color-scheme", theme === "system" ? "light dark" : theme);
  document.documentElement.setAttribute("data-theme", theme === "system" ? resolvedColorScheme : theme);
  try {
    localStorage.setItem("preferred-theme", theme);
  } catch (e) {
    // localStorage may not be available in private/incognito mode
  }
  window.dispatchEvent(new CustomEvent("changed-preferred-theme", { detail: theme }));
}

export function getPreferredTheme() {
  try {
    const preferredTheme = localStorage.getItem("preferred-theme");
    return preferredTheme === "null" || preferredTheme === null ? "system" : preferredTheme;
  } catch (e) {
    // localStorage may not be available in private/incognito mode
    return "system";
  }
}

export function observeThemeChanges() {
  window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", (e) => {
    setTheme(getPreferredTheme());
  });

  setTheme(getPreferredTheme());
}

export const ThemeToggle = {
  mounted() {
    const handleClick = (event) => {
      event.preventDefault();

      const currentTheme = document.documentElement.getAttribute("data-theme") === "dark" ? "dark" : "light";

      setTheme(currentTheme === "dark" ? "light" : "dark");
    };

    this.el.addEventListener("click", handleClick);
    this.handleClick = handleClick;
  },

  destroyed() {
    if (this.el && this.handleClick) {
      this.el.removeEventListener("click", this.handleClick);
    }
  },
};

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
