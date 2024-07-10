import * as path from "node:path";
import fg from "fast-glob";
import fs from "node:fs";

export default {
  load() {
    const generatedDirectory = path.join(
      import.meta.dirname,
      "../../../docs/generated/manifest"
    );
    const files = fg
      .sync("**/*.md", {
        cwd: generatedDirectory,
        absolute: true,
        ignore: ["**/README.md"],
      })
      .sort();
    return files.map((file) => {
      const category = path.basename(path.dirname(file))
      const fileName = path.basename(file).replace(".md", "")
      return {
        category: category,
        title: fileName,
        name: fileName.toLowerCase(),
        identifier: category + "/" + fileName.toLowerCase(),
        description: "",
        content: fs.readFileSync(file, "utf-8"),
      };
    });
  },
};
