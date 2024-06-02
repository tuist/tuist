import { defineConfig } from "vitepress";
import projectDescriptionTypesDataLoader from "../docs/reference/project-description/types.data";
import examplesDataLoader from "../docs/reference/examples/examples.data";
import cliDataLoader from "../docs/reference/cli/commands.data";
import * as path from "node:path";
import * as fs from "node:fs/promises";

const projectDescriptionTypesData = projectDescriptionTypesDataLoader.load();

const projectDescriptionSidebar = {
  text: "Project Description",
  items: [],
};

function capitalize(text) {
  return text.charAt(0).toUpperCase() + text.slice(1).toLowerCase();
}

["structs", "enums", "extensions", "typealiases"].forEach((category) => {
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
    const category = item.category
    if (!nestedItems[category]) {
      nestedItems[category] = {
        text: capitalize(category),
        collapsed: true,
        items: [],
      };
    }
    nestedItems[category].items.push({ text: item.title, link: `/reference/cli/${item.command}` });
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
    text: "Introduction",
    items: [
      {
        text: "What is Tuist?",
        link: "/",
      },
      {
        text: "The cost of convenience",
        link: "/guide/introduction/cost-of-convenience",
      },
      {
        text: "Installation",
        link: "/guide/introduction/installation",
      },
      {
        text: "Adopting Tuist",
        collapsed: true,
        items: [
          {
            text: "Create a project",
            link: "/guide/introduction/adopting-tuist/new-project",
          },
          {
            text: "Use it with a Swift Package",
            link: "/guide/introduction/adopting-tuist/swift-package",
          },
          {
            text: "Migrate from .xcodeproj",
            link: "/guide/introduction/adopting-tuist/migrate-from-xcodeproj",
          },
          {
            text: "Migrate local Swift Packages",
            link: "/guide/introduction/adopting-tuist/migrate-local-swift-packages",
          },
          {
            text: "Migrate from XcodeGen",
            link: "/guide/introduction/adopting-tuist/migrate-from-xcodegen",
          },
          {
            text: "Migrate from Bazel",
            link: "/guide/introduction/adopting-tuist/migrate-from-bazel",
          },
        ],
      },
      {
        text: "From v3 to v4",
        link: "/guide/introduction/from-v3-to-v4",
      },
    ],
  },
  {
    text: "Tuist Projects",
    items: [
      {
        text: "Manifests",
        link: "/guide/project/manifests",
      },
      {
        text: "Directory structure",
        link: "/guide/project/directory-structure",
      },
      { text: "Editing", link: "/guide/project/editing" },
      { text: "Dependencies", link: "/guide/project/dependencies" },
      { text: "Code sharing", link: "/guide/project/code-sharing" },
      {
        text: "Synthesized files",
        link: "/guide/project/synthesized-files",
      },
      {
        text: "Dynamic configuration",
        link: "/guide/project/dynamic-configuration",
      },
      {
        text: "Templates",
        link: "/guide/project/templates",
      },
      {
        text: "Plugins",
        link: "/guide/project/plugins",
      },
      {
        text: "Commands",
        collapsed: true,
        items: [
          { text: "Generate", link: "/guide/automation/generate" },
          { text: "Build", link: "/guide/automation/build" },
          { text: "Test", link: "/guide/automation/test" },
          { text: "Run", link: "/guide/automation/run" },
          { text: "Graph", link: "/guide/automation/graph" },
          { text: "Clean", link: "/guide/automation/clean" },
        ],
      },
      {
        text: "The Modular Architecture",
        link: "/guide/scale/tma-architecture",
      },
    ],
  },
  {
    text: "Tuist Cloud",
    items: [
      {
        text: "What is Tuist Cloud?",
        link: "/cloud/what-is-cloud",
      },
      {
        text: "Get started",
        link: "/cloud/get-started",
      },
      {
        text: "Binary caching",
        link: "/cloud/binary-caching",
      },
      {
        text: "Selective testing",
        link: "/cloud/selective-testing",
      },
      {
        text: "Hashing",
        link: "/cloud/hashing",
      },
      {
        text: "On-premise",
        link: "/cloud/on-premise",
      },
    ],
  },
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
              items: examplesDataLoader.load().map((item) => {
                return {
                  text: item.title,
                  link: `/reference/examples/${item.name}`,
                };
              }),
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
