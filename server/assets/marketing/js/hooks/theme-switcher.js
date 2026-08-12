/*
 * Theme switcher button group (footer + navbar mobile menu).
 *
 * Mount on a noora button group whose items carry data-theme-option
 * ("system" | "light" | "dark"). Clicking an item applies + persists the
 * preference; every mounted switcher re-syncs its selected state off the
 * tuist:theme-change event, so the footer and mobile-menu instances stay
 * in agreement.
 */

import { applyPreferredTheme, getPreferredTheme, onThemeChange } from "../lib/theme.js";

export const ThemeSwitcher = {
  mounted() {
    this.buttons = Array.from(this.el.querySelectorAll("[data-theme-option]"));

    this.sync = () => {
      const preference = getPreferredTheme();
      for (const button of this.buttons) {
        if (button.dataset.themeOption === preference) {
          button.setAttribute("data-selected", "");
        } else {
          button.removeAttribute("data-selected");
        }
      }
    };

    this.onClick = (event) => {
      const button = event.target.closest("[data-theme-option]");
      if (!button || !this.el.contains(button)) return;
      applyPreferredTheme(button.dataset.themeOption);
    };

    this.el.addEventListener("click", this.onClick);
    this.offThemeChange = onThemeChange(this.sync);
    this.sync();
  },

  destroyed() {
    this.el.removeEventListener("click", this.onClick);
    if (this.offThemeChange) this.offThemeChange();
  },
};
