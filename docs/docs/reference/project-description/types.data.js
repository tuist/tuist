import * as path from "node:path";
import fg from "fast-glob";
import fs from "node:fs";

export default {
  load() {
    const generatedDirectory = path.join(
      import.meta.dirname,
      "../../../generated"
    );
    const files = fg
      .sync("**/*.md", {
        cwd: generatedDirectory,
        absolute: true,
        ignore: ["**/README.md"],
      })
      .sort();
    return files.map((file) => {
      return {
        title: path.basename(file).replace(".md", ""),
        name: path.basename(file).replace(".md", "").toLowerCase(),
        description: "",
        content: fs.readFileSync(file, "utf-8"),
      };
    });
  },
};
