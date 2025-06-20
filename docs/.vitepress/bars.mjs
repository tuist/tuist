import {
  cube02Icon,
  cube01Icon,
  tuistIcon,
  building07Icon,
  server04Icon,
  bookOpen01Icon,
  codeBrowserIcon,
  star06Icon,
  playIcon,
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
      link: `/${locale}/guides/tuist/about`,
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
        {
          text: localizedString(locale, "sidebars.contributors.items.cli.text"),
          collapsed: true,
          items: [
            {
              text: localizedString(
                locale,
                "sidebars.contributors.items.cli.items.logging.text",
              ),
              link: `/${locale}/contributors/cli/logging`,
            },
          ],
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
      link: "https://tuist.dev/api/docs",
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
      text: "Tuist",
      link: `/${locale}/`,
      items: [
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.tuist.items.about.text",
          ),
          link: `/${locale}/guides/tuist/about`,
        },
      ],
    },
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
            "sidebars.guides.items.quick-start.items.get-started.text",
          ),
          link: `/${locale}/guides/quick-start/get-started`,
        },
      ],
    },
    {
      text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${localizedString(
        locale,
        "sidebars.guides.items.features.text",
      )} ${cube02Icon()}</span>`,
      items: [
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.develop.items.generated-projects.text",
          ),
          collapsed: true,
          link: `/${locale}/guides/features/projects`,
          items: [
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.generated-projects.items.adoption.text",
              ),
              collapsed: true,
              items: [
                {
                  text: localizedString(
                    locale,
                    "sidebars.guides.items.develop.items.generated-projects.items.adoption.items.new-project.text",
                  ),
                  link: `/${locale}/guides/features/projects/adoption/new-project`,
                },
                {
                  text: localizedString(
                    locale,
                    "sidebars.guides.items.develop.items.generated-projects.items.adoption.items.swift-package.text",
                  ),
                  link: `/${locale}/guides/features/projects/adoption/swift-package`,
                },
                {
                  text: localizedString(
                    locale,
                    "sidebars.guides.items.develop.items.generated-projects.items.adoption.items.migrate.text",
                  ),
                  collapsed: true,
                  items: [
                    {
                      text: localizedString(
                        locale,
                        "sidebars.guides.items.develop.items.generated-projects.items.adoption.items.migrate.items.xcode-project.text",
                      ),
                      link: `/${locale}/guides/features/projects/adoption/migrate/xcode-project`,
                    },
                    {
                      text: localizedString(
                        locale,
                        "sidebars.guides.items.develop.items.generated-projects.items.adoption.items.migrate.items.swift-package.text",
                      ),
                      link: `/${locale}/guides/features/projects/adoption/migrate/swift-package`,
                    },
                    {
                      text: localizedString(
                        locale,
                        "sidebars.guides.items.develop.items.generated-projects.items.adoption.items.migrate.items.xcodegen-project.text",
                      ),
                      link: `/${locale}/guides/features/projects/adoption/migrate/xcodegen-project`,
                    },
                    {
                      text: localizedString(
                        locale,
                        "sidebars.guides.items.develop.items.generated-projects.items.adoption.items.migrate.items.bazel-project.text",
                      ),
                      link: `/${locale}/guides/features/projects/adoption/migrate/bazel-project`,
                    },
                  ],
                },
              ],
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.generated-projects.items.manifests.text",
              ),
              link: `/${locale}/guides/features/projects/manifests`,
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.generated-projects.items.directory-structure.text",
              ),
              link: `/${locale}/guides/features/projects/directory-structure`,
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.generated-projects.items.editing.text",
              ),
              link: `/${locale}/guides/features/projects/editing`,
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.generated-projects.items.dependencies.text",
              ),
              link: `/${locale}/guides/features/projects/dependencies`,
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.generated-projects.items.code-sharing.text",
              ),
              link: `/${locale}/guides/features/projects/code-sharing`,
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.generated-projects.items.synthesized-files.text",
              ),
              link: `/${locale}/guides/features/projects/synthesized-files`,
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.generated-projects.items.dynamic-configuration.text",
              ),
              link: `/${locale}/guides/features/projects/dynamic-configuration`,
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.generated-projects.items.templates.text",
              ),
              link: `/${locale}/guides/features/projects/templates`,
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.generated-projects.items.plugins.text",
              ),
              link: `/${locale}/guides/features/projects/plugins`,
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.generated-projects.items.hashing.text",
              ),
              link: `/${locale}/guides/features/projects/hashing`,
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.generated-projects.items.inspect.text",
              ),
              collapsed: true,
              items: [
                {
                  text: localizedString(
                    locale,
                    "sidebars.guides.items.develop.items.generated-projects.items.inspect.items.implicit-imports.text",
                  ),
                  link: `/${locale}/guides/features/projects/inspect/implicit-dependencies`,
                },
              ],
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.generated-projects.items.the-cost-of-convenience.text",
              ),
              link: `/${locale}/guides/features/projects/cost-of-convenience`,
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.generated-projects.items.tma-architecture.text",
              ),
              link: `/${locale}/guides/features/projects/tma-architecture`,
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.generated-projects.items.best-practices.text",
              ),
              link: `/${locale}/guides/features/projects/best-practices`,
            },
          ],
        },
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.develop.items.cache.text",
          ),
          link: `/${locale}/guides/features/cache`,
        },
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.develop.items.selective-testing.text",
          ),
          link: `/${locale}/guides/features/selective-testing`,
          collapsed: true,
          items: [
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.selective-testing.items.xcode-project.text",
              ),
              link: `/${locale}/guides/features/selective-testing/xcode-project`,
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.selective-testing.items.generated-project.text",
              ),
              link: `/${locale}/guides/features/selective-testing/generated-project`,
            },
          ],
        },
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.develop.items.registry.text",
          ),
          link: `/${locale}/guides/features/registry`,
          collapsed: true,
          items: [
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.registry.items.xcode-project.text",
              ),
              link: `/${locale}/guides/features/registry/xcode-project`,
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.registry.items.generated-project.text",
              ),
              link: `/${locale}/guides/features/registry/generated-project`,
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.registry.items.xcodeproj-integration.text",
              ),
              link: `/${locale}/guides/features/registry/xcodeproj-integration`,
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.registry.items.swift-package.text",
              ),
              link: `/${locale}/guides/features/registry/swift-package`,
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.registry.items.continuous-integration.text",
              ),
              link: `/${locale}/guides/features/registry/continuous-integration`,
            },
          ],
        },
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.develop.items.insights.text",
          ),
          link: `/${locale}/guides/features/insights`,
        },
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.develop.items.bundle-size.text",
          ),
          link: `/${locale}/guides/features/bundle-size`,
        },
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.ai.items.mcp.text",
          ),
          link: `/${locale}/guides/features/mcp`,
        },
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.share.items.previews.text",
          ),
          link: `/${locale}/guides/features/previews`,
        },
      ],
    },
    {
      text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${localizedString(
        locale,
        "sidebars.guides.items.environments.text",
      )} ${playIcon()}</span>`,
      items: [
        {
          text: localizedString(
            locale,
            "sidebars.guides.items.environments.items.continuous-integration.text",
          ),
          link: `/${locale}/guides/environments/continuous-integration`,
        },
      ],
    },
  ];
}
