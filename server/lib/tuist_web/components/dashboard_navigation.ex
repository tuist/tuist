defmodule TuistWeb.DashboardNavigation do
  @moduledoc false
  use TuistWeb, :verified_routes
  use Gettext, backend: TuistWeb.Gettext

  alias Tuist.Accounts
  alias Tuist.Authorization
  alias Tuist.FeatureFlags
  alias Tuist.Projects.Project
  alias TuistWeb.API.BuildEntityResources
  alias TuistWeb.Helpers.BuildEntityLabels

  # Shared by the account sidebar and global search, including on project pages.
  def account(user, account) do
    root = "/#{account.name}"
    admin? = Authorization.authorize(:account_update, user, account) == :ok

    Enum.reject(
      [
        item(dgettext("dashboard", "Projects"), root <> "/projects", "folders"),
        group(
          FeatureFlags.runners_enabled?(account),
          "sidebar-runners",
          dgettext("dashboard", "Runners"),
          root <> "/runners",
          "server",
          [
            item(dgettext("dashboard", "Workflows"), root <> "/runners/workflows", "versions"),
            item(dgettext("dashboard", "Jobs"), root <> "/runners/jobs", "stack_2"),
            item(dgettext("dashboard_runners", "Volumes"), root <> "/runners/volumes", "database"),
            item(
              dgettext("dashboard", "Profiles"),
              root <> "/runners/profiles",
              "category",
              Authorization.authorize(:runners_update, user, account) == :ok
            )
          ]
        ),
        group(
          FeatureFlags.sandboxes_enabled?(account) and Authorization.authorize(:sandboxes_read, user, account) == :ok,
          "sidebar-sandboxes",
          dgettext("dashboard_sandboxes", "Sandboxes"),
          root <> "/sandboxes",
          "box_model_2",
          [item(dgettext("dashboard_sandboxes", "Instances"), root <> "/sandboxes/instances", "stack_2")]
        ),
        item(
          dgettext("dashboard", "Members"),
          root <> "/members",
          "users",
          Accounts.organization?(account) and Authorization.authorize(:organization_read, user, account) == :ok
        ),
        group(Tuist.Pulse.authorized?(user, account), "sidebar-pulse", "Pulse", nil, "chart_arcs", [
          item(dgettext("dashboard", "Metrics"), root <> "/~/pulse/metrics", "chart_arcs"),
          item(dgettext("dashboard", "Logs"), root <> "/~/pulse/logs", "file_text"),
          item(dgettext("dashboard", "Traces"), root <> "/~/pulse/traces", "list_tree"),
          item(
            dgettext("dashboard", "Errors"),
            root <> "/~/pulse/errors",
            "alert_circle",
            Tuist.Pulse.errors_available?()
          )
        ]),
        item(dgettext("dashboard", "Webhooks"), root <> "/webhooks", "webhook", admin?),
        item(dgettext("dashboard", "Cache"), root <> "/cache", "database", admin?),
        item(dgettext("dashboard", "Billing"), root <> "/billing", "credit_card", admin?),
        item(dgettext("dashboard", "Usage"), root <> "/usage", "chart_column"),
        item(dgettext("dashboard", "Settings"), root <> "/settings", "settings", admin?)
      ],
      &is_nil/1
    )
  end

  def pages(user, account, project) do
    settings = "/#{account.name}/settings"

    account_pages =
      user
      |> account(account)
      |> Enum.flat_map(&flatten(&1, dgettext("dashboard", "Account: %{name}", name: account.name)))
      |> Enum.map(fn page ->
        if page.path == settings, do: %{page | title: dgettext("dashboard", "Account Settings")}, else: page
      end)

    admin? = Authorization.authorize(:account_update, user, account) == :ok

    account_settings = [
      page(
        dgettext("dashboard", "Account Tokens"),
        settings <> "/tokens",
        dgettext("dashboard", "Manage account API keys"),
        Authorization.authorize(:account_token_read, user, account) == :ok
      ),
      page(
        dgettext("dashboard", "Account Integrations"),
        settings <> "/integrations",
        dgettext("dashboard", "Connect repositories and CI providers"),
        admin?,
        "GitHub Origin GitLab Buildkite Amp settings"
      ),
      page(
        dgettext("dashboard", "Account Authentication"),
        settings <> "/authentication",
        dgettext("dashboard", "Manage SSO, SCIM and sign-in security"),
        admin?,
        "OIDC workload identities passkeys two-factor MFA settings"
      ),
      page(
        dgettext("dashboard", "Account AI"),
        if(Accounts.organization?(account), do: settings <> "/ai/routing", else: settings <> "/ai"),
        dgettext("dashboard", "Manage AI subscriptions and routing"),
        if(Accounts.organization?(account),
          do: admin? and FeatureFlags.organization_ai_enabled?(account),
          else: account.user_id == user.id and FeatureFlags.ai_enabled?(user)
        )
      )
    ]

    Enum.reject(account_pages ++ account_settings ++ project_pages(user, account, project), &is_nil/1)
  end

  def project_pages(user, account, project, opts \\ [])
  def project_pages(_user, _account, nil, _opts), do: []

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def project_pages(user, account, project, opts) do
    root = "/#{account.name}/#{project.name}"
    once? = Project.once_project?(project)
    build_root = if once?, do: "/once/builds", else: "/builds"
    test_root = if once?, do: "/once/tests", else: "/tests"
    resources = BuildEntityResources.for_project(project)

    pages = [
      page(dgettext("dashboard", "Overview"), root, project.name),
      page(dgettext("dashboard", "Builds"), root <> build_root, project.name),
      page(
        dgettext("dashboard", "Build Runs"),
        root <> if(once?, do: "/once/build-runs", else: "/builds/build-runs"),
        project.name
      ),
      page(dgettext("dashboard", "Tests"), root <> test_root, project.name),
      page(
        dgettext("dashboard", "Test Runs"),
        root <> if(once?, do: "/once/test-runs", else: "/tests/test-runs"),
        project.name
      ),
      page(dgettext("dashboard", "Test Cases"), root <> "/tests/test-cases", project.name),
      page(dgettext("dashboard", "Flaky Tests"), root <> "/tests/flaky-tests", project.name),
      page(dgettext("dashboard", "Quarantined Tests"), root <> "/tests/quarantined-tests", project.name),
      page(
        dgettext("dashboard", "Shards"),
        root <> "/tests/shards",
        project.name,
        project.build_system in [:xcode, :mix, :cargo, :once]
      ),
      page(
        dgettext("dashboard", "Code Coverage"),
        root <> "/tests/coverage",
        project.name,
        project.build_system in [:xcode, :mix] and FeatureFlags.coverage_enabled?(account, project)
      ),
      page(
        dgettext("dashboard", "Test Selection"),
        root <> "/tests/test-selection",
        project.name,
        TuistWeb.TestSelectionsLive.enabled?(account, project)
      ),
      page(
        dgettext("dashboard", "Tasks"),
        root <> "/builds/tasks",
        project.name,
        Project.gradle_project?(project) and not Enum.any?(resources, &(&1.key == :gradle_tasks))
      ),
      page(dgettext("dashboard", "Bazel Cache"), root <> "/bazel-cache", project.name, Project.bazel_project?(project)),
      page(dgettext("dashboard", "Once Cache"), root <> "/once-cache", project.name, once?),
      page(dgettext("dashboard", "Cargo Cache"), root <> "/cargo-cache", project.name, Project.cargo_project?(project)),
      page(dgettext("dashboard", "Mix Cache"), root <> "/mix-cache", project.name, Project.mix_project?(project)),
      page(dgettext("dashboard", "Xcode Cache"), root <> "/xcode-cache", project.name, Project.xcode_project?(project)),
      page(
        dgettext("dashboard", "Gradle Cache"),
        root <> "/gradle-cache",
        project.name,
        Project.gradle_project?(project)
      ),
      page(dgettext("dashboard", "Module Cache"), root <> "/module-cache", project.name, Project.xcode_project?(project)),
      page(
        dgettext("dashboard", "Cache Runs"),
        root <> "/module-cache/cache-runs",
        project.name,
        Project.xcode_project?(project)
      ),
      page(
        dgettext("dashboard", "Generations"),
        root <> "/module-cache/generate-runs",
        project.name,
        Project.xcode_project?(project)
      ),
      page(
        dgettext("dashboard", "Modules"),
        root <> "/module-cache/modules",
        project.name,
        Project.xcode_project?(project)
      ),
      page(dgettext("dashboard", "Previews"), root <> "/previews", project.name, Project.supports_previews?(project)),
      page(dgettext("dashboard", "Bundles"), root <> "/bundles", project.name, Project.supports_bundles?(project))
    ]

    entity_pages =
      Enum.map(resources, &page(BuildEntityLabels.plural(&1.system, &1.kind), root <> &1.path, project.name))

    admin? =
      Keyword.get_lazy(opts, :project_admin?, fn -> Authorization.authorize(:project_update, user, project) == :ok end)

    (pages ++ entity_pages ++ project_settings(account, project, admin?))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(fn page ->
      # Once's native routes differ, but these destinations mean the same thing.
      destination =
        page.path
        |> String.replace_prefix(root, "")
        |> then(fn
          "/once/builds" -> "/builds"
          "/once/build-runs" -> "/builds/build-runs"
          "/once/tests" -> "/tests"
          "/once/test-runs" -> "/tests/test-runs"
          path -> path
        end)

      section = project_section(destination)
      description = if String.downcase(section) == String.downcase(page.title), do: "", else: section

      hierarchy =
        cond do
          String.starts_with?(destination, "/settings/") -> dgettext("dashboard", "Settings")
          length(String.split(destination, "/", trim: true)) > 1 -> section
          true -> nil
        end

      title =
        case destination do
          "/settings" -> dgettext("dashboard", "Settings")
          "/settings/integrations" -> dgettext("dashboard", "Integrations")
          "/settings/notifications" -> dgettext("dashboard", "Notifications")
          "/settings/automations" -> dgettext("dashboard", "Automations")
          "/settings/bundles" -> dgettext("dashboard", "Bundles")
          _ -> page.title
        end

      icon =
        case destination do
          "" -> "smart_home"
          "/builds" -> "versions"
          "/builds/build-runs" -> "chart_column"
          "/tests" -> "subtask"
          "/tests/test-runs" -> "dashboard"
          "/tests/test-cases" -> "exchange"
          "/tests/flaky-tests" -> "progress_x"
          "/tests/quarantined-tests" -> "lock"
          "/tests/shards" -> "stack_2"
          "/tests/coverage" -> "umbrella"
          "/tests/test-selection" -> "filter"
          "/module-cache" -> "database"
          "/module-cache/cache-runs" -> "schema"
          "/module-cache/generate-runs" -> "filters"
          "/module-cache/modules" -> "apps"
          "/previews" -> "devices"
          "/bundles" -> "package"
          "/settings" <> _ -> "settings"
          "/" <> cache when cache in ~w(bazel-cache once-cache cargo-cache mix-cache xcode-cache gradle-cache) -> "server"
          _ -> "subtask"
        end

      Map.merge(page, %{
        title: title,
        keywords: String.trim("#{page.keywords} #{page.title}"),
        destination: destination,
        project: project.name,
        description: description,
        hierarchy: hierarchy,
        icon: icon
      })
    end)
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp project_section(destination) do
    case String.split(destination, "/", trim: true) do
      [] -> dgettext("dashboard", "Build and test insights")
      ["settings", "integrations"] -> dgettext("dashboard", "Connect this project to a repository")
      ["settings", "notifications"] -> dgettext("dashboard", "Configure project notifications")
      ["settings", "automations"] -> dgettext("dashboard", "Configure automated project workflows")
      ["settings", "bundles"] -> dgettext("dashboard", "Configure app bundle analysis")
      ["settings" | _] -> dgettext("dashboard", "Project settings")
      ["tests" | _] -> dgettext("dashboard", "Tests")
      ["builds" | _] -> dgettext("dashboard", "Builds")
      ["module-cache" | _] -> dgettext("dashboard", "Module Cache")
      ["previews" | _] -> dgettext("dashboard", "App previews")
      ["bundles" | _] -> dgettext("dashboard", "App size analysis")
      _ -> dgettext("dashboard", "Compilation cache")
    end
  end

  defp project_settings(account, project, admin?) do
    if admin? do
      root = "/#{account.name}/#{project.name}/settings"

      [
        page(dgettext("dashboard", "Project Settings"), root, project.name),
        page(dgettext("dashboard", "Project Integrations"), root <> "/integrations", project.name),
        page(
          dgettext("dashboard", "Project Notifications"),
          root <> "/notifications",
          project.name,
          Project.xcode_project?(project)
        ),
        page(
          dgettext("dashboard", "Project Automations"),
          root <> "/automations",
          project.name,
          project.build_system in [:xcode, :bazel, :mix, :cargo]
        ),
        page(
          dgettext("dashboard", "Bundle Settings"),
          root <> "/bundles",
          project.name,
          Project.supports_bundles?(project)
        )
      ]
    else
      []
    end
  end

  defp item(title, path, icon, enabled? \\ true)
  defp item(title, path, icon, true), do: %{title: title, path: path, icon: icon, children: [], id: nil}
  defp item(_, _, _, false), do: nil

  defp group(true, id, title, path, icon, children),
    do: %{id: id, title: title, path: path, icon: icon, children: Enum.reject(children, &is_nil/1)}

  defp group(false, _, _, _, _, _), do: nil

  defp page(title, path, description, enabled? \\ true, keywords \\ "")

  defp page(title, path, description, true, keywords),
    do: %{title: title, path: path, description: description, keywords: keywords}

  defp page(_, _, _, false, _), do: nil

  defp flatten(item, context, hierarchy \\ nil) do
    own =
      if item.path,
        do: [Map.merge(page(item.title, item.path, context), %{icon: item.icon, hierarchy: hierarchy})],
        else: []

    own ++ Enum.flat_map(item.children, &flatten(&1, "#{context} · #{item.title}", item.title))
  end
end
