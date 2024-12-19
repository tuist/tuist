import { defineConfig } from "vitepress";
import * as path from "node:path";
import * as fs from "node:fs/promises";
import {
  guidesSidebar,
  contributorsSidebar,
  referencesSidebar,
  serverSidebar,
  navBar,
} from "./bars.mjs";
import { loadData as loadCLIData } from "./data/cli";
import { localizedString } from "./i18n.mjs";

async function themeConfig(locale) {
  const sidebar = {};
  sidebar[`/${locale}/contributors`] = contributorsSidebar(locale);
  sidebar[`/${locale}/guides/`] = guidesSidebar(locale);
  sidebar[`/${locale}/server/`] = serverSidebar(locale);
  sidebar[`/${locale}/`] = guidesSidebar(locale);
  sidebar[`/${locale}/cli/`] = await loadCLIData(locale);
  sidebar[`/${locale}/references/`] = await referencesSidebar(locale);
  return {
    nav: navBar(locale),
    sidebar,
  };
}

function getSearchOptionsForLocale(locale) {
  return {
    placeholder: localizedString(locale, "search.placeholder"),
    translations: {
      button: {
        buttonText: localizedString(
          locale,
          "search.translations.button.buttonText",
        ),
        buttonAriaLabel: localizedString(
          locale,
          "search.translations.button.buttonAriaLabel",
        ),
      },
      modal: {
        searchBox: {
          resetButtonTitle: localizedString(
            locale,
            "search.translations.modal.search-box.reset-button-title",
          ),
          resetButtonAriaLabel: localizedString(
            locale,
            "search.translations.modal.search-box.reset-button-aria-label",
          ),
          cancelButtonText: localizedString(
            locale,
            "search.translations.modal.search-box.cancel-button-text",
          ),
          cancelButtonAriaLabel: localizedString(
            locale,
            "search.translations.modal.search-box.cancel-button-aria-label",
          ),
        },
        startScreen: {
          recentSearchesTitle: localizedString(
            locale,
            "search.translations.modal.start-screen.recent-searches-title",
          ),
          noRecentSearchesText: localizedString(
            locale,
            "search.translations.modal.start-screen.no-recent-searches-text",
          ),
          saveRecentSearchButtonTitle: localizedString(
            locale,
            "search.translations.modal.start-screen.save-recent-search-button-title",
          ),
          removeRecentSearchButtonTitle: localizedString(
            locale,
            "search.translations.modal.start-screen.remove-recent-search-button-title",
          ),
          favoriteSearchesTitle: localizedString(
            locale,
            "search.translations.modal.start-screen.favorite-searches-title",
          ),
          removeFavoriteSearchButtonTitle: localizedString(
            locale,
            "search.translations.modal.start-screen.remove-favorite-search-button-title",
          ),
        },
        errorScreen: {
          titleText: localizedString(
            locale,
            "search.translations.modal.error-screen.title-text",
          ),
          helpText: localizedString(
            locale,
            "search.translations.modal.error-screen.help-text",
          ),
        },
        footer: {
          selectText: localizedString(
            locale,
            "search.translations.modal.footer.select-text",
          ),
          navigateText: localizedString(
            locale,
            "search.translations.modal.footer.navigate-text",
          ),
          closeText: localizedString(
            locale,
            "search.translations.modal.footer.close-text",
          ),
          searchByText: localizedString(
            locale,
            "search.translations.modal.footer.search-by-text",
          ),
        },
        noResultsScreen: {
          noResultsText: localizedString(
            locale,
            "search.translations.modal.no-results-screen.no-results-text",
          ),
          suggestedQueryText: localizedString(
            locale,
            "search.translations.modal.no-results-screen.suggested-query-text",
          ),
          reportMissingResultsText: localizedString(
            locale,
            "search.translations.modal.no-results-screen.report-missing-results-text",
          ),
          reportMissingResultsLinkText: localizedString(
            locale,
            "search.translations.modal.no-results-screen.report-missing-results-link-text",
          ),
        },
      },
    },
  };
}

const searchOptionsLocales = {
  en: getSearchOptionsForLocale("en"),
  ko: getSearchOptionsForLocale("ko"),
  ja: getSearchOptionsForLocale("ja"),
  ru: getSearchOptionsForLocale("ru"),
  es: getSearchOptionsForLocale("es"),
};

