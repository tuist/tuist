import { comingSoonBadge, xcodeProjCompatibleBadge } from "./badges.mjs";
import {
  cubeOutlineIcon,
  cube02Icon,
  cube01Icon,
  microscopeIcon,
  code02Icon,
  dataIcon,
  checkCircleIcon,
  tuistIcon,
  building07Icon,
  cloudBlank02Icon,
  server04Icon,
  bookOpen01Icon,
  codeBrowserIcon,
} from "./icons.mjs";
import { loadData as loadExamplesData } from "./data/examples";
import { loadData as loadProjectDescriptionData } from "./data/project-description";
import enStrings from "./strings/en.json";
import ruStrings from "./strings/ru.json";
import koStrings from "./strings/ko.json";
import jaStrings from "./strings/ja.json";

const strings = {
  en: enStrings,
  ru: ruStrings,
  ko: koStrings,
  ja: jaStrings,
};

function localizedString(locale, key) {
  const getString = (localeStrings, key) => {
    const keys = key.split(".");
    let current = localeStrings;

    for (const k of keys) {
      if (current && current.hasOwnProperty(k)) {
        current = current[k];
      } else {
        return undefined;
      }
    }
    return current;
  };

  let localizedValue = getString(strings[locale], key);

  if (localizedValue === undefined && locale !== "en") {
    localizedValue = getString(strings["en"], key);
  }

  return localizedValue;
}

async function projectDescriptionSidebar(locale) {
  const projectDescriptionTypesData = await loadProjectDescriptionData();
  const projectDescriptionSidebar = {
    text: "Project Description",
    collapsed: true,
    items: [],
  };
  function capitalize(text) {
    return text.charAt(0).toUpperCase() + text.slice(1).toLowerCase();
  }
  ["structs", "enums", "extensions", "typealiases"].forEach((category) => {
    if (
      projectDescriptionTypesData.find((item) => item.category === category)
    ) {
      projectDescriptionSidebar.items.push({
        text: capitalize(category),
        collapsed: true,
        items: projectDescriptionTypesData
          .filter((item) => item.category === category)
          .map((item) => ({
            text: item.title,
            link: `/${locale}/references/project-description/${item.identifier}`,
          })),
      });
    }
  });
  return projectDescriptionSidebar;
}

export async function referencesSidebar(locale) {
  return [
    {
      text: localizedString(locale, "sidebars.references.text"),
      items: [
        await projectDescriptionSidebar(locale),
        {
          text: localizedString(
            locale,
            "sidebars.references.items.examples.text"
          ),
          collapsed: true,
          items: (await loadExamplesData()).map((item) => {
            return {
              text: item.title,
              link: `/${locale}/references/examples/${item.name}`,
            };
          }),
        },
        {
          text: localizedString(
            locale,
            "sidebars.references.items.migrations.text"
          ),
          collapsed: true,
          items: [
            {
              text: localizedString(
                locale,
                "sidebars.references.items.migrations.items.from-v3-to-v4.text"
              ),
              link: "/references/migrations/from-v3-to-v4",
            },
          ],
        },
      ],
    },
  ];
}

