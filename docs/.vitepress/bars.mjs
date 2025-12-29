import {
  bookOpen01Icon,
  codeBrowserIcon,
  cacheIcon,
  testIcon,
  registryIcon,
  insightsIcon,
  bundleSizeIcon,
  previewsIcon,
  projectsIcon,
  mcpIcon,
  ciIcon,
  githubIcon,
  ssoIcon,
  accountsIcon,
  authIcon,
  installIcon,
  telemetryIcon,
  gitForgesIcon,
  selfHostingIcon,
  installTuistIcon,
  getStartedIcon,
  agenticBuildingIcon,
  qaIcon,
  slackIcon,
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
          link: `/${locale}/references/examples`,
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
          text: localizedString(
            locale,
            "sidebars.contributors.items.releases.text",
          ),
          link: `/${locale}/contributors/releases`,
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

export async function guidesSidebar(locale) {
  return [
    {
      text: localizedString(locale, "sidebars.guides.items.quick-start.text"),
      items: [
        {
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${installTuistIcon()} ${localizedString(
            locale,
            "sidebars.guides.items.quick-start.items.install-tuist.text",
          )}</span>`,
          link: `/${locale}/guides/quick-start/install-tuist`,
        },
        {
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${getStartedIcon()} ${localizedString(
            locale,
            "sidebars.guides.items.quick-start.items.get-started.text",
          )}</span>`,
          link: `/${locale}/guides/quick-start/get-started`,
        },
      ],
    },
    {
      text: localizedString(locale, "sidebars.guides.items.features.text"),
      items: [
        {
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${projectsIcon()} ${localizedString(
            locale,
            "sidebars.guides.items.develop.items.generated-projects.text",
          )}</span>`,
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
                "sidebars.guides.items.develop.items.generated-projects.items.metadata-tags.text",
              ),
              link: `/${locale}/guides/features/projects/metadata-tags`,
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
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${cacheIcon()} ${localizedString(
            locale,
            "sidebars.guides.items.develop.items.cache.text",
          )}</span>`,
          link: `/${locale}/guides/features/cache`,
          collapsed: true,
          items: [
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.cache.items.xcode-cache.text",
              ),
              link: `/${locale}/guides/features/cache/xcode-cache`,
            },
            {
              text: localizedString(
                locale,
                "sidebars.guides.items.develop.items.cache.items.module-cache.text",
              ),
              link: `/${locale}/guides/features/cache/module-cache`,
            },
          ],
        },
        {
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${testIcon()} ${localizedString(
            locale,
            "sidebars.guides.items.develop.items.selective-testing.text",
          )}</span>`,
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
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${registryIcon()} ${localizedString(
            locale,
            "sidebars.guides.items.develop.items.registry.text",
          )}</span>`,
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
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${insightsIcon()} ${localizedString(
            locale,
            "sidebars.guides.items.develop.items.insights.text",
          )}</span>`,
          link: `/${locale}/guides/features/insights`,
        },
        {
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${bundleSizeIcon()} ${localizedString(
            locale,
            "sidebars.guides.items.develop.items.bundle-size.text",
          )}</span>`,
          link: `/${locale}/guides/features/bundle-size`,
        },
        {
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${qaIcon()} ${localizedString(
            locale,
            "sidebars.guides.items.develop.items.qa.text",
          )}</span>`,
          link: `/${locale}/guides/features/qa`,
        },
        {
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${previewsIcon()} ${localizedString(
            locale,
            "sidebars.guides.items.share.items.previews.text",
          )}</span>`,
          link: `/${locale}/guides/features/previews`,
        },
        {
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${agenticBuildingIcon()} ${localizedString(
            locale,
            "sidebars.guides.items.agentic-coding.text",
          )}</span>`,
          collapsed: true,
          items: [
            {
              text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${mcpIcon()} ${localizedString(
                locale,
                "sidebars.guides.items.agentic-coding.items.mcp.text",
              )}</span>`,
              link: `/${locale}/guides/features/agentic-coding/mcp`,
            },
          ],
        },
      ],
    },
    {
      text: localizedString(locale, "sidebars.guides.items.examples.text"),
      items: [
        {
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${codeBrowserIcon()} ${localizedString(
            locale,
            "sidebars.guides.items.examples.items.generated-projects.text",
          )}</span>`,
          link: `/${locale}/guides/examples/generated-projects`,
          collapsed: true,
          items: (await loadExamplesData()).map((item) => {
            return {
              text: item.title,
              link: `/${locale}/guides/examples/generated-projects/${item.name}`,
            };
          }),
        },
      ],
    },
    {
      text: localizedString(locale, "sidebars.guides.items.integrations.text"),
      items: [
        {
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${ciIcon()} ${localizedString(
            locale,
            "sidebars.guides.items.integrations.items.continuous-integration.text",
          )}</span>`,
          link: `/${locale}/guides/integrations/continuous-integration`,
        },
        {
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${ssoIcon()} ${localizedString(
            locale,
            "sidebars.guides.items.integrations.items.sso.text",
          )}</span>`,
          link: `/${locale}/guides/integrations/sso`,
        },
        {
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${slackIcon()} ${localizedString(
            locale,
            "sidebars.guides.items.integrations.items.slack.text",
          )}</span>`,
          link: `/${locale}/guides/integrations/slack`,
        },
        {
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${gitForgesIcon()} ${localizedString(
            locale,
            "sidebars.guides.items.integrations.items.git-forges.text",
          )}</span>`,
          collapsed: true,
          items: [
            {
              text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${githubIcon()} ${localizedString(
                locale,
                "sidebars.guides.items.integrations.items.git-forges.items.github.text",
              )}</span>`,
              link: `/${locale}/guides/integrations/gitforge/github`,
            },
          ],
        },
      ],
    },
    {
      text: localizedString(locale, "sidebars.guides.items.server.text"),
      items: [
        {
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${accountsIcon()} ${localizedString(
            locale,
            "sidebars.guides.items.server.items.accounts-and-projects.text",
          )}</span>`,
          link: `/${locale}/guides/server/accounts-and-projects`,
        },
        {
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${authIcon()} ${localizedString(
            locale,
            "sidebars.guides.items.server.items.authentication.text",
          )}</span>`,
          link: `/${locale}/guides/server/authentication`,
        },
        {
          text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${selfHostingIcon()} ${localizedString(
            locale,
            "sidebars.guides.items.server.items.self-hosting.text",
          )}</span>`,
          collapsed: true,
          items: [
            {
              text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${installIcon()} ${localizedString(
                locale,
                "sidebars.guides.items.server.items.self-hosting.items.installation.text",
              )}</span>`,
              link: `/${locale}/guides/server/self-host/install`,
            },
            {
              text: `<span style="display: flex; flex-direction: row; align-items: center; gap: 7px;">${telemetryIcon()} ${localizedString(
                locale,
                "sidebars.guides.items.server.items.self-hosting.items.telemetry.text",
              )}</span>`,
              link: `/${locale}/guides/server/self-host/telemetry`,
            },
          ],
        },
      ],
    },
  ];
}
