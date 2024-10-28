import DefaultTheme from "vitepress/theme";
import "./custom.css";
/** @type {import('vitepress').Theme} */
import Layout from "./Layout.vue";
import LocalizedLink from "./components/LocalizedLink.vue";
import Card from "./components/Card.vue";

export default {
  Layout,
  extends: DefaultTheme,
  enhanceApp({ app }) {
    app.component("LocalizedLink", LocalizedLink);
    app.component("Card", Card);
  },
};
