import * as path from 'node:path';
import * as fs from 'node:fs/promises';
import { glob } from 'fast-glob';

const VALID_KEYWORDS = ['NOTE', 'TIP', 'IMPORTANT', 'WARNING', 'CAUTION'];

export async function validateAdmonitions(outDir) {
  const docsDir = path.join(path.dirname(outDir), 'docs');
  const files = await glob('**/*.md', { cwd: docsDir });

  let hasErrors = false;
  const errors = [];

  for (const file of files) {
    const filePath = path.join(docsDir, file);
    const content = await fs.readFile(filePath, 'utf-8');
    const lines = content.split('\n');

    lines.forEach((line, index) => {
      const match = line.match(/^>\s*\[!([^\]]+)\]/);
      if (match) {
        const keyword = match[1];
        const keywordOnly = keyword.split(/[\s\\]/)[0];

        if (!VALID_KEYWORDS.includes(keywordOnly)) {
          hasErrors = true;
          errors.push({
            file: `docs/${file}`,
            line: index + 1,
            keyword: keyword,
            content: line.trim()
          });
        }
      }
    });
  }

  if (hasErrors) {
    console.error('\n❌ Invalid admonition syntax found:\n');
    console.error(`Valid keywords are: ${VALID_KEYWORDS.join(', ')}\n`);

    errors.forEach(error => {
      console.error(`${error.file}:${error.line}`);
      console.error(`  Invalid keyword: [!${error.keyword}]`);
      console.error(`  Found: ${error.content}`);
      console.error('');
    });

    console.error(`\nTotal errors: ${errors.length}`);
    console.error('\nAdmonitions must use the syntax: > [!KEYWORD] where KEYWORD is one of:');
    console.error(`  ${VALID_KEYWORDS.join(', ')}\n`);

    throw new Error('Invalid admonition syntax detected');
  }
}
