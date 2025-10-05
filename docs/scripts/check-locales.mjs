#!/usr/bin/env node

import * as path from 'node:path';
import * as fs from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import fastGlob from 'fast-glob';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const LOCALES = ['en', 'ar', 'es', 'ja', 'ko', 'pt', 'ru', 'zh'];
const BASE_LOCALE = 'en';

async function checkLocales() {
  const docsDir = path.join(__dirname, '..', 'docs');

  // Get all English markdown files
  const baseLocalePath = path.join(docsDir, BASE_LOCALE);
  const baseFiles = await fastGlob('**/*.md', { cwd: baseLocalePath });

  console.log(`📚 Checking ${baseFiles.length} pages across ${LOCALES.length - 1} locales...\n`);

  // Process all locales in parallel
  const results = await Promise.all(
    LOCALES.filter(locale => locale !== BASE_LOCALE).map(async (locale) => {
      const localePath = path.join(docsDir, locale);

      // Check all files in parallel for this locale
      const checks = await Promise.all(
        baseFiles.map(async (relativeFile) => {
          const localeFilePath = path.join(localePath, relativeFile);

          try {
            await fs.access(localeFilePath);
            return null; // File exists
          } catch {
            return relativeFile; // File is missing
          }
        })
      );

      const missing = checks.filter(f => f !== null);

      return { locale, missing };
    })
  );

  // Collect all missing files
  const missingFiles = [];
  results.forEach(({ locale, missing }) => {
    missing.forEach(file => {
      missingFiles.push({ locale, file });
    });
  });

  if (missingFiles.length === 0) {
    console.log('✅ All locales are in sync!');
    return;
  }

  console.error('\n❌ Missing pages found in locales:\n');

  const byLocale = {};
  missingFiles.forEach(({ locale, file }) => {
    if (!byLocale[locale]) byLocale[locale] = [];
    byLocale[locale].push(file);
  });

  Object.entries(byLocale).forEach(([locale, files]) => {
    console.error(`  ${locale}: ${files.length} missing file(s)`);
    files.forEach(file => console.error(`    - ${file}`));
  });

  console.error(`\nTotal missing files: ${missingFiles.length}`);
  console.error('\nAll locales must have the same pages as English (en).\n');

  process.exit(1);
}

checkLocales().catch(error => {
  console.error('Error checking locales:', error);
  process.exit(1);
});
