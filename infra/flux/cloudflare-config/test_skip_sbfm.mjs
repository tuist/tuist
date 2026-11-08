import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const field = 'http.request.uri.path';
const locales = ['ar', 'en', 'es', 'ja', 'ka', 'ko', 'ru', 'tr', 'yue_Hant', 'zh_Hans', 'zh_Hant'];
const methods = ['GET', 'HEAD'];
const writes = ['POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'];

function expression(name, key = 'expression') {
  const content = readFileSync(new URL(name, import.meta.url), 'utf8');
  const match = content.match(new RegExp(`^( +)${key}: \\|-\\n((?:\\1  [^\\n]*\\n?)+)`, 'm'));
  assert.ok(match, `${name}: ${key}`);
  return match[2].trim();
}

const apiRule = expression('skip-sbfm-api-paths.yaml');
const marketingRule = expression('skip-sbfm-marketing-pages.yaml');

// Evaluate the actual expression, splitting only on top-level boolean operators.
function evaluate(source, request) {
  source = source.trim();
  for (const operator of ['or', 'and']) {
    let depth = 0;
    let start = 0;
    const parts = [];
    for (const token of source.matchAll(/"[^"]*"|\(|\)|\b(?:and|or)\b/g)) {
      if (token[0] === '(') depth++;
      else if (token[0] === ')') depth--;
      else if (token[0] === operator && depth === 0) {
        parts.push(source.slice(start, token.index));
        start = token.index + token[0].length;
      }
    }
    if (parts.length) {
      parts.push(source.slice(start));
      const values = parts.map((part) => evaluate(part, request));
      return operator === 'or' ? values.some(Boolean) : values.every(Boolean);
    }
  }
  if (source.startsWith('(') && source.endsWith(')')) return evaluate(source.slice(1, -1), request);
  if (source.startsWith('not ')) return !evaluate(source.slice(4), request);
  if (source === 'cf.client.bot') return request[source];
  if (source === 'http.response.headers["x-tuist-public"][0] eq "1"') return request.publicHeader === '1';

  let match;
  if ((match = source.match(/^http\.request\.uri\.path matches r"([^"]+)"$/))) {
    return new RegExp(match[1]).test(request[field]);
  }
  if ((match = source.match(/^(http\.[\w.]+) in \{(.*?)\}$/s))) {
    assert.ok(Object.hasOwn(request, match[1]));
    return [...match[2].matchAll(/"([^"]+)"/g)].some((item) => item[1] === request[match[1]]);
  }
  if ((match = source.match(/^(http\.[\w.]+) (eq|ne) "([^"]+)"$/))) {
    assert.ok(Object.hasOwn(request, match[1]));
    return (request[match[1]] === match[3]) === (match[2] === 'eq');
  }
  if ((match = source.match(/^http\.request\.uri\.path wildcard "([^"]+)"$/))) {
    // Cloudflare wildcards match entire paths, slashes included, case-insensitively.
    const pattern = match[1].split('*').map((part) => part.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('.*');
    return new RegExp(`^${pattern}$`, 'i').test(request[field]);
  }
  if ((match = source.match(/^(starts_with|ends_with)\(http\.request\.uri\.path, "([^"]+)"\)$/))) {
    return match[1] === 'starts_with' ? request[field].startsWith(match[2]) : request[field].endsWith(match[2]);
  }
  if ((match = source.match(/^http\.request\.uri\.path contains "([^"]+)"$/))) {
    return request[field].includes(match[1]);
  }
  throw new Error(`Unrecognized condition: ${source}`);
}

function exempt(rule, path, method = 'GET', host = 'tuist.dev') {
  return evaluate(rule, { [field]: path, 'http.request.method': method, 'http.host': host });
}

function either(path, method = 'GET') {
  return exempt(apiRule, path, method) || exempt(marketingRule, path, method);
}

function checkPaths(paths, predicate, expected, requestMethods = ['GET']) {
  for (const path of paths) for (const method of requestMethods) {
    assert.equal(predicate(path, method), expected, `${method} ${path}`);
  }
}

test('canonical project roots', () => {
  checkPaths(['/tuist/tuist', '/tuist/ios_app_with_frameworks', '/my-org/my_project'], (p, m) => exempt(apiRule, p, m), true, methods);
});

test('public documentation and Markdown', () => {
  const paths = ['/docs', '/docs/en/guides/install-tuist', '/marketing-markdown', '/marketing-markdown/',
    '/marketing-markdown/cache', '/marketing-markdown/compare/github-actions', '/marketing-markdown/source/openness',
    '/robots.txt', '/llms.txt', '/llms-full.txt', '/sitemap.xml', '/geofeed.csv'];
  for (const locale of locales) for (const section of ['docs', 'docs-markdown']) {
    paths.push(`/${locale}/${section}`, `/${locale}/${section}/`,
      `/${locale}/${section}/guides/install-tuist`, `/${locale}/${section}/references/docs/example`);
  }
  checkPaths(paths, (p, m) => exempt(apiRule, p, m), true, methods);
});

test('content prefixes do not exempt project dashboards', () => {
  checkPaths(['/tuist/docs/builds', '/tuist/docs-markdown/tests', '/tuist/en/docs/builds',
    '/en/tuist/docs/guides/install-tuist', '/en/docs-private/builds', '/en/docs-markdown-private/tests',
    '/marketing-markdown-private/compare/provider', '/docs-private/en/guides/install-tuist'], (p, m) => exempt(apiRule, p, m), false);
});

test('deeper dashboards and empty segments remain protected', () => {
  checkPaths(['/tuist/tuist/analytics', '/tuist/tuist/builds', '/tuist/tuist/tests', '/tuist/tuist/module-cache',
    '/tuist/tuist/tests/test-runs', '/tuist/tuist/', '/tuist/', '//tuist', '//', '/tuist//tuist', '/tuist'], (p, m) => exempt(apiRule, p, m), false);
});

test('sockets, authentication, operator and scanner paths remain protected', () => {
  checkPaths(['/live/websocket', '/live/longpoll', '/socket/websocket', '/users/log_in', '/users/register',
    '/auth/callback', '/ops/og-gallery', '/.git/config', '/wp-admin/install.php', '/tuist/tuist%2Fbuilds'], (p, m) => exempt(apiRule, p, m), false);
});

test('native jams and legacy threads socket handshakes alone are exempt', () => {
  for (const collection of ['jams', 'threads']) {
    assert.equal(exempt(apiRule, `/${collection}/socket/websocket`), true);
    checkPaths([`/${collection}/socket/websocket`], (p, m) => exempt(apiRule, p, m), false, ['HEAD', ...writes]);
    checkPaths([`/${collection}/socket/longpoll`, `/${collection}/socket/websocket/`, `/${collection}/socket/websocket/extra`, `/${collection}/socket/private`], (p, m) => exempt(apiRule, p, m), false);
  }
});

test('non-read methods remain protected', () => {
  checkPaths(['/tuist/tuist', '/en/docs', '/en/docs/guides/install-tuist', '/en/docs-markdown/guides/install-tuist',
    '/marketing-markdown', '/marketing-markdown/cache', '/llms.txt'], (p, m) => exempt(apiRule, p, m), false, writes);
});

test('existing machine paths remain exempt', () => {
  for (const [path, method] of [['/api/auth/oidc/token', 'POST'], ['/webhooks/github', 'POST'], ['/mcp', 'POST'],
    ['/oauth2/token', 'POST'], ['/scim/v2/Users', 'PATCH'], ['/agent/auth/claim', 'POST'],
    ['/open-graph-images/signed-key', 'GET'], ['/tuist/tuist/previews/example/app.ipa', 'GET']]) {
    assert.equal(exempt(apiRule, path, method), true, `${method} ${path}`);
  }
  assert.equal(exempt(apiRule, '/search', 'POST', 'search.tuist.dev'), true);
});

test('marketing route shapes across locales and guide roots', () => {
  const pages = ['/blog', '/blog/2026/09/09/bazel', '/blog/2026/09/09/bazel/iframe.html',
    '/changelog', '/changelog/2026.09.05-bazel-build-insights', '/customers', '/cache', '/previews', '/pricing',
    '/compute', '/tests', '/about', '/brand', '/download', '/newsletter', '/newsletter/issues/12', '/privacy',
    '/data-processing-addendum', '/trademark-guidelines'];
  checkPaths([...pages, '/', '/customers/acme', '/blog/rss.xml', '/blog/atom.xml',
    '/changelog/rss.xml', '/changelog/atom.xml', '/rss.xml',
    '/case-studies', '/case-studies/acme', '/flaky-tests', '/test-insights',
    '/compare', '/compare/github-actions', '/solutions/slow-builds',
    '/build-systems', '/build-systems/bazel'], either, true, methods);
  for (const locale of locales.filter((value) => value !== 'en')) {
    checkPaths([`/${locale}`, ...pages.map((path) => `/${locale}${path}`),
      `/${locale}/customers/acme`], either, true, methods);
    checkPaths(['/blog/project/builds', '/changelog/project/builds', '/newsletter/issues/builds']
      .map((path) => `/${locale}${path}`), (p, m) => exempt(marketingRule, p, m), false, methods);
  }
});

test('combined rules protect deeper dashboards, auth and case-variant account paths', () => {
  checkPaths(['/tuist/tuist/builds', '/customers/acme/builds', '/es/acme/builds', '/es/customers/acme/builds',
    '/acme/blog/builds', '/sitemaps/other/1.xml', '/users/log_in', '/auth/callback', '/ops/og-gallery',
    '/blogs/acme/builds', '/changelogs/acme/builds', '/globe', '/en', '/xx/blog/2026/09/09/bazel',
    '/blog/acme/builds', '/Blog/acme/builds', '/changelog/acme/builds', '/Changelog/acme/builds',
    '/newsletter/issues/builds', '/Newsletter/issues/builds', '/es/Customers/builds',
    '/blog/2026/09/09/bazel/builds', '/blog/2026/09/09/bazel%2Fbuilds',
    '/es/blog/2026/09/09/bazel/iframe.html/builds', '/newsletter/issues/12/builds'], either, false, methods);
  assert.equal(either('/newsletter/verify'), true); // Existing two-segment root exemption.
  assert.equal(exempt(marketingRule, '/newsletter/verify'), false);
  assert.equal(either('/es/newsletter/verify'), false);
  checkPaths(['/sitemap-projects.xml', '/sitemaps/projects/1.xml', '/sitemaps/projects/999999.xml'],
    either, false, methods);
  checkPaths(['/blog/acme', '/Blog/acme', '/Changelog/acme',
    '/Newsletter/issues/12', '/sitemaps/projects/builds',
    '/sitemaps/projects/builds/1.xml'], (p, m) => exempt(marketingRule, p, m), false, methods);
});

test('marketing rule permits only reads on dashboard host', () => {
  checkPaths(['/pricing', '/newsletter'], (p, m) => exempt(marketingRule, p, m), false, writes);
  assert.equal(exempt(marketingRule, '/pricing', 'GET', 'search.tuist.dev'), false);
});

test('Bazel timeline JSON is an exact public read route with crawler-class counters', () => {
  const path = '/blog/bazel/timeline.json';
  const excluded = [`${path}/`, `${path}/builds`, `${path}.bak`,
    '/blog/bazel/timelineXjson', '/Blog/bazel/timeline.json', '/es/blog/bazel/timeline.json'];
  checkPaths([path], (p, m) => exempt(marketingRule, p, m), true, methods);
  checkPaths([path], either, false, writes);
  checkPaths(excluded, either, false, methods);
  for (const method of methods) {
    assert.equal(exempt(marketingRule, path, method, 'search.tuist.dev'), false);
  }

  for (const [index, file] of ['public-pages-rate-limit.yaml', 'verified-crawlers-rate-limit.yaml'].entries()) {
    const counter = expression(file, 'countingExpression');
    const request = { [field]: path, 'http.host': 'tuist.dev', 'cf.client.bot': index === 1 };
    for (const method of methods) {
      request['http.request.method'] = method;
      assert.equal(evaluate(counter, request), true, `${file}: ${method} ${path}`);
      for (const rejected of excluded) {
        assert.equal(evaluate(counter, { ...request, [field]: rejected }), false, `${file}: ${method} ${rejected}`);
      }
      assert.equal(evaluate(counter, { ...request, 'cf.client.bot': index !== 1 }), false);
      assert.equal(evaluate(counter, { ...request, 'http.host': 'search.tuist.dev' }), false);
    }
    for (const method of writes) {
      assert.equal(evaluate(counter, { ...request, 'http.request.method': method }), false, `${file}: ${method}`);
    }
  }
});

test('both crawler classes count header-free public reads and retain existing public counters', () => {
  const files = ['public-pages-rate-limit.yaml', 'verified-crawlers-rate-limit.yaml'];
  const counts = files.map((file) => expression(file, 'countingExpression'));
  assert.equal(counts[0].replace('not cf.client.bot', 'cf.client.bot'), counts[1]);
  const marketingPattern = marketingRule.match(/matches r"([^"]+)"/)[1];
  assert.ok(counts[0].includes(`matches r"${marketingPattern}"`));

  for (const [index, file] of files.entries()) {
    const rule = expression(file);
    const request = { 'http.host': 'tuist.dev', 'cf.client.bot': index === 1, publicHeader: undefined };
    for (const method of methods) {
      request['http.request.method'] = method;
      assert.equal(evaluate(rule, request), true, `${file}: ${method}`);
      for (const path of ['/pricing', '/blog/2026/11/06/continuous-localization', '/es/customers/acme',
        '/newsletter/issues/12', '/robots.txt',
        '/llms-full.txt', '/marketing-markdown/missing', '/en/docs/guides/install-tuist', '/ar/docs-markdown/']) {
        request[field] = path;
        assert.equal(evaluate(counts[index], request), true, `${file}: ${method} ${path}`);
      }
    }
    request['cf.client.bot'] = index !== 1;
    assert.equal(evaluate(rule, request), false, `${file}: opposite crawler class`);
    assert.equal(evaluate(counts[index], request), false, `${file}: opposite class must not count`);
    request['cf.client.bot'] = index === 1;
    for (const method of writes) {
      request['http.request.method'] = method;
      assert.equal(evaluate(rule, request), false, `${file}: ${method}`);
      for (const publicHeader of [undefined, '1']) {
        request.publicHeader = publicHeader;
        assert.equal(evaluate(counts[index], request), false, `${file}: ${method} must not count`);
      }
    }
    request['http.request.method'] = 'GET';
    request[field] = '/tuist/tuist';
    request.publicHeader = '1';
    assert.equal(evaluate(counts[index], request), true);
    request.publicHeader = undefined;
    assert.equal(evaluate(counts[index], request), false);
  }
});

test('all expressions fit Cloudflare limits', () => {
  for (const rule of [apiRule, marketingRule, ...['public-pages-rate-limit.yaml', 'verified-crawlers-rate-limit.yaml']
    .flatMap((file) => [expression(file), expression(file, 'countingExpression')])]) {
    assert.ok(Buffer.byteLength(rule) <= 4096);
  }
});
