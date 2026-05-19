import rssPlugin from "@11ty/eleventy-plugin-rss";

import { generateSocialImages } from "./scripts/generate-social-images.mjs";

export default function (eleventyConfig) {
  eleventyConfig.addPlugin(rssPlugin);

  eleventyConfig.addPassthroughCopy({ "src/public": "/" });
  eleventyConfig.addPassthroughCopy({ "src/assets": "assets" });

  eleventyConfig.addWatchTarget("./src/assets/");
  eleventyConfig.addWatchTarget("./src/en/blog/posts/");
  eleventyConfig.addWatchTarget("./src/ja/blog/posts/");

  eleventyConfig.on("eleventy.before", async () => {
    await generateSocialImages();
  });

  eleventyConfig.addCollection("posts", (collections) =>
    collections
      .getFilteredByGlob("./src/{en,ja}/blog/posts/*.{md,njk}")
      .sort((a, b) => b.date - a.date),
  );

  eleventyConfig.addFilter("readableDate", (value, localeTag = "en-US") => {
    const date = value instanceof Date ? value : new Date(value);

    return date.toLocaleDateString(localeTag, {
      year: "numeric",
      month: "long",
      day: "numeric",
      timeZone: "UTC",
    });
  });

  eleventyConfig.addFilter("htmlDateString", (value) => {
    const date = value instanceof Date ? value : new Date(value);
    return date.toISOString().slice(0, 10);
  });

  eleventyConfig.addFilter(
    "filterByLocale",
    (items, localeCode) => (items || []).filter((item) => item.data?.locale?.code === localeCode),
  );

  eleventyConfig.addFilter("toAbsoluteUrl", (value, siteUrl) => {
    if (!value) return value;
    if (/^https?:\/\//.test(value)) return value;
    return new URL(value, siteUrl).toString();
  });

  return {
    dir: {
      input: "src",
      includes: "_includes",
      layouts: "_includes/layouts",
      data: "_data",
      output: "_site",
    },
    templateFormats: ["njk", "md", "html", "11ty.js"],
    markdownTemplateEngine: "njk",
    htmlTemplateEngine: "njk",
  };
}

