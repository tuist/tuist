import * as path from "node:path";
import * as fs from "node:fs/promises";
import fastGlob from "fast-glob";

export async function validateLocalizedLinks(outDir) {
  // outDir is .vitepress/dist, we need to go up two levels to get to the project root
  // then into docs/ which is the srcDir
  const projectRoot = path.dirname(path.dirname(outDir));
  const docsDir = path.join(projectRoot, "docs");
  const enDir = path.join(docsDir, "en");

  // Only validate English files - translations are managed separately
  const enFiles = await fastGlob("**/*.md", { cwd: enDir });

  const validPaths = buildValidPaths(enFiles);

  const errors = [];

  for (const file of enFiles) {
    const filePath = path.join(enDir, file);
    const content = await fs.readFile(filePath, "utf-8");

    const linkErrors = validateFileLinks(content, `en/${file}`, validPaths);
    errors.push(...linkErrors);
  }

  if (errors.length > 0) {
    console.error("\n❌ Invalid LocalizedLink hrefs found:\n");

    errors.forEach((error) => {
      console.error(`docs/${error.file}:${error.line}`);
      console.error(`  ${error.message}`);
      if (error.suggestion) {
        console.error(`  Suggestion: ${error.suggestion}`);
      }
      console.error("");
    });

    console.error(`Total errors: ${errors.length}\n`);

    throw new Error("Invalid LocalizedLink hrefs detected");
  }
}

function buildValidPaths(enFiles) {
  const paths = new Set();

  for (const file of enFiles) {
    let urlPath = "/" + file.replace(/\.md$/, "");

    if (urlPath.endsWith("/index")) {
      urlPath = urlPath.slice(0, -6);
    }

    paths.add(urlPath);

    if (file.includes("[")) {
      const dynamicPattern = urlPath.replace(/\[([^\]]+)\]/g, "[*]");
      paths.add(dynamicPattern);
    }
  }

  paths.add("/");

  return paths;
}

function validateFileLinks(content, file, validPaths) {
  const errors = [];
  const lines = content.split("\n");

  const localizedLinkRegex =
    /<LocalizedLink\s+(?:href|to)=["']([^"']+)["'][^>]*>/g;

  lines.forEach((line, index) => {
    let match;
    localizedLinkRegex.lastIndex = 0;

    while ((match = localizedLinkRegex.exec(line)) !== null) {
      const href = match[1];
      const lineNumber = index + 1;

      if (href.startsWith("http://") || href.startsWith("https://")) {
        continue;
      }

      if (!href.startsWith("/")) {
        errors.push({
          file,
          line: lineNumber,
          href,
          message: `LocalizedLink href must start with '/': "${href}"`,
        });
        continue;
      }

      const pathWithoutHash = href.split("#")[0];
      const pathWithoutQuery = pathWithoutHash.split("?")[0];

      // Warn about .html extensions - VitePress uses clean URLs
      if (pathWithoutQuery.endsWith(".html")) {
        errors.push({
          file,
          line: lineNumber,
          href,
          message: `LocalizedLink href contains .html extension (VitePress uses clean URLs): "${href}"`,
          suggestion: href.replace(".html", ""),
        });
        continue;
      }

      if (!isValidPath(pathWithoutQuery, validPaths)) {
        const suggestion = findSimilarPath(pathWithoutQuery, validPaths);
        errors.push({
          file,
          line: lineNumber,
          href,
          message: `LocalizedLink href points to non-existent page: "${href}"`,
          suggestion,
        });
      }
    }
  });

  return errors;
}

function isValidPath(href, validPaths) {
  if (validPaths.has(href)) {
    return true;
  }

  // Check against dynamic route patterns
  for (const validPath of validPaths) {
    if (validPath.includes("[*]")) {
      // Replace [*] with a placeholder before escaping regex special chars
      const placeholder = "___DYNAMIC___";
      const withPlaceholder = validPath.replace(/\[\*\]/g, placeholder);
      const escaped = withPlaceholder.replace(/[.+?^${}()|[\]\\]/g, "\\$&");

      // Build regex that matches a single path segment for [*]
      // For /cli/[*], this should match /cli/share, /cli/organization, etc.
      const singleSegmentPattern = escaped.replace(
        new RegExp(placeholder, "g"),
        "[^/]+",
      );
      const singleRegex = new RegExp(`^${singleSegmentPattern}$`);
      if (singleRegex.test(href)) {
        return true;
      }

      // Also match deeper paths for dynamic routes
      // e.g., /references/project-description/[*] should match /references/project-description/structs/project
      const multiSegmentPattern = escaped.replace(
        new RegExp(placeholder, "g"),
        ".+",
      );
      const multiRegex = new RegExp(`^${multiSegmentPattern}$`);
      if (multiRegex.test(href)) {
        return true;
      }
    }
  }

  return false;
}

function findSimilarPath(href, validPaths) {
  const hrefParts = href.split("/").filter(Boolean);
  let bestMatch = null;
  let bestScore = 0;

  for (const validPath of validPaths) {
    if (validPath.includes("[*]")) continue;

    const validParts = validPath.split("/").filter(Boolean);

    let score = 0;
    const minLen = Math.min(hrefParts.length, validParts.length);
    for (let i = 0; i < minLen; i++) {
      if (hrefParts[i] === validParts[i]) {
        score++;
      }
    }

    if (hrefParts.length > 0 && validParts.length > 0) {
      const lastHref = hrefParts[hrefParts.length - 1];
      const lastValid = validParts[validParts.length - 1];
      if (
        lastHref === lastValid ||
        lastHref.includes(lastValid) ||
        lastValid.includes(lastHref)
      ) {
        score += 2;
      }
    }

    if (score > bestScore) {
      bestScore = score;
      bestMatch = validPath;
    }
  }

  return bestScore > 0 ? bestMatch : null;
}
