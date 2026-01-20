import * as path from "node:path";
import fg from "fast-glob";
import fs from "node:fs";

const glob = path.join(
  import.meta.dirname,
  "../../../examples/xcode/*/README.md",
);

export async function loadData(files) {
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
      content: content,
      url: `https://github.com/tuist/tuist/tree/main/examples/xcode/${path.basename(
        path.dirname(file),
      )}`,
    };
  });
}

export async function paths() {
  return (await loadData()).map((item) => {
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
}
