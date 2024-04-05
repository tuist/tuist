import * as path from "node:path";
import fg from "fast-glob";
import fs from "node:fs";

const glob = path.join(import.meta.dirname, "../../../../fixtures/*/README.md");

export default {
  watch: [glob],
  load(files) {
    if (!files) {
      files = fg
        .sync(glob, {
          absolute: true,
        })
        .sort();
    }
    return files.map((file) => {
      const content = fs.readFileSync(file, "utf-8");
      const titleRegex = /^#\s*(.+)/m;
      const titleMatch = content.match(titleRegex);
      return {
        title: titleMatch[1],
        name: path.basename(path.dirname(file)).toLowerCase(),
        description: "foo",
        content: content,
        url: `https://github.com/tuist/tuist/tree/main/fixtures/${path.basename(
          path.dirname(file)
        )}`,
      };
    });
  },
};
