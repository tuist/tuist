import * as path from "node:path";
import * as fs from "node:fs/promises";
import fastGlob from "fast-glob";

const LOCALES = ["en", "ar", "es", "ja", "ko", "pt", "ru", "zh_Hans", "pl"];
const BASE_LOCALE = "en";

export async function checkLocalePages(outDir) {
  const docsDir = path.join(path.dirname(outDir), "docs");

  // Get all English markdown files
  const baseLocalePath = path.join(docsDir, BASE_LOCALE);
  const baseFiles = await fastGlob("**/*.md", { cwd: baseLocalePath });

  // Process all locales in parallel
  const results = await Promise.all(
    LOCALES.filter((locale) => locale !== BASE_LOCALE).map(async (locale) => {
      const localePath = path.join(docsDir, locale);

      // Ensure locale directory exists
      await fs.mkdir(localePath, { recursive: true });

      // Check all files in parallel for this locale
      const missingFiles = await Promise.all(
        baseFiles.map(async (relativeFile) => {
          const localeFilePath = path.join(localePath, relativeFile);

          try {
            await fs.access(localeFilePath);
            return null; // File exists
          } catch {
            return relativeFile; // File is missing
          }
        }),
      );

      return {
        locale,
        missing: missingFiles.filter((f) => f !== null),
      };
    }),
  );

  // Collect all missing files
  const missingFiles = [];
  results.forEach(({ locale, missing }) => {
    missing.forEach((file) => {
      missingFiles.push({ locale, file });
    });
  });

  if (missingFiles.length > 0) {
    console.error("\n❌ Missing pages found in locales:\n");

    const byLocale = {};
    missingFiles.forEach(({ locale, file }) => {
      if (!byLocale[locale]) byLocale[locale] = [];
      byLocale[locale].push(file);
    });

    Object.entries(byLocale).forEach(([locale, files]) => {
      console.error(`  ${locale}: ${files.length} missing file(s)`);
      files.forEach((file) => console.error(`    - ${file}`));
    });

    console.error(`\nTotal missing files: ${missingFiles.length}`);
    console.error("\nAll locales must have the same pages as English (en).\n");

    throw new Error("Missing pages detected in locales");
  }
}
