import { defineConfig } from "vitepress";
import projectDescriptionTypesDataLoader from "../docs/reference/project-description/types.data";
import examplesDataLoader from "../docs/reference/examples/examples.data";
import cliDataLoader from "../docs/reference/cli/commands.data";
import * as path from "node:path";
import * as fs from "node:fs/promises";
import {
  cubeOutlineIcon,
  cube02Icon,
  cube01Icon,
  barChartSquare02Icon,
} from "./icons.mjs";

const projectDescriptionTypesData = projectDescriptionTypesDataLoader.load();

const projectDescriptionSidebar = {
  text: "Project Description",
  collapsed: true,
  items: [],
};

function capitalize(text) {
  return text.charAt(0).toUpperCase() + text.slice(1).toLowerCase();
}

function requiresProjectBadge() {
  return `<div style="background: var(--vp-custom-block-tip-code-bg); color: var(--vp-c-tip-1); font-size: 11px; display: inline-block; padding-left: 5px; padding-right: 5px; border-radius: 10%;">Tuist Project</div>`;
}

function requiresAccount() {
  return `<div style="background: var(--vp-c-success-soft); color: var(--vp-c-success-1); font-size: 11px; display: inline-block; padding-left: 5px; padding-right: 5px; border-radius: 10%;">Account required</div>`;
}

function appleIcon(size = 15) {
  return `<svg width="${size}" height="${size}" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 384 512"><!--!Font Awesome Free 6.5.2 by @fontawesome - https://fontawesome.com License - https://fontawesome.com/license/free Copyright 2024 Fonticons, Inc.--><path d="M318.7 268.7c-.2-36.7 16.4-64.4 50-84.8-18.8-26.9-47.2-41.7-84.7-44.6-35.5-2.8-74.3 20.7-88.5 20.7-15 0-49.4-19.7-76.4-19.7C63.3 141.2 4 184.8 4 273.5q0 39.3 14.4 81.2c12.8 36.7 59 126.7 107.2 125.2 25.2-.6 43-17.9 75.8-17.9 31.8 0 48.3 17.9 76.4 17.9 48.6-.7 90.4-82.5 102.6-119.3-65.2-30.7-61.7-90-61.7-91.9zm-56.6-164.2c27.3-32.4 24.8-61.9 24-72.5-24.1 1.4-52 16.4-67.9 34.9-17.5 19.8-27.8 44.3-25.6 71.9 26.1 2 49.9-11.4 69.5-34.3z"/></svg>`;
}

