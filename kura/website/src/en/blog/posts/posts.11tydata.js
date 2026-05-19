function stripDatePrefix(fileSlug) {
  return fileSlug.replace(/^\d{4}-\d{2}-\d{2}-/, "");
}

export default {
  layout: "post.njk",
  tags: ["posts"],
  eleventyComputed: {
    permalink: (data) => `/blog/${stripDatePrefix(data.page.fileSlug)}/`,
    socialImage: (data) => `/assets/social/${stripDatePrefix(data.page.fileSlug)}-en.png`,
    socialImageAlt: (data) => `${data.title} · Kura`,
  },
};

