import * as path from "node:path";
import fg from "fast-glob";
import fs from "node:fs";

export default {
  load() {
    const fixturesDirectory = path.join(
      import.meta.dirname,
      "../../../../fixtures"
    );
    const files = fg
      .sync("*/README.md", {
        cwd: fixturesDirectory,
        absolute: true,
      })
      .sort();
    return files.map((file) => {
      return {
        title: path.basename(path.dirname(file)),
        name: path.basename(path.dirname(file)).toLowerCase(),
        description: "",
        content: fs.readFileSync(file, "utf-8"),
      };
    });
  },
};