function tuistIcon(size = 15) {
  return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M21 16V7.2C21 6.0799 21 5.51984 20.782 5.09202C20.5903 4.71569 20.2843 4.40973 19.908 4.21799C19.4802 4 18.9201 4 17.8 4H6.2C5.07989 4 4.51984 4 4.09202 4.21799C3.71569 4.40973 3.40973 4.71569 3.21799 5.09202C3 5.51984 3 6.0799 3 7.2V16M4.66667 20H19.3333C19.9533 20 20.2633 20 20.5176 19.9319C21.2078 19.7469 21.7469 19.2078 21.9319 18.5176C22 18.2633 22 17.9533 22 17.3333C22 17.0233 22 16.8683 21.9659 16.7412C21.8735 16.3961 21.6039 16.1265 21.2588 16.0341C21.1317 16 20.9767 16 20.6667 16H3.33333C3.02334 16 2.86835 16 2.74118 16.0341C2.39609 16.1265 2.12654 16.3961 2.03407 16.7412C2 16.8683 2 17.0233 2 17.3333C2 17.9533 2 18.2633 2.06815 18.5176C2.25308 19.2078 2.79218 19.7469 3.48236 19.9319C3.73669 20 4.04669 20 4.66667 20Z" stroke="black" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
</svg>`;
}

[("structs", "enums", "extensions", "typealiases")].forEach((category) => {
  if (projectDescriptionTypesData.find((item) => item.category === category)) {
    projectDescriptionSidebar.items.push({
      text: capitalize(category),
      collapsed: true,
      items: projectDescriptionTypesData
        .filter((item) => item.category === category)
        .map((item) => ({
          text: item.title,
          link: `/reference/project-description/${item.identifier}`,
        })),
    });
  }
});

function generateNestedSidebarItems(items) {
  const nestedItems = {};

  items.forEach((item) => {
    const category = item.category;
    if (!nestedItems[category]) {
      nestedItems[category] = {
        text: capitalize(category),
        collapsed: true,
        items: [],
      };
    }
    nestedItems[category].items.push({
      text: item.title,
      link: `/reference/cli/${item.command}`,
    });
  });

  function isLinkItem(item) {
    return typeof item.link === "string";
  }

  function convertToArray(obj) {
    return Object.values(obj).reduce((acc, item) => {
      if (Array.isArray(item.items) && item.items.every(isLinkItem)) {
        acc.push(item);
      } else {
        acc.push({
          text: item.text,
          collapsed: true,
          items: convertToArray(item.items),
        });
      }
      return acc;
    }, []);
  }

  return convertToArray(nestedItems);
}

const cliData = cliDataLoader.load();

const cliSidebar = {
  text: "CLI",
  items: generateNestedSidebarItems(cliData),
};

const guideSidebar = [
  {
    text: `<div style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Quick start ${tuistIcon()}</div>`,
    link: "/",
    items: [
      {
        text: "Install Tuist",
        link: "/guide/quick-start/install-tuist",
      },
      {
        text: "Create a project",
        link: "/guide/quick-start/create-a-project",
      },
      {
        text: "Add dependencies",
        link: "/guide/quick-start/add-dependencies",
      },
      {
        text: "Gather insights",
        link: "/guide/quick-start/gather-insights",
      },
      {
        text: "Optimize workflows",
        link: "/guide/quick-start/optimize-workflows",
      },
    ],
  },
  {
    text: `<div style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Create ${cubeOutlineIcon()}</div>`,
    items: [],
  },
  {
    text: `<div style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Build ${cube02Icon()}</div>`,
    items: [],
  },
  {
    text: `<div style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Share ${cube01Icon()}</div>`,
    items: [],
  },
  {
    text: `<div style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Measure ${barChartSquare02Icon()}</div>`,
    items: [],
  },
  // {
  //   text: `<div style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Projects ${appleIcon()}</div>`,
  //   collapsed: true,
  //   link: "/guide/project",
  //   items: [
  //     {
  //       text: "Adoption",
  //       collapsed: true,
  //       items: [
  //         {
  //           text: "Create a project",
  //           link: "/guide/project/adoption/new-project",
  //         },
  //         {
  //           text: "Use it with a Swift Package",
  //           link: "/guide/project/adoption/swift-package",
  //         },
  //         {
  //           text: "Migrate from .xcodeproj",
  //           link: "/guide/project/adoption/migrate-from-xcodeproj",
  //         },
  //         {
  //           text: "Migrate local Swift Packages",
  //           link: "/guide/project/adoption/migrate-local-swift-packages",
  //         },
  //         {
  //           text: "Migrate from XcodeGen",
  //           link: "/guide/project/adoption/migrate-from-xcodegen",
  //         },
  //         {
  //           text: "Migrate from Bazel",
  //           link: "/guide/project/adoption/migrate-from-bazel",
  //         },
  //       ],
  //     },
  //     {
  //       text: "Manifests",
  //       link: "/guide/project/manifests",
  //     },
  //     {
  //       text: "Directory structure",
  //       link: "/guide/project/directory-structure",
  //     },
  //     { text: "Editing", link: "/guide/project/editing" },
  //     { text: "Dependencies", link: "/guide/project/dependencies" },
  //     { text: "Code sharing", link: "/guide/project/code-sharing" },
  //     {
  //       text: "Synthesized files",
  //       link: "/guide/project/synthesized-files",
  //     },
  //     {
  //       text: "Dynamic configuration",
  //       link: "/guide/project/dynamic-configuration",
  //     },
  //     {
  //       text: "Templates",
  //       link: "/guide/project/templates",
  //     },
  //     {
  //       text: "Plugins",
  //       link: "/guide/project/plugins",
  //     },
  //     {
  //       text: "Hashing",
  //       link: "/guide/project/hashing",
  //     },
  //     {
  //       text: "The modular architecture",
  //       link: "/guide/project/tma-architecture",
  //     },
  //     {
  //       text: "The cost of convenience",
  //       link: "/guide/project/cost-of-convenience",
  //     },
  //   ],
  // },
  // {
  //   text: `<div><div style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Cache ${appleIcon()}</div>${requiresProjectBadge()} ${requiresAccount()}</div>`,
  //   link: "/guide/cache",
  //   items: [],
  // },
  // {
  //   text: `<div><div style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Tests ${appleIcon()}</div>${requiresProjectBadge()} ${requiresAccount()}</div>`,
  //   items: [
  //     {
  //       text: "Smart runner",
  //       link: "/guide/tests/smart-runner",
  //     },
  //     {
  //       text: "Flakiness",
  //       link: "/guide/tests/flakiness",
  //     },
  //   ],
  // },
  // {
  //   text: `<div><div style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Runs ${appleIcon()}</div>${requiresProjectBadge()} ${requiresAccount()}</div>`,
  //   items: [
  //     {
  //       text: "Analytics",
  //     },
  //   ],
  // },
  // {
  //   text: "Tuist Cloud",
  //   items: [
  //     {
  //       text: "What is Tuist Cloud?",
  //       link: "/cloud/what-is-cloud",
  //     },
  //     {
  //       text: "Get started",
  //       link: "/cloud/get-started",
  //     },
  //     {
  //       text: "Selective testing",
  //       link: "/cloud/selective-testing",
  //     },
  //     {
  //       text: "On-premise",
  //       link: "/cloud/on-premise",
  //       items: [
  //         {
  //           text: "Metrics",
  //           link: "/cloud/on-premise/metrics",
  //         },
  //       ],
  //     },
  //   ],
  // },
];

// https://vitepress.dev/reference/site-config
export default defineConfig({
  title: "Tuist",
  titleTemplate: ":title | Tuist",
  description: "Scale your Xcode app development",
  srcDir: "docs",
  lastUpdated: true,
  locales: {
    root: {
      label: "English",
      lange: "en",
    },
  },
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
/documentation/tuist/installation /guide/cli/installation 301
/documentation/tuist/project-structure /guide/project/directory-structure 301
/documentation/tuist/command-line-interface /guide/tuist/commands/generate 301
/documentation/tuist/dependencies /guide/project/dependencies 301
/documentation/tuist/sharing-code-across-manifests /guide/project/code-sharing 301
/documentation/tuist/synthesized-files /guide/project/synthesized-files 301
/documentation/tuist/migration-guidelines /guide/project/adoption/migrate-from-xcodeproj 301
/tutorials/tuist-tutorials /guide/project/adoption/new-project 301
/tutorials/tuist/install  /guide/project/adoption/new-project 301
/tutorials/tuist/create-project  /guide/project/adoption/new-project 301
/tutorials/tuist/external-dependencies /guide/project/adoption/new-project 301
/documentation/tuist/generation-environment /guide/project/dynamic-configuration 301
/documentation/tuist/using-plugins /guide/project/plugins 301
/documentation/tuist/creating-plugins /guide/project/plugins 301
/documentation/tuist/task /guide/project/plugins 301
/documentation/tuist/tuist-cloud /cloud/what-is-cloud 301
/documentation/tuist/tuist-cloud-get-started /cloud/get-started 301
/documentation/tuist/binary-caching /guide/cache 301
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
/guide/scale/ufeatures-architecture.html /guide/project/tma-architecture.html 301
/guide/scale/ufeatures-architecture /guide/project/tma-architecture 301
/guide/introduction/cost-of-convenience /guide/project/cost-of-convenience 301
/guide/introduction/from-v3-to-v4 /guide/tuist/from-v3-to-v4 301
/guide/introduction/installation /guide/tuist/installation/cli 301
/guide/introduction/adopting-tuist/new-project /guide/project/adoption/new-project 301
/guide/introduction/adopting-tuist/swift-package /guide/project/adoption/swift-package 301
/guide/introduction/adopting-tuist/migrate-from-xcodeproj /guide/project/adoption/migrate-from-xcodeproj 301
/guide/introduction/adopting-tuist/migrate-local-swift-packages /guide/project/adoption/migrate-local-swift-packages 301
/guide/introduction/adopting-tuist/migrate-from-xcodegen /guide/project/adoption/migrate-from-xcodegen 301
/guide/introduction/adopting-tuist/migrate-from-bazel /guide/project/adoption/migrate-from-bazel 301
/guide/tuist/installation /guide/tuist/installation/cli 301
/cloud/on-premise /guide/tuist/installation/server 301
/cloud/binary-caching /guide/cache 301
/guide/automation/build /guide/tuist/commands/build 301
/guide/automation/test /guide/tuist/commands/test 301
/guide/automation/run /guide/tuist/commands/run 301
/guide/automation/graph /guide/tuist/commands/graph 301
/guide/automation/clean /guide/tuist/commands/clean 301
/guide/scale/tma-architecture /guide/project/tma-architecture 301
/cloud/hashing /guide/project/hashing 301
/documentation/tuist/* / 301
    `;
    fs.writeFile(redirectsPath, redirects);
  },
  themeConfig: {
    logo: "/logo.png",
    search: {
      provider: "local",
    },
    nav: [
      { text: "Guide", link: "/" },
      {
        text: "Reference",
        link: "/reference/project-description/structs/project",
      },
      { text: "Contributors", link: "/contributors/get-started" },
      { text: "Changelog", link: "https://github.com/tuist/tuist/releases" },
    ],
    editLink: {
      pattern: "https://github.com/tuist/tuist/edit/main/docs/docs/:path",
    },
    sidebar: {
      "/contributors": [
        {
          text: "Contributors",
          items: [
            {
              text: "Get started",
              link: "/contributors/get-started",
            },
            {
              text: "Issue reporting",
              link: "/contributors/issue-reporting",
            },
            {
              text: "Code reviews",
              link: "/contributors/code-reviews",
            },
            {
              text: "Principles",
              link: "/contributors/principles",
            },
          ],
        },
      ],
      "/guide/": guideSidebar,
      "/": guideSidebar,
      "/reference/": [
        {
          text: "Reference",
          items: [
            cliSidebar,
            projectDescriptionSidebar,
            {
              text: "Examples",
              collapsed: true,
              items: examplesDataLoader.load().map((item) => {
                return {
                  text: item.title,
                  link: `/reference/examples/${item.name}`,
                };
              }),
            },
            {
              text: "Migrations",
              collapsed: true,
              items: [
                {
                  text: "From v3 to v4",
                  link: "/reference/migrations/from-v3-to-v4",
                },
              ],
            },
          ],
        },
      ],
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
