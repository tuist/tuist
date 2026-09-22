import { defineConfig } from "vitepress";
import { site } from "../site.js";

export default defineConfig({
  title: "Once",
  titleTemplate: false,
  description: site.description,
  cleanUrls: true,
  lastUpdated: true,
  sitemap: {
    hostname: "https://once.tuist.dev",
  },
  head: [
    ["link", { rel: "icon", type: "image/png", href: "/favicon.png" }],
    ["meta", { name: "theme-color", content: "#3c4858" }],
  ],
  themeConfig: {
    logo: "/nav-logo.png",
    search: {
      provider: "local",
    },
    editLink: {
      pattern: "https://github.com/tuist/tuist/edit/main/once/docs/:path",
      text: "Edit this page on GitHub",
    },
    nav: site.nav,
    sidebar: site.sidebar,
    socialLinks: [{ icon: "github", link: "https://github.com/tuist/tuist/tree/main/once" }],
    footer: site.footer,
  },
});
