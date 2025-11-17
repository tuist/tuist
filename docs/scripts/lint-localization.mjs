#!/usr/bin/env node

import * as path from "node:path";
import * as fs from "node:fs/promises";
import fg from "fast-glob";

const docsDirectory = path.join(import.meta.dirname, "..", "docs");

/**
 * Checks if a VitePress container block has proper HTML comments for translation segmentation.
 *
 * VitePress containers like ::: warning, ::: info, etc. should have HTML comments after the
 * opening tag and before the closing tag to ensure proper translation segmentation:
 *
 * Correct:
 * ::: warning TITLE
 * <!-- -->
 * Content here
 * <!-- -->
 * :::
 *
 * Incorrect:
 * ::: warning TITLE
 * Content here
 * :::
 */
async function checkVitePressBlocks() {
  console.log("Checking VitePress blocks for HTML comments...\n");

  const files = await fg("en/**/*.md", {
    cwd: docsDirectory,
    absolute: true,
    ignore: ["**/node_modules/**", "**/.vitepress/**"],
  });

  let hasErrors = false;
  let totalBlocks = 0;
  let blocksWithIssues = 0;

  for (const file of files) {
    const content = await fs.readFile(file, "utf-8");
    const lines = content.split("\n");
    const relativePath = path.relative(docsDirectory, file);

    const blockPattern = /^:::\s+(warning|info|tip|danger|note)/i;
    let inBlock = false;
    let blockStartLine = 0;
    let blockType = "";
    let blockTitle = "";
    let blockContent = [];

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const lineNumber = i + 1;

      if (!inBlock && blockPattern.test(line)) {
        // Start of a VitePress block
        inBlock = true;
        blockStartLine = lineNumber;
        const match = line.match(blockPattern);
        blockType = match[1];
        blockTitle = line.substring(match[0].length).trim();
        blockContent = [];
        totalBlocks++;
      } else if (inBlock && line.trim() === ":::") {
        // End of a VitePress block
        inBlock = false;

        // Check if the block has proper HTML comments
        const hasOpeningComment =
          blockContent.length > 0 &&
          blockContent[0].trim().match(/^<!--\s*-->$/);
        const hasClosingComment =
          blockContent.length > 0 &&
          blockContent[blockContent.length - 1].trim().match(/^<!--\s*-->$/);

        if (!hasOpeningComment || !hasClosingComment) {
          hasErrors = true;
          blocksWithIssues++;

          console.log(
            `❌ ${relativePath}:${blockStartLine} - Missing HTML comments`,
          );
          console.log(`   Block type: ${blockType}${blockTitle ? " " + blockTitle : ""}`);

          if (!hasOpeningComment) {
            console.log("   Missing opening comment after block declaration");
          }
          if (!hasClosingComment) {
            console.log("   Missing closing comment before :::");
          }

          console.log("");
        }
      } else if (inBlock) {
        // Inside a block, collect content
        blockContent.push(line);
      }
    }
  }

  console.log(`\n${"=".repeat(80)}`);
  console.log(`Total VitePress blocks found: ${totalBlocks}`);
  console.log(`Blocks with issues: ${blocksWithIssues}`);
  console.log(`Blocks correctly formatted: ${totalBlocks - blocksWithIssues}`);
  console.log(`${"=".repeat(80)}\n`);

  if (hasErrors) {
    console.error(
      "❌ Some VitePress blocks are missing HTML comments for proper translation segmentation.",
    );
    console.error("\nTo fix, ensure blocks follow this pattern:");
    console.error("::: warning TITLE");
    console.error("<!-- -->");
    console.error("Content here");
    console.error("<!-- -->");
    console.error(":::");
    process.exit(1);
  } else {
    console.log(
      "✅ All VitePress blocks have proper HTML comments for translation segmentation.",
    );
  }
}

checkVitePressBlocks().catch((error) => {
  console.error("Error:", error);
  process.exit(1);
});
