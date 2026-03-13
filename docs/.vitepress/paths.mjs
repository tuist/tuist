function normalizeHref(href = "/") {
  if (!href) return "/";
  return href.startsWith("/") ? href : `/${href}`;
}

export function docsRoutePrefix(locale) {
  return `/${locale}/docs`;
}

export function localizedDocsPath(locale, href = "/") {
  const normalizedHref = normalizeHref(href);

  if (normalizedHref === "/") {
    return `${docsRoutePrefix(locale)}/`;
  }

  if (normalizedHref === "/docs") {
    return docsRoutePrefix(locale);
  }

  if (normalizedHref.startsWith("/docs/")) {
    return `/${locale}${normalizedHref}`;
  }

  return `${docsRoutePrefix(locale)}${normalizedHref}`;
}

export function stripDocsPathPrefix(pathname = "/") {
  if (pathname === "/docs") {
    return "/";
  }

  if (pathname.startsWith("/docs/")) {
    return pathname.slice(5);
  }

  return pathname;
}

export function rewriteDocsPublicPath(relativePath, locales) {
  const [locale, ...rest] = relativePath.split("/");

  if (!locales.includes(locale)) {
    return relativePath;
  }

  return [locale, "docs", ...rest].join("/");
}

export function rewriteDocsRedirectRules(content, locales) {
  const localeSegments = [...locales, ":locale"]
    .map((locale) => locale.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"))
    .join("|");
  const localePathRegex = new RegExp(`^\\/(${localeSegments})(\\/.*)?$`);

  const prefixDocs = (pathname) => {
    if (!pathname.startsWith("/")) {
      return pathname;
    }

    const match = pathname.match(localePathRegex);

    if (!match) {
      return pathname;
    }

    const [, locale, rest = ""] = match;

    if (rest === "/docs" || rest.startsWith("/docs/")) {
      return pathname;
    }

    return `/${locale}/docs${rest}`;
  };

  return content
    .trim()
    .split("\n")
    .map((line) => {
      const trimmed = line.trim();

      if (!trimmed || trimmed.startsWith("#")) {
        return trimmed;
      }

      const parts = trimmed.split(/\s+/);

      if (parts.length < 3) {
        return trimmed;
      }

      const [source, destination, ...rest] = parts;
      return [prefixDocs(source), prefixDocs(destination), ...rest].join(" ");
    })
    .join("\n");
}
