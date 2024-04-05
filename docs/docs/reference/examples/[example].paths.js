import examplesDataLoader from "./examples.data";

export default {
  paths() {
    return examplesDataLoader.load().map((item) => {
      return {
        params: {
          example: item.name,
          title: item.title,
          description: item.description,
          url: item.url,
        },
        content: item.content,
      };
    });
  },
};
