import * as path from 'node:path';
import * as fs from 'node:fs/promises';
import fastGlob from 'fast-glob';

const VALID_KEYWORDS = ['info', 'tip', 'warning', 'danger', 'details'];

export async function validateAdmonitions(outDir) {
  const docsDir = path.join(path.dirname(outDir), 'docs');
  const files = await fastGlob('**/*.md', { cwd: docsDir });

  let hasErrors = false;
  const errors = [];

  for (const file of files) {
    const filePath = path.join(docsDir, file);
    const content = await fs.readFile(filePath, 'utf-8');
    const lines = content.split('\n');

    lines.forEach((line, index) => {
      // Check for old GitHub-style admonitions
      const oldStyleMatch = line.match(/^>\s*\[!([^\]]+)\]/);
      if (oldStyleMatch) {
        hasErrors = true;
        errors.push({
          file: `docs/${file}`,
          line: index + 1,
          type: 'old-syntax',
          content: line.trim(),
          message: 'Found GitHub-style admonition. Please use VitePress syntax instead: ::: keyword'
        });
      }

      // Check for VitePress admonitions with invalid keywords
      const vitepressMatch = line.match(/^:::\s+([a-z]+)/);
      if (vitepressMatch) {
        const keyword = vitepressMatch[1];
        if (!VALID_KEYWORDS.includes(keyword)) {
          hasErrors = true;
          errors.push({
            file: `docs/${file}`,
            line: index + 1,
            type: 'invalid-keyword',
            keyword: keyword,
            content: line.trim(),
            message: `Invalid keyword: "${keyword}". Must be one of: ${VALID_KEYWORDS.join(', ')}`
          });
        }
      }
    });
  }

  if (hasErrors) {
    console.error('\n❌ Invalid admonition syntax found:\n');
    console.error(`Valid VitePress admonition keywords are: ${VALID_KEYWORDS.join(', ')}\n`);

    errors.forEach(error => {
      console.error(`${error.file}:${error.line}`);
      console.error(`  ${error.message}`);
      console.error(`  Found: ${error.content}`);
      console.error('');
    });

    console.error(`\nTotal errors: ${errors.length}`);
    console.error('\nAdmonitions must use VitePress syntax: ::: keyword');
    console.error('Example:');
    console.error('  ::: danger STOP');
    console.error('  Danger zone, do not proceed');
    console.error('  :::');
    console.error('');
    console.error('  ::: details Click me to view the code');
    console.error('  ```js');
    console.error('  console.log("Hello, VitePress!")');
    console.error('  ```');
    console.error('  :::\n');

    throw new Error('Invalid admonition syntax detected');
  }
}
