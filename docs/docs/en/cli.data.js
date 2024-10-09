import { loadData } from "../../.vitepress/data/cli";

export default {
  async load() {
    return await loadData("en");
  },
};
