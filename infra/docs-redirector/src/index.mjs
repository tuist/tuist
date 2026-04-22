const APP_ORIGIN = "https://tuist.dev";

const SUPPORTED_DOCS_LOCALES = new Set([
  "en",
  "es",
  "ja",
  "ko",
  "ru",
  "yue_Hant",
  "zh_Hans",
  "zh_Hant",
]);

const LEGACY_ENGLISH_FALLBACK_LOCALES = new Set(["ar", "pl", "pt"]);

export function buildRedirectURL(requestUrl) {
  const url = new URL(requestUrl);
  const redirectURL = new URL(resolveDocsPath(url.pathname), APP_ORIGIN);
  redirectURL.search = url.search;
  return redirectURL.toString();
}

export function resolveDocsPath(pathname) {
  const segments = normalizeSegments(pathname);

  if (segments.length === 0) {
    return "/en/docs";
  }

  const [first, second, ...rest] = segments;

  if (first === "docs") {
    return resolveDocsPrefixedPath(second, rest);
  }

  if (SUPPORTED_DOCS_LOCALES.has(first)) {
    if (second === "docs") {
      return buildLocaleDocsPath(first, rest);
    }

    return buildLocaleDocsPath(first, [second, ...rest].filter(Boolean));
  }

  if (LEGACY_ENGLISH_FALLBACK_LOCALES.has(first)) {
    return buildEnglishDocsPath([second, ...rest].filter(Boolean));
  }

  return buildEnglishDocsPath([first, second, ...rest].filter(Boolean));
}

function resolveDocsPrefixedPath(maybeLocale, rest) {
  if (!maybeLocale) {
    return "/en/docs";
  }

  if (SUPPORTED_DOCS_LOCALES.has(maybeLocale)) {
    return buildLocaleDocsPath(maybeLocale, rest);
  }

  if (LEGACY_ENGLISH_FALLBACK_LOCALES.has(maybeLocale)) {
    return buildEnglishDocsPath(rest);
  }

  return buildEnglishDocsPath([maybeLocale, ...rest]);
}

function normalizeSegments(pathname) {
  const trimmed = pathname.trim();

  if (trimmed === "" || trimmed === "/") {
    return [];
  }

  const segments = trimmed.replace(/^\/+/, "").split("/").filter(Boolean);

  if (segments.at(-1) === "index") {
    return segments.slice(0, -1);
  }

  return segments;
}

function buildEnglishDocsPath(segments) {
  return buildLocaleDocsPath("en", segments);
}

function buildLocaleDocsPath(locale, segments) {
  return `/${locale}/docs${segments.length > 0 ? `/${segments.join("/")}` : ""}`;
}

export default {
  async fetch(request) {
    return Response.redirect(buildRedirectURL(request.url), 301);
  },
};
