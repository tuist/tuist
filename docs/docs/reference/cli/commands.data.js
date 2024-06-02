import * as path from "node:path";
import fg from "fast-glob";
import fs from "node:fs";

export default {
  load() {
    const generatedDirectory = path.join(
      import.meta.dirname,
      "../../../docs/generated/cli"
    );
    const files = fg
      .sync("**/*.md", {
        cwd: generatedDirectory,
        absolute: true
      })

    const validCategories = ["cloud", "plugin", "migration", "tuist"];

    return files.map((file) => {
      const fileName = path.basename(file, ".md");
      const content = fs.readFileSync(file, "utf-8");

      const category = path.relative(generatedDirectory, file).split(path.sep)[0];
      const finalCategory = validCategories.includes(category) ? category : "tuist";

      let titleParts = fileName.split(".");
      let title = titleParts
      .filter(part => !validCategories.includes(part))
      .join(" ");


      return {
        identifier: fileName,
        title: title,
        content: content,
        category: finalCategory,
      };
    })
  },
};