export default defineConfig({
  title: "Tuist",
  titleTemplate: ":title | Tuist",
  description: "Scale your Xcode app development",
  srcDir: "docs",
  lastUpdated: false,
  locales: {
    en: {
      label: "English",
      lang: "en",
      themeConfig: await themeConfig("en"),
    },
    ko: {
      label: "한국어 (Korean)",
      lang: "ko",
      themeConfig: await themeConfig("ko"),
    },
    ja: {
      label: "日本語 (Japanese)",
      lang: "ja",
      themeConfig: await themeConfig("ja"),
    },
    ru: {
      label: "Русский (Russian)",
      lang: "ru",
      themeConfig: await themeConfig("ru"),
    },
    es: {
      label: "Castellano (Spanish)",
      lang: "es",
      themeConfig: await themeConfig("es"),
    },
    pt: {
      label: "Português (Portuguese)",
      lang: "pt",
      themeConfig: await themeConfig("pt"),
    },
  },
  cleanUrls: true,
  head: [
    [
      "script",
      {},
      `
      !function(t,e){var o,n,p,r;e.__SV||(window.posthog=e,e._i=[],e.init=function(i,s,a){function g(t,e){var o=e.split(".");2==o.length&&(t=t[o[0]],e=o[1]),t[e]=function(){t.push([e].concat(Array.prototype.slice.call(arguments,0)))}}(p=t.createElement("script")).type="text/javascript",p.async=!0,p.src=s.api_host.replace(".i.posthog.com","-assets.i.posthog.com")+"/static/array.js",(r=t.getElementsByTagName("script")[0]).parentNode.insertBefore(p,r);var u=e;for(void 0!==a?u=e[a]=[]:a="posthog",u.people=u.people||[],u.toString=function(t){var e="posthog";return"posthog"!==a&&(e+="."+a),t||(e+=" (stub)"),e},u.people.toString=function(){return u.toString(1)+".people (stub)"},o="capture identify alias people.set people.set_once set_config register register_once unregister opt_out_capturing has_opted_out_capturing opt_in_capturing reset isFeatureEnabled onFeatureFlags getFeatureFlag getFeatureFlagPayload reloadFeatureFlags group updateEarlyAccessFeatureEnrollment getEarlyAccessFeatures getActiveMatchingSurveys getSurveys onSessionId".split(" "),n=0;n<o.length;n++)g(u,o[n]);e._i.push([i,s,a])},e.__SV=1)}(document,window.posthog||[]);
      posthog.init('phc_stva6NJi8LG6EmR6RA6uQcRdrmfTQcAVLoO3vGgWmNZ',{api_host:'https://eu.i.posthog.com'})
    `,
    ],
    [
      "script",
      {},
      `
      !function(t){if(window.ko)return;window.ko=[],["identify","track","removeListeners","open","on","off","qualify","ready"].forEach(function(t){ko[t]=function(){var n=[].slice.call(arguments);return n.unshift(t),ko.push(n),ko}});var n=document.createElement("script");n.async=!0,n.setAttribute("src","https://cdn.getkoala.com/v1/pk_3f80a3529ec2914b714a3f740d10b12642b9/sdk.js"),(document.body || document.head).appendChild(n)}();
    `,
    ],
    ["meta", { property: "og:url", content: "https://docs.tuist.io" }, ""],
    ["meta", { property: "og:type", content: "website" }, ""],
    [
      "meta",
      { property: "og:image", content: "https://docs.tuist.io/images/og.jpeg" },
      "",
    ],
    ["meta", { name: "twitter:card", content: "summary" }, ""],
    ["meta", { property: "twitter:domain", content: "docs.tuist.io" }, ""],
    ["meta", { property: "twitter:url", content: "https://docs.tuist.io" }, ""],
    [
      "meta",
      {
        name: "twitter:image",
        content: "https://docs.tuist.io/images/og.jpeg",
      },
      "",
    ],
  ],
  sitemap: {
    hostname: "https://docs.tuist.io",
  },
  async buildEnd({ outDir }) {
    const redirectsPath = path.join(outDir, "_redirects");
    const redirects = `
/documentation/tuist/installation /guide/introduction/installation 301
/documentation/tuist/project-structure /guide/project/directory-structure 301
/documentation/tuist/command-line-interface /guide/automation/generate 301
/documentation/tuist/dependencies /guide/project/dependencies 301
/documentation/tuist/sharing-code-across-manifests /guide/project/code-sharing 301
/documentation/tuist/synthesized-files /guide/project/synthesized-files 301
/documentation/tuist/migration-guidelines /guide/introduction/adopting-tuist/migrate-from-xcodeproj 301
/tutorials/tuist-tutorials /guide/introduction/adopting-tuist/new-project 301
/tutorials/tuist/install  /guide/introduction/adopting-tuist/new-project 301
/tutorials/tuist/create-project  /guide/introduction/adopting-tuist/new-project 301
/tutorials/tuist/external-dependencies /guide/introduction/adopting-tuist/new-project 301
/documentation/tuist/generation-environment /guide/project/dynamic-configuration 301
/documentation/tuist/using-plugins /guide/project/plugins 301
/documentation/tuist/creating-plugins /guide/project/plugins 301
/documentation/tuist/task /guide/project/plugins 301
/documentation/tuist/tuist-cloud /cloud/what-is-cloud 301
/documentation/tuist/tuist-cloud-get-started /cloud/get-started 301
/documentation/tuist/binary-caching /cloud/binary-caching 301
/documentation/tuist/selective-testing /cloud/selective-testing 301
/tutorials/tuist-cloud-tutorials /cloud/on-premise 301
/tutorials/tuist/enterprise-infrastructure-requirements /cloud/on-premise 301
/tutorials/tuist/enterprise-environment /cloud/on-premise 301
/tutorials/tuist/enterprise-deployment /cloud/on-premise 301
/documentation/tuist/get-started-as-contributor /contributors/get-started 301
/documentation/tuist/manifesto /contributors/principles 301
/documentation/tuist/code-reviews /contributors/code-reviews 301
/documentation/tuist/reporting-bugs /contributors/issue-reporting 301
/documentation/tuist/championing-projects /contributors/get-started 301
/guide/scale/ufeatures-architecture.html /guide/scale/tma-architecture.html 301
/guide/scale/ufeatures-architecture /guide/scale/tma-architecture 301
/guide/introduction/cost-of-convenience /guides/develop/projects/cost-of-convenience 301
/guide/introduction/installation /guides/quick-start/install-tuist 301
/guide/introduction/adopting-tuist/new-project /guides/start/new-project 301
/guide/introduction/adopting-tuist/swift-package /guides/start/swift-package 301
/guide/introduction/adopting-tuist/migrate-from-xcodeproj /guides/start/migrate/xcode-project 301
/guide/introduction/adopting-tuist/migrate-local-swift-packages /guides/start/migrate/swift-package 301
/guide/introduction/adopting-tuist/migrate-from-xcodegen /guides/start/migrate/xcodegen-project 301
/guide/introduction/adopting-tuist/migrate-from-bazel /guides/start/migrate/bazel-project 301
/guide/introduction/from-v3-to-v4 /references/migrations/from-v3-to-v4 301
/guide/project/manifests /guides/develop/projects/manifests 301
/guide/project/directory-structure /guides/develop/projects/directory-structure 301
/guide/project/editing /guides/develop/projects/editing 301
/guide/project/dependencies /guides/develop/projects/dependencies 301
/guide/project/code-sharing /guides/develop/projects/code-sharing 301
/guide/project/synthesized-files /guides/develop/projects/synthesized-files 301
/guide/project/dynamic-configuration /guides/develop/projects/dynamic-configuration 301
/guide/project/templates /guides/develop/projects/templates 301
/guide/project/plugins /guides/develop/projects/plugins 301
/guide/automation/generate / 301
/guide/automation/build /guides/develop/build 301
/guide/automation/test /guides/develop/test 301
/guide/automation/run / 301
/guide/automation/graph / 301
/guide/automation/clean / 301
/guide/scale/tma-architecture /guides/develop/projects/tma-architecture 301
/cloud/what-is-cloud / 301
/cloud/get-started / 301
/cloud/binary-caching /guides/develop/build/cache 301
/cloud/selective-testing /guides/develop/test/smart-runner 301
/cloud/hashing /guides/develop/projects/hashing 301
/cloud/on-premise /guides/dashboard/on-premise/install 301
/cloud/on-premise/metrics /guides/dashboard/on-premise/metrics 301
/reference/project-description/* /references/project-description/:splat 301
/reference/examples/* /references/examples/:splat 301
/guides/develop/workflows /guides/develop/continuous-integration/workflows 301
/guides/dashboard/on-premise/install /server/on-premise/install 301
/guides/dashboard/on-premise/metrics /server/on-premise/metrics 301
/:locale/references/project-description/structs/config /:locale/references/project-description/structs/tuist  301
/:locale/guides/develop/test/smart-runner /:locale/guides/develop/test/selective-testing 301
/documentation/tuist/* / 301
${await fs.readFile(path.join(import.meta.dirname, "locale-redirects.txt"), {
  encoding: "utf-8",
})}
    `;
    fs.writeFile(redirectsPath, redirects);
  },
  themeConfig: {
    logo: "/logo.png",
    search: {
      provider: "algolia",
      options: {
        appId: "5A3L9HI9VQ",
        apiKey: "cd45f515fb1fbb720d633cb0f1257e7a",
        indexName: "tuist",
        locales: searchOptionsLocales,
        startUrls: ["https://tuist.dev/"],
        renderJavaScript: false,
        sitemaps: [],
        exclusionPatterns: [],
        ignoreCanonicalTo: false,
        discoveryPatterns: ["https://tuist.dev/**"],
        schedule: "at 05:10 on Saturday",
        actions: [
          {
            indexName: "tuist",
            pathsToMatch: ["https://tuist.dev/**"],
            recordExtractor: ({ $, helpers }) => {
              return helpers.docsearch({
                recordProps: {
                  lvl1: ".content h1",
                  content: ".content p, .content li",
                  lvl0: {
                    selectors: "section.has-active div h2",
                    defaultValue: "Documentation",
                  },
                  lvl2: ".content h2",
                  lvl3: ".content h3",
                  lvl4: ".content h4",
                  lvl5: ".content h5",
                },
                indexHeadings: true,
              });
            },
          },
        ],
        initialIndexSettings: {
          vitepress: {
            attributesForFaceting: ["type", "lang"],
            attributesToRetrieve: ["hierarchy", "content", "anchor", "url"],
            attributesToHighlight: ["hierarchy", "hierarchy_camel", "content"],
            attributesToSnippet: ["content:10"],
            camelCaseAttributes: ["hierarchy", "hierarchy_radio", "content"],
            searchableAttributes: [
              "unordered(hierarchy_radio_camel.lvl0)",
              "unordered(hierarchy_radio.lvl0)",
              "unordered(hierarchy_radio_camel.lvl1)",
              "unordered(hierarchy_radio.lvl1)",
              "unordered(hierarchy_radio_camel.lvl2)",
              "unordered(hierarchy_radio.lvl2)",
              "unordered(hierarchy_radio_camel.lvl3)",
              "unordered(hierarchy_radio.lvl3)",
              "unordered(hierarchy_radio_camel.lvl4)",
              "unordered(hierarchy_radio.lvl4)",
              "unordered(hierarchy_radio_camel.lvl5)",
              "unordered(hierarchy_radio.lvl5)",
              "unordered(hierarchy_radio_camel.lvl6)",
              "unordered(hierarchy_radio.lvl6)",
              "unordered(hierarchy_camel.lvl0)",
              "unordered(hierarchy.lvl0)",
              "unordered(hierarchy_camel.lvl1)",
              "unordered(hierarchy.lvl1)",
              "unordered(hierarchy_camel.lvl2)",
              "unordered(hierarchy.lvl2)",
              "unordered(hierarchy_camel.lvl3)",
              "unordered(hierarchy.lvl3)",
              "unordered(hierarchy_camel.lvl4)",
              "unordered(hierarchy.lvl4)",
              "unordered(hierarchy_camel.lvl5)",
              "unordered(hierarchy.lvl5)",
              "unordered(hierarchy_camel.lvl6)",
              "unordered(hierarchy.lvl6)",
              "content",
            ],
            distinct: true,
            attributeForDistinct: "url",
            customRanking: [
              "desc(weight.pageRank)",
              "desc(weight.level)",
              "asc(weight.position)",
            ],
            ranking: [
              "words",
              "filters",
              "typo",
              "attribute",
              "proximity",
              "exact",
              "custom",
            ],
            highlightPreTag:
              '<span class="algolia-docsearch-suggestion--highlight">',
            highlightPostTag: "</span>",
            minWordSizefor1Typo: 3,
            minWordSizefor2Typos: 7,
            allowTyposOnNumericTokens: false,
            minProximity: 1,
            ignorePlurals: true,
            advancedSyntax: true,
            attributeCriteriaComputedByMinProximity: true,
            removeWordsIfNoResults: "allOptional",
          },
        },
      },
    },
    editLink: {
      pattern: "https://github.com/tuist/tuist/edit/main/docs/docs/:path",
    },
    socialLinks: [
      { icon: "github", link: "https://github.com/tuist/tuist" },
      { icon: "mastodon", link: "https://fosstodon.org/@tuist" },
      { icon: "bluesky", link: "https://bsky.app/profile/tuist.dev" },
      {
        icon: "slack",
        link: "https://join.slack.com/t/tuistapp/shared_invite/zt-1y667mjbk-s2LTRX1YByb9EIITjdLcLw",
      },
    ],
    footer: {
      message: "Released under the MIT License.",
      copyright: "Copyright © 2024-present Tuist GmbH",
    },
  },
});