export function navBar(locale) {
  return [
    {
      text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${localizedString(
        locale,
        "navbar.guides.text"
      )} ${bookOpen01Icon()}</span>`,
      link: `/${locale}/`,
    },
    {
      text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${localizedString(
        locale,
        "navbar.cli.text"
      )} ${codeBrowserIcon()}</span>`,
      link: `/${locale}/cli/auth`,
    },
    {
      text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${localizedString(
        locale,
        "navbar.server.text"
      )} ${server04Icon()}</span>`,
      link: `/${locale}/server/introduction/why-a-server`,
    },
    {
      text: localizedString(locale, "navbar.resources.text"),
      items: [
        {
          text: localizedString(
            locale,
            "navbar.resources.items.references.text"
          ),
          link: `/${locale}/references/project-description/structs/project`,
        },
        {
          text: localizedString(
            locale,
            "navbar.resources.items.contributors.text"
          ),
          link: `/${locale}/contributors/get-started`,
        },
        {
          text: localizedString(
            locale,
            "navbar.resources.items.changelog.text"
          ),
          link: "https://github.com/tuist/tuist/releases",
        },
      ],
    },
  ];
}

export function contributorsSidebar(locale) {
  return [
    {
      text: localizedString(locale, "sidebars.contributors.text"),
      items: [
        {
          text: localizedString(
            locale,
            "sidebars.contributors.items.get-started.text"
          ),
          link: `/${locale}/contributors/get-started`,
        },
        {
          text: localizedString(
            locale,
            "sidebars.contributors.items.issue-reporting.text"
          ),
          link: `/${locale}/contributors/issue-reporting`,
        },
        {
          text: localizedString(
            locale,
            "sidebars.contributors.items.code-reviews.text"
          ),
          link: `/${locale}/contributors/code-reviews`,
        },
        {
          text: localizedString(
            locale,
            "sidebars.contributors.items.principles.text"
          ),
          link: `/${locale}/contributors/principles`,
        },
      ],
    },
  ];
}

export function serverSidebar(locale) {
  return [
    {
      text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${localizedString(
        locale,
        "sidebars.server.items.introduction.text"
      )} ${server04Icon()}</span>`,
      items: [
        {
          text: localizedString(
            locale,
            "sidebars.server.items.introduction.items.why-server.text"
          ),
          link: `/${locale}/server/introduction/why-a-server`,
        },
        {
          text: localizedString(
            locale,
            "sidebars.server.items.introduction.items.accounts-and-projects.text"
          ),
          link: `/${locale}/server/introduction/accounts-and-projects`,
        },
        {
          text: localizedString(
            locale,
            "sidebars.server.items.introduction.items.authentication.text"
          ),
          link: `/${locale}/server/introduction/authentication`,
        },
        {
          text: localizedString(
            locale,
            "sidebars.server.items.introduction.items.integrations.text"
          ),
          link: `/${locale}/server/introduction/integrations`,
        },
      ],
    },
    {
      text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${localizedString(
        locale,
        "sidebars.server.items.on-premise.text"
      )} ${building07Icon()}</span>`,
      collapsed: true,
      items: [
        {
          text: localizedString(
            locale,
            "sidebars.server.items.on-premise.items.install.text"
          ),
          link: `/${locale}/server/on-premise/install`,
        },
        {
          text: localizedString(
            locale,
            "sidebars.server.items.on-premise.items.metrics.text"
          ),
          link: `/${locale}/server/on-premise/metrics`,
        },
      ],
    },
    {
      text: localizedString(
        locale,
        "sidebars.server.items.api-documentation.text"
      ),
      link: "https://cloud.tuist.io/api/docs",
    },
    {
      text: localizedString(locale, "sidebars.server.items.status.text"),
      link: "https://status.tuist.io",
    },
    {
      text: localizedString(
        locale,
        "sidebars.server.items.metrics-dashboard.text"
      ),
      link: "https://tuist.grafana.net/public-dashboards/1f85f1c3895e48febd02cc7350ade2d9",
    },
  ];
}

export function guidesSidebar(locale) {
  return [
    {
      text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Quick start ${tuistIcon()}</span>`,
      link: "/",
      items: [
        {
          text: "Install Tuist",
          link: `/${locale}/guides/quick-start/install-tuist`,
        },
        {
          text: "Create a project",
          link: `/${locale}/guides/quick-start/create-a-project`,
        },
        {
          text: "Add dependencies",
          link: `/${locale}/guides/quick-start/add-dependencies`,
        },
        {
          text: "Gather insights",
          link: `/${locale}/guides/quick-start/gather-insights`,
        },
        {
          text: "Optimize workflows",
          link: `/${locale}/guides/quick-start/optimize-workflows`,
        },
      ],
    },
    {
      text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Start ${cubeOutlineIcon()}</span>`,
      items: [
        {
          text: "Create a new project",
          link: `/${locale}/guides/start/new-project`,
        },
        {
          text: "Try with a Swift Package",
          link: `/${locale}/guides/start/swift-package`,
        },
        {
          text: "Migrate",
          collapsed: true,
          items: [
            {
              text: "An Xcode project",
              link: `/${locale}/guides/start/migrate/xcode-project`,
            },
            {
              text: "A Swift Package",
              link: `/${locale}/guides/start/migrate/swift-package`,
            },
            {
              text: "An XcodeGen project",
              link: `/${locale}/guides/start/migrate/xcodegen-project`,
            },
            {
              text: "A Bazel project",
              link: `/${locale}/guides/start/migrate/bazel-project`,
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
          link: `/${locale}/guides/develop/projects`,
          items: [
            {
              text: "Manifests",
              link: `/${locale}/guides/develop/projects/manifests`,
            },
            {
              text: "Directory structure",
              link: `/${locale}/guides/develop/projects/directory-structure`,
            },
            {
              text: "Editing",
              link: `/${locale}/guides/develop/projects/editing`,
            },
            {
              text: "Dependencies",
              link: `/${locale}/guides/develop/projects/dependencies`,
            },
            {
              text: "Code sharing",
              link: `/${locale}/guides/develop/projects/code-sharing`,
            },
            {
              text: "Synthesized files",
              link: `/${locale}/guides/develop/projects/synthesized-files`,
            },
            {
              text: "Dynamic configuration",
              link: `/${locale}/guides/develop/projects/dynamic-configuration`,
            },
            {
              text: "Templates",
              link: `/${locale}/guides/develop/projects/templates`,
            },
            {
              text: "Plugins",
              link: `/${locale}/guides/develop/projects/plugins`,
            },
            {
              text: "Hashing",
              link: `/${locale}/guides/develop/projects/hashing`,
            },
            {
              text: "The cost of convenience",
              link: `/${locale}/guides/develop/projects/cost-of-convenience`,
            },
            {
              text: "Modular architecture",
              link: `/${locale}/guides/develop/projects/tma-architecture`,
            },
            {
              text: "Best practices",
              link: `/${locale}/guides/develop/projects/best-practices`,
            },
          ],
        },
        {
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Build ${dataIcon()}</span>`,
          link: `/${locale}/guides/develop/build`,
          collapsed: true,
          items: [
            {
              text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Cache</span>`,
              link: `/${locale}/guides/develop/build/cache`,
            },
          ],
        },
        {
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Test ${checkCircleIcon()}</span>`,
          link: `/${locale}/guides/develop/test`,
          collapsed: true,
          items: [
            {
              text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Smart runner</span>`,
              link: `/${locale}/guides/develop/test/smart-runner`,
            },
            {
              text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Flakiness</span>`,
              link: `/${locale}/guides/develop/test/flakiness`,
            },
          ],
        },
        {
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Inspect ${microscopeIcon()}</span>`,
          collapsed: true,
          items: [
            {
              text: "Implicit dependencies",
              link: `/${locale}/guides/develop/inspect/implicit-dependencies`,
            },
          ],
        },
        {
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Automate ${cloudBlank02Icon()}</span>`,
          collapsed: true,
          items: [
            {
              text: `Continuous Integration`,
              link: `/${locale}/guides/develop/automate/continuous-integration`,
            },
            {
              text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Workflows ${comingSoonBadge()}</span>`,
              link: `/${locale}/guides/develop/automate/workflows`,
            },
          ],
        },
      ],
    },
    {
      text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Share ${cube01Icon()}</span>`,
      items: [
        {
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">Previews ${xcodeProjCompatibleBadge()}</span>`,
          link: `/${locale}/guides/share/previews`,
        },
      ],
    },
  ];
}
