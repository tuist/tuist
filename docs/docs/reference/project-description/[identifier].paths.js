import typesDataLoader from "./types.data";

export default {
  paths() {
    return typesDataLoader.load().map((item) => {
        return {
            params: { type: item.name, title: item.title, description: item.description, identifier: item.identifier },
            content: item.content
        }
    })
  },
};
