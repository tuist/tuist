export default class {
  data() {
    return {
      pagination: { data: "agentDocs", size: 1, alias: "doc" },
      permalink: (data) => data.doc.mdUrl,
      eleventyExcludeFromCollections: true,
    };
  }

  render({ doc }) {
    return doc.markdown;
  }
}
