import { comingSoonBadge } from "./badges.mjs";
import {
  cubeOutlineIcon,
  cube02Icon,
  cube01Icon,
  barChartSquare02Icon,
  code02Icon,
  dataIcon,
  checkCircleIcon,
  tuistIcon,
  cloudBlank02Icon,
  server04Icon,
} from "./icons.mjs";
import examplesDataLoader from "../docs/references/examples/examples.data";
import projectDescriptionTypesDataLoader from "../docs/references/project-description/types.data";
import cliDataLoader from "../docs/references/cli/commands.data";

const projectDescriptionTypesData = projectDescriptionTypesDataLoader.load();

const projectDescriptionSidebar = {
  text: "Project Description",
  collapsed: true,
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
          link: `/references/project-description/${item.identifier}`,
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
      link: `/references/cli/${item.command}`,
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

export const referencesSidebar = [
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
            link: `/references/examples/${item.name}`,
          };
        }),
      },
      {
        text: "Migrations",
        collapsed: true,
        items: [
          {
            text: "From v3 to v4",
            link: "/references/migrations/from-v3-to-v4",
          },
        ],
      },
    ],
  },
];

export const contributorsSidebar = [
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
];

export const guidesSidebar = [
  {
    text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Quick start ${tuistIcon()}</span>`,
    link: "/",
    items: [
      {
        text: "Install Tuist",
        link: "/guides/quick-start/install-tuist",
      },
      {
        text: "Create a project",
        link: "/guides/quick-start/create-a-project",
      },
      {
        text: "Add dependencies",
        link: "/guides/quick-start/add-dependencies",
      },
      {
        text: "Gather insights",
        link: "/guides/quick-start/gather-insights",
      },
      {
        text: "Optimize workflows",
        link: "/guides/quick-start/optimize-workflows",
      },
    ],
  },
  {
    text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Start ${cubeOutlineIcon()}</span>`,
    items: [
      {
        text: "Create a new project",
        link: "/guides/start/new-project",
      },
      {
        text: "Try with a Swift Package",
        link: "/guides/start/swift-package",
      },
      {
        text: "Migrate",
        collapsed: true,
        items: [
          {
            text: "An Xcode project",
            link: "/guides/start/migrate/xcode-project",
          },
          {
            text: "A Swift Package",
            link: "/guides/start/migrate/swift-package",
          },
          {
            text: "An XcodeGen project",
            link: "/guides/start/migrate/xcodegen-project",
          },
          {
            text: "A Bazel project",
            link: "/guides/start/migrate/bazel-project",
          },
        ],
      },
    ],
  },
  {
    text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Develop ${cube02Icon()}</span>`,
    items: [
      {
        text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Projects ${code02Icon()}</span>`,
        collapsed: true,
        link: "guides/develop/projects",
        items: [
          {
            text: "Manifests",
            link: "guides/develop/projects/manifests",
          },
          {
            text: "Directory structure",
            link: "guides/develop/projects/directory-structure",
          },
          {
            text: "Editing",
            link: "guides/develop/projects/editing",
          },
          {
            text: "Dependencies",
            link: "guides/develop/projects/dependencies",
          },
          {
            text: "Code sharing",
            link: "guides/develop/projects/code-sharing",
          },
          {
            text: "Synthesized files",
            link: "guides/develop/projects/synthesized-files",
          },
          {
            text: "Dynamic configuration",
            link: "guides/develop/projects/dynamic-configuration",
          },
          {
            text: "Templates",
            link: "guides/develop/projects/templates",
          },
          {
            text: "Plugins",
            link: "guides/develop/projects/plugins",
          },
          {
            text: "Hashing",
            link: "guides/develop/projects/hashing",
          },
          {
            text: "The cost of convenience",
            link: "guides/develop/projects/cost-of-convenience",
          },
          {
            text: "Modular architecture",
            link: "guides/develop/projects/tma-architecture",
          },
        ],
      },
      {
        text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Build ${dataIcon()}</span>`,
        link: "guides/develop/build",
        collapsed: true,
        items: [
          {
            text: "Cache",
            link: "guides/develop/build/cache",
          },
        ],
      },
      {
        text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Test ${checkCircleIcon()}</span>`,
        link: "guides/develop/test",
        collapsed: true,
        items: [
          {
            text: "Smart runner",
            link: "guides/develop/test/smart-runner",
          },
          {
            text: "Flakiness",
            link: "guides/develop/test/flakiness",
          },
        ],
      },
      {
        text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Automate ${cloudBlank02Icon()}</span>`,
        collapsed: true,
        items: [
          {
            text: `Continuous Integration`,
            link: "guides/develop/automate/continuous-integration",
          },
          {
            text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Workflows ${comingSoonBadge()}</span>`,
            link: "guides/develop/automate/workflows",
          },
        ],
      },
    ],
  },
  {
    text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Share ${cube01Icon()}</span>`,
    items: [
      {
        text: "Previews",
        link: "guides/share/previews",
      },
    ],
  },
  // {
  //   text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Measure ${barChartSquare02Icon()} ${comingSoonBadge()}</span>`,
  //   items: [],
  // },
  {
    text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Dashboard ${server04Icon()}</span>`,
    collapsed: true,
    items: [
      {
        text: "On-premise",
        collapsed: true,
        items: [
          {
            text: "Install",
            link: "guides/dashboard/on-premise/install",
          },
          {
            text: "Metrics",
            link: "guides/dashboard/on-premise/metrics",
          },
        ],
      },
    ],
  },
];
