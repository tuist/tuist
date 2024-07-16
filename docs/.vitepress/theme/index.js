import DefaultTheme from "vitepress/theme";
import "./custom.css";
import Button from "./components/Button.vue";
/** @type {import('vitepress').Theme} */
export default {
  extends: DefaultTheme,
  enhanceApp({ app }) {
    app.component("Button", Button);
  },
};
