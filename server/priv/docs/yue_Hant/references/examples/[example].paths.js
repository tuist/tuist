import { paths } from "./../../../../.vitepress/data/examples";

export default {
  async paths() {
    const examplePaths = await paths("yue_Hant");
    return examplePaths;
  },
};
