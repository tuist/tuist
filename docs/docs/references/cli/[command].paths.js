import cliDataLoader from "./commands.data";

export default {
  paths() {
    return cliDataLoader.load().map((item) => {
        return {
            params: { command: item.command, title: item.title, description: item.description },
            content: item.content
        }
    })
  },
};
