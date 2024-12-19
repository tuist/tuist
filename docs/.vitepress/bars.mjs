import { comingSoonBadge, xcodeProjCompatibleBadge } from "./badges.mjs";
import {
  cubeOutlineIcon,
  cube02Icon,
  cube01Icon,
  tuistIcon,
  building07Icon,
  server04Icon,
  bookOpen01Icon,
  codeBrowserIcon,
} from "./icons.mjs";
import { loadData as loadExamplesData } from "./data/examples";
import { loadData as loadProjectDescriptionData } from "./data/project-description";
import { localizedString } from "./i18n.mjs";

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
            "sidebars.references.items.examples.text",
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
            "sidebars.references.items.migrations.text",
          ),
          collapsed: true,
          items: [
            {
              text: localizedString(
                locale,
                "sidebars.references.items.migrations.items.from-v3-to-v4.text",
              ),
              link: `/${locale}/references/migrations/from-v3-to-v4`,
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
        "navbar.guides.text",
      )} ${bookOpen01Icon()}</span>`,
      link: `/${locale}/`,
    },
    {
      text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${localizedString(
        locale,
        "navbar.cli.text",
      )} ${codeBrowserIcon()}</span>`,
      link: `/${locale}/cli/auth`,
    },
    {
      text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${localizedString(
        locale,
        "navbar.server.text",
      )} ${server04Icon()}</span>`,
      link: `/${locale}/server/introduction/why-a-server`,
    },
    {
      text: localizedString(locale, "navbar.resources.text"),
      items: [
        {
          text: localizedString(
            locale,
            "navbar.resources.items.references.text",
          ),
          link: `/${locale}/references/project-description/structs/project`,
        },
        {
          text: localizedString(
            locale,
            "navbar.resources.items.contributors.text",
          ),
          link: `/${locale}/contributors/get-started`,
        },
        {
          text: localizedString(
            locale,
            "navbar.resources.items.changelog.text",
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
            "sidebars.contributors.items.get-started.text",
          ),
          link: `/${locale}/contributors/get-started`,
        },
        {
          text: localizedString(
            locale,
            "sidebars.contributors.items.issue-reporting.text",
          ),
          link: `/${locale}/contributors/issue-reporting`,
        },
        {
          text: localizedString(
            locale,
            "sidebars.contributors.items.code-reviews.text",
          ),
          link: `/${locale}/contributors/code-reviews`,
        },
        {
          text: localizedString(
            locale,
            "sidebars.contributors.items.principles.text",
          ),
          link: `/${locale}/contributors/principles`,
        },
        {
          text: localizedString(
            locale,
            "sidebars.contributors.items.translate.text",
          ),
          link: `/${locale}/contributors/translate`,
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
        "sidebars.server.items.introduction.text",
      )} ${server04Icon()}</span>`,
      items: [
        {
          text: localizedString(
            locale,
            "sidebars.server.items.introduction.items.why-server.text",
          ),
          link: `/${locale}/server/introduction/why-a-server`,
        },
        {
          text: localizedString(
            locale,
            "sidebars.server.items.introduction.items.accounts-and-projects.text",
          ),
          link: `/${locale}/server/introduction/accounts-and-projects`,
        },
        {
          text: localizedString(
            locale,
            "sidebars.server.items.introduction.items.authentication.text",
          ),
          link: `/${locale}/server/introduction/authentication`,
        },
        {
          text: localizedString(
            locale,
            "sidebars.server.items.introduction.items.integrations.text",
          ),
          link: `/${locale}/server/introduction/integrations`,
        },
      ],
    },
    {
      text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${localizedString(
        locale,
        "sidebars.server.items.on-premise.text",
      )} ${building07Icon()}</span>`,
      collapsed: true,
      items: [
        {
          text: localizedString(
            locale,
            "sidebars.server.items.on-premise.items.install.text",
          ),
          link: `/${locale}/server/on-premise/install`,
        },
        {
          text: localizedString(
            locale,
            "sidebars.server.items.on-premise.items.metrics.text",
          ),
          link: `/${locale}/server/on-premise/metrics`,
        },
      ],
    },
    {
      text: localizedString(
        locale,
        "sidebars.server.items.api-documentation.text",
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
        "sidebars.server.items.metrics-dashboard.text",
      ),
      link: "https://tuist.grafana.net/public-dashboards/1f85f1c3895e48febd02cc7350ade2d9",
    },
  ];
}

export function guidesSidebar(locale) {
  return [
    {
      text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${localizedString(
        locale,
        "sidebars.guides.items.quick-start.text",
      )} ${tuistIcon()}</span>`,
      items: [
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.quick-start.items.install-tuist.text",
          ),
          link: `/${locale}/guides/quick-start/install-tuist`,
        },
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.quick-start.items.create-a-project.text",
          ),
          link: `/${locale}/guides/quick-start/create-a-project`,
        },
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.quick-start.items.add-dependencies.text",
          ),
          link: `/${locale}/guides/quick-start/add-dependencies`,
        },
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.quick-start.items.gather-insights.text",
          ),
          link: `/${locale}/guides/quick-start/gather-insights`,
        },
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.quick-start.items.optimize-workflows.text",
          ),
          link: `/${locale}/guides/quick-start/optimize-workflows`,
        },
      ],
    },
    {
      text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${localizedString(
        locale,
        "sidebars.guides.items.start.text",
      )} ${cubeOutlineIcon()}</span>`,
      items: [
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.start.items.new-project.text",
          ),
          link: `/${locale}/guides/start/new-project`,
        },
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.start.items.swift-package.text",
          ),
          link: `/${locale}/guides/start/swift-package`,
        },
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.start.items.migrate.text",
          ),
          collapsed: true,
          items: [
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.start.items.migrate.items.xcode-project.text",
              ),
              link: `/${locale}/guides/start/migrate/xcode-project`,
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.start.items.migrate.items.swift-package.text",
              ),
              link: `/${locale}/guides/start/migrate/swift-package`,
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.start.items.migrate.items.xcodegen-project.text",
              ),
              link: `/${locale}/guides/start/migrate/xcodegen-project`,
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.start.items.migrate.items.bazel-project.text",
              ),
              link: `/${locale}/guides/start/migrate/bazel-project`,
            },
          ],
        },
      ],
    },
    {
      text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${localizedString(
        locale,
        "sidebars.guides.items.develop.text",
      )} ${cube02Icon()}</span>`,
      items: [
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.develop.items.projects.text",
          ),
          collapsed: true,
          link: `/${locale}/guides/develop/projects`,
          items: [
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.projects.items.manifests.text",
              ),
              link: `/${locale}/guides/develop/projects/manifests`,
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.projects.items.directory-structure.text",
              ),
              link: `/${locale}/guides/develop/projects/directory-structure`,
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.projects.items.editing.text",
              ),
              link: `/${locale}/guides/develop/projects/editing`,
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.projects.items.dependencies.text",
              ),
              link: `/${locale}/guides/develop/projects/dependencies`,
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.projects.items.code-sharing.text",
              ),
              link: `/${locale}/guides/develop/projects/code-sharing`,
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.projects.items.synthesized-files.text",
              ),
              link: `/${locale}/guides/develop/projects/synthesized-files`,
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.projects.items.dynamic-configuration.text",
              ),
              link: `/${locale}/guides/develop/projects/dynamic-configuration`,
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.projects.items.templates.text",
              ),
              link: `/${locale}/guides/develop/projects/templates`,
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.projects.items.plugins.text",
              ),
              link: `/${locale}/guides/develop/projects/plugins`,
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.projects.items.hashing.text",
              ),
              link: `/${locale}/guides/develop/projects/hashing`,
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.projects.items.the-cost-of-convenience.text",
              ),
              link: `/${locale}/guides/develop/projects/cost-of-convenience`,
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.projects.items.tma-architecture.text",
              ),
              link: `/${locale}/guides/develop/projects/tma-architecture`,
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.projects.items.best-practices.text",
              ),
              link: `/${locale}/guides/develop/projects/best-practices`,
            },
          ],
        },
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.develop.items.build.text",
          ),
          link: `/${locale}/guides/develop/build`,
          collapsed: true,
          items: [
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.build.items.cache.text",
              ),
              link: `/${locale}/guides/develop/build/cache`,
            },
            {
              text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${localizedString(
                locale,
                "sidebars.guides.items.develop.items.build.items.registry.text",
              )} ${xcodeProjCompatibleBadge(locale)}</span>`,
              link: `/${locale}/guides/develop/build/registry`,
            },
          ],
        },
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.develop.items.test.text",
          ),
          link: `/${locale}/guides/develop/test`,
          collapsed: true,
          items: [
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.test.items.smart-runner.text",
              ),
              link: `/${locale}/guides/develop/test/smart-runner`,
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.test.items.flakiness.text",
              ),
              link: `/${locale}/guides/develop/test/flakiness`,
            },
          ],
        },
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.develop.items.inspect.text",
          ),
          collapsed: true,
          items: [
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.inspect.items.implicit-imports.text",
              ),
              link: `/${locale}/guides/develop/inspect/implicit-dependencies`,
            },
          ],
        },
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.develop.items.automate.text",
          ),
          collapsed: true,
          items: [
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.automate.items.continuous-integration.text",
              ),
              link: `/${locale}/guides/develop/automate/continuous-integration`,
            },
            {
              text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${localizedString(
                locale,
                "sidebars.guides.items.develop.items.automate.items.workflows.text",
              )} ${comingSoonBadge(locale)}</span>`,
              link: `/${locale}/guides/develop/automate/workflows`,
            },
          ],
        },
      ],
    },
    {
      text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${localizedString(
        locale,
        "sidebars.guides.items.share.text",
      )} ${cube01Icon()}</span>`,
      items: [
        {
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${localizedString(
            locale,
            "sidebars.guides.items.share.items.previews.text",
          )} ${xcodeProjCompatibleBadge(locale)}</span>`,
          link: `/${locale}/guides/share/previews`,
        },
      ],
    },
  ];
}
