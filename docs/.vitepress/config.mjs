import { defineConfig } from "vitepress";
import projectDescriptionTypesDataLoader from "../docs/reference/project-description/types.data";
import examplesDataLoader from "../docs/reference/examples/examples.data";

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
  themeConfig: {
    logo: "/logo.png",
    search: {
      provider: "local",
    },
    nav: [
      { text: "Tuist Cloud", link: "/cloud/what-is-cloud" },
      { text: "Guide", link: "/guide/introduction/what-is-tuist" },
      { text: "Reference", link: "/reference/cli/generate" },
      { text: "Changelog", link: "https://github.com/tuist/tuist/releases" },
    ],
    editLink: {
      pattern: "https://github.com/tuist/docs/edit/main/docs/:path",
    },
    sidebar: {
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
      "/guide/": [
        {
          text: "Introduction",
          items: [
            {
              text: "What is Tuist?",
              link: "/guide/introduction/what-is-tuist",
            },
            {
              text: "The cost of convenience",
              link: "/guide/introduction/cost-of-convenience",
            },
            {
              text: "From v3 to v4",
              link: "/guide/introduction/from-v3-to-v4",
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
                  link: "/guide/introduction/adopting-tuist/swift-package",
                },
                {
                  text: "Migrate local Swift Packages",
                },
                {
                  text: "Migrate from XcodeGen",
                  link: "/guide/introduction/adopting-tuist/migrate-from-xcodegen",
                },
                {
                  text: "Migrate from Bazel",
                  link: "/guide/introduction/adopting-tuist/migrate-from-xcodegen",
                },
              ],
            },
          ],
        },
        {
          text: "Project",
          items: [
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
            {
              text: "Xcode",
              link: "/guide/scale/xcode",
            },
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
            {
              text: "Types",
              collapsed: true,
              items: [
                { text: "Tasks" },
                { text: "Templates" },
                { text: "Resource synthesizers" },
              ],
            },
            {
              text: "Sharing (plugins)",
            },
          ],
        },
      ],
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
