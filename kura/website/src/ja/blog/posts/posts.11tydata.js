function stripDatePrefix(fileSlug) {
  return fileSlug.replace(/^\d{4}-\d{2}-\d{2}-/, "");
}

export default {
  layout: "post.njk",
  tags: ["posts"],
  eleventyComputed: {
    permalink: (data) => `/ja/blog/${stripDatePrefix(data.page.fileSlug)}/`,
    socialImage: (data) => `/assets/social/${stripDatePrefix(data.page.fileSlug)}-ja.png`,
    socialImageAlt: (data) => `${data.title} · Kura`,
  },
};

