const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');
const yaml = require('js-yaml');

const workflow = yaml.load(readFileSync(join(__dirname, '../workflows/tuist-project-tests.yml'), 'utf8'));
const script = workflow.jobs['acceptance-scope'].steps.find(step => step.id === 'scope').with.script;
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const decide = new AsyncFunction('github', 'context', 'core', script);

async function required(files, options = {}) {
  const outputs = {};
  await decide({
    paginate: async () => {
      if (options.unreadable) throw new Error('File list unavailable');
      return files;
    },
    rest: { pulls: {
      listFiles: {},
      get: async () => ({ data: {
        head: { sha: options.head ?? 'head' },
        base: { sha: options.base ?? 'base' },
        changed_files: options.count ?? files.length,
      } }),
    } },
  }, {
    eventName: options.event ?? 'pull_request',
    repo: { owner: 'tuist', repo: 'tuist' },
    payload: { pull_request: {
      number: 123,
      head: { sha: 'head' },
      base: { sha: 'base' },
    } },
  }, {
    setOutput: (name, value) => { outputs[name] = value; },
    warning: () => {},
  });
  return outputs.required;
}

const translations = [
  { filename: '.glossia/app/Resources/TuistApp/en.lproj/Localizable.strings/ja.lock' },
  { filename: 'app/Resources/TuistApp/ja.lproj/Localizable.strings' },
  { filename: 'app/Resources/TuistApp/zh-Hant.lproj/Localizable.stringsdict' },
  { filename: 'server/priv/gettext/ja/LC_MESSAGES/dashboard.po' },
  { filename: 'server/priv/docs/ja/guides/features/cache.md' },
  { filename: 'android/app/src/main/res/values-zh-rTW/strings.xml' },
];

test('a complete translation-only PR skips CLI acceptance, including large paginated diffs', async () => {
  assert.equal(await required(translations), 'false');
  assert.equal(await required(Array.from({ length: 1204 }, (_, i) => translations[i % translations.length])), 'false');
  assert.equal(await required([{ filename: translations[1].filename, previous_filename: translations[2].filename }]), 'false');
});

test('translations mixed with source, configuration or English inputs still require acceptance', async () => {
  for (const filename of [
    'cli/Sources/TuistKit/Services/GenerateService.swift',
    'cli/Tests/TuistKitTests/GenerateTests.swift',
    'cli/Tests/Fixtures/app/en.lproj/Localizable.strings',
    'app/Sources/TuistApp/App.swift',
    'app/Resources/TuistApp/en.lproj/Localizable.strings',
    'server/priv/gettext/en/LC_MESSAGES/dashboard.po',
    'server/priv/docs/en/guides/features/cache.md',
    'android/app/src/main/res/values/strings.xml',
    '.glossia/config.json',
    'Tuist.swift',
    'Package.resolved',
    'mise.toml',
    'cas-plugin/src/lib.rs',
    '.github/workflows/tuist-project-tests.yml',
  ]) {
    assert.equal(await required([...translations, { filename }]), 'true', filename);
  }
});

test('renaming source into a translation path cannot hide a source change', async () => {
  assert.equal(await required([{
    filename: translations[0].filename,
    previous_filename: 'cli/Sources/TuistKit/Services/GenerateService.swift',
  }]), 'true');
});

test('missing, truncated or outdated PR evidence requires acceptance', async () => {
  assert.equal(await required([], {}), 'true');
  assert.equal(await required(translations, { unreadable: true }), 'true');
  assert.equal(await required(translations, { count: 3001 }), 'true');
  assert.equal(await required(translations, { head: 'new-head' }), 'true');
  assert.equal(await required(translations, { base: 'new-base' }), 'true');
});

test('main always retains full acceptance coverage for translation changes', async () => {
  assert.equal(await required(translations, { event: 'push' }), 'true');
});
