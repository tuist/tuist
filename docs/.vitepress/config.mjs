import { defineConfig } from "vitepress";
import projectDescriptionTypesDataLoader from "../docs/reference/project-description/types.data";
import examplesDataLoader from "../docs/reference/examples/examples.data";
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
          link: `/reference/project-description/${item.name}`,
        })),
    });
  }
});

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
    text: "Project",
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
    ],
  },
  {
    text: "Automation",
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
    text: "Scale",
    items: [
      // {
      //   text: "Xcode",
      //   link: "/guide/scale/xcode",
      // },
      {
        text: "µFeatures architecture",
        link: "/guide/scale/ufeatures-architecture",
      },
      {
        text: "Tuist Cloud",
        link: "/cloud/what-is-cloud",
      },
    ],
  },
  {
    text: "Extensions",
    items: [
      { text: "Tasks", link: "/guide/extensions/tasks" },
      { text: "Templates" },
      { text: "Resource synthesizers" },
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
/documentation/tuist/* /reference/project-description/:splat 301
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
      { text: "Reference", link: "/reference/project-description/project" },
      { text: "Tuist Cloud", link: "/cloud/what-is-cloud" },
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
      "/cloud": [
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
              text: "On-premise",
              link: "/cloud/on-premise",
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
            // TODO
            // {
            //   text: "CLI",
            //   items: cliDataLoader.load().map((item) => {
            //     return {
            //       text: item.title,
            //       link: `/reference/cli/${item.command}`,
            //     };
            //   }),
            // },
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
