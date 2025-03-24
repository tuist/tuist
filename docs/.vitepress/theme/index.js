import DefaultTheme from "vitepress/theme";
import "./custom.css";
/** @type {import('vitepress').Theme} */
import Layout from "./layouts/Layout.vue";
import LocalizedLink from "./components/LocalizedLink.vue";
import HomeCard from "./components/HomeCard.vue";
import HomeCards from "./components/HomeCards.vue";
import HomeVideos from "./components/HomeVideos.vue";
import HomeCommunity from "./components/HomeCommunity.vue";
import HomeCommunityItem from "./components/HomeCommunityItem.vue";

export default {
  Layout,
  extends: DefaultTheme,
  enhanceApp({ app }) {
    app.component("LocalizedLink", LocalizedLink);
    app.component("HomeCard", HomeCard);
    app.component("HomeCards", HomeCards);
    app.component("HomeVideos", HomeVideos);
    app.component("HomeCommunity", HomeCommunity);
    app.component("HomeCommunityItem", HomeCommunityItem);
  },
};
