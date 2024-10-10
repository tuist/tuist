import { defineConfig } from "vitepress";
import * as path from "node:path";
import * as fs from "node:fs/promises";
import {
  guidesSidebar,
  contributorsSidebar,
  referencesSidebar,
  serverSidebar,
} from "./sidebars.mjs";
import { loadData as loadCLIData } from "./data/cli";

import { server04Icon, bookOpen01Icon, codeBrowserIcon } from "./icons.mjs";

import { fileURLToPath } from "node:url";
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const paths = path.join(__dirname, "../../paths.txt");

export default defineConfig({
  title: "Tuist",
  titleTemplate: ":title | Tuist",
  description: "Scale your Xcode app development",
  srcDir: "docs",
  lastUpdated: true,
  locales: {
    en: {
      label: "English",
      lang: "en",
      themeConfig: {
        nav: [
          {
            text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Guides ${bookOpen01Icon()}</span>`,
            link: "/en/",
          },
          {
            text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">CLI ${codeBrowserIcon()}</span>`,
            link: "/en/cli/auth",
          },
          {
            text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Server ${server04Icon()}</span>`,
            link: "/en/server/introduction/why-a-server",
          },
          {
            text: "Resources",
            items: [
              {
                text: "References",
                link: "/en/references/project-description/structs/project",
              },
              { text: "Contributors", link: "/en/contributors/get-started" },
              {
                text: "Changelog",
                link: "https://github.com/tuist/tuist/releases",
              },
            ],
          },
        ],
        sidebar: {
          "/en/contributors": contributorsSidebar("en"),
          "/en/guides/": guidesSidebar("en"),
          "/en/server/": serverSidebar("en"),
          "/en/": guidesSidebar("en"),
          "/en/cli/": await loadCLIData("en"),
          "/en/references/": await referencesSidebar("en"),
        },
      },
    },
    ko: {
      label: "Korean",
      lang: "ko",
      themeConfig: {
        nav: [
          {
            text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Guides ${bookOpen01Icon()}</span>`,
            link: "/ko/",
          },
          {
            text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">CLI ${codeBrowserIcon()}</span>`,
            link: "/ko/cli/auth",
          },
          {
            text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Server ${server04Icon()}</span>`,
            link: "/ko/server/introduction/why-a-server",
          },
          {
            text: "Resources",
            items: [
              {
                text: "References",
                link: "/ko/references/project-description/structs/project",
              },
              { text: "Contributors", link: "/ko/contributors/get-started" },
              {
                text: "Changelog",
                link: "https://github.com/tuist/tuist/releases",
              },
            ],
          },
        ],
        sidebar: {
          "/ko/contributors": contributorsSidebar("ko"),
          "/ko/guides/": guidesSidebar("ko"),
          "/ko/server/": serverSidebar("ko"),
          "/ko/": guidesSidebar("ko"),
          "/ko/cli/": await loadCLIData("ko"),
          "/ko/references/": await referencesSidebar("ko"),
        },
      },
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
/documentation/tuist/* / 301
${await fs.readFile(path.join(import.meta.dirname, "locale-redirects.txt"), { encoding: "utf-8" })}
    `;
    fs.writeFile(redirectsPath, redirects);
  },
  themeConfig: {
    logo: "/logo.png",
    search: {
      provider: "local",
    },
    editLink: {
      pattern: "https://github.com/tuist/tuist/edit/main/docs/docs/:path",
    },
    socialLinks: [
      { icon: "github", link: "https://github.com/tuist/tuist" },
      { icon: "x", link: "https://x.com/tuistio" },
      { icon: "mastodon", link: "https://fosstodon.org/@tuist" },
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
