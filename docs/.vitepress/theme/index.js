import DefaultTheme from "vitepress/theme";
import "./custom.css";
/** @type {import('vitepress').Theme} */
import Layout from "./Layout.vue";

export default {
  Layout,
  extends: DefaultTheme,
  enhanceApp({ app }) {},
};
