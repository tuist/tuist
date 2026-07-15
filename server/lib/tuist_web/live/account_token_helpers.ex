defmodule TuistWeb.AccountTokenHelpers do
  @moduledoc false

  use Gettext, backend: TuistWeb.Gettext

  alias Tuist.Accounts.AccountToken
  alias Tuist.Authorization.Checks
  alias Tuist.Utilities.DateFormatter

  def scope_options do
    [
      %{
        key: "presets",
        label: dgettext("dashboard_account", "Presets"),
        scopes: [
          %{
            scope: "ci",
            label: dgettext("dashboard_account", "CI"),
            description:
              dgettext(
                "dashboard_account",
                "Cache writes, previews, bundles, tests, builds, and runs for CI jobs."
              )
          }
        ]
      },
      %{
        key: "account",
        label: dgettext("dashboard_account", "Account"),
        scopes: [
          %{
            scope: "account:cache:read",
            label: dgettext("dashboard_account", "Cache read"),
            description: dgettext("dashboard_account", "Read account-level cache entries.")
          },
          %{
            scope: "account:cache:write",
            label: dgettext("dashboard_account", "Cache write"),
            description: dgettext("dashboard_account", "Read and write account-level cache entries.")
          },
          %{
            scope: "account:members:read",
            label: dgettext("dashboard_account", "Members read"),
            description: dgettext("dashboard_account", "Read organization members and invitations.")
          },
          %{
            scope: "account:members:write",
            label: dgettext("dashboard_account", "Members write"),
            description: dgettext("dashboard_account", "Manage organization members and invitations.")
          },
          %{
            scope: "account:registry:read",
            label: dgettext("dashboard_account", "Registry read"),
            description: dgettext("dashboard_account", "Read packages from the account registry.")
          },
          %{
            scope: "account:registry:write",
            label: dgettext("dashboard_account", "Registry write"),
            description: dgettext("dashboard_account", "Publish packages to the account registry.")
          },
          %{
            scope: "account:scim:write",
            label: dgettext("dashboard_account", "SCIM write"),
            description: dgettext("dashboard_account", "Provision organization members through SCIM.")
          }
        ]
      },
      %{
        key: "project",
        label: dgettext("dashboard_account", "Project"),
        scopes: [
          %{
            scope: "project:admin:read",
            label: dgettext("dashboard_account", "Admin read"),
            description: dgettext("dashboard_account", "Read project administration data.")
          },
          %{
            scope: "project:admin:write",
            label: dgettext("dashboard_account", "Admin write"),
            description: dgettext("dashboard_account", "Manage project administration data.")
          },
          %{
            scope: "project:cache:read",
            label: dgettext("dashboard_account", "Cache read"),
            description: dgettext("dashboard_account", "Read project cache entries.")
          },
          %{
            scope: "project:cache:write",
            label: dgettext("dashboard_account", "Cache write"),
            description: dgettext("dashboard_account", "Read and write project cache entries.")
          },
          %{
            scope: "project:previews:read",
            label: dgettext("dashboard_account", "Previews read"),
            description: dgettext("dashboard_account", "Read previews.")
          },
          %{
            scope: "project:previews:write",
            label: dgettext("dashboard_account", "Previews write"),
            description: dgettext("dashboard_account", "Create and manage previews.")
          },
          %{
            scope: "project:bundles:read",
            label: dgettext("dashboard_account", "Bundles read"),
            description: dgettext("dashboard_account", "Read bundle analytics.")
          },
          %{
            scope: "project:bundles:write",
            label: dgettext("dashboard_account", "Bundles write"),
            description: dgettext("dashboard_account", "Upload and manage bundle data.")
          },
          %{
            scope: "project:tests:read",
            label: dgettext("dashboard_account", "Tests read"),
            description: dgettext("dashboard_account", "Read test analytics.")
          },
          %{
            scope: "project:tests:write",
            label: dgettext("dashboard_account", "Tests write"),
            description: dgettext("dashboard_account", "Upload and manage test data.")
          },
          %{
            scope: "project:builds:read",
            label: dgettext("dashboard_account", "Builds read"),
            description: dgettext("dashboard_account", "Read build analytics.")
          },
          %{
            scope: "project:builds:write",
            label: dgettext("dashboard_account", "Builds write"),
            description: dgettext("dashboard_account", "Upload and manage build data.")
          },
          %{
            scope: "project:runs:read",
            label: dgettext("dashboard_account", "Runs read"),
            description: dgettext("dashboard_account", "Read runs.")
          },
          %{
            scope: "project:runs:write",
            label: dgettext("dashboard_account", "Runs write"),
            description: dgettext("dashboard_account", "Create and manage runs.")
          }
        ]
      }
    ]
  end

  def scopes_label(scopes), do: Enum.join(scopes, ", ")

  def selected_scope_groups(scopes) do
    scope_options()
    |> Enum.map(fn group ->
      %{group | scopes: Enum.filter(group.scopes, &(&1.scope in scopes))}
    end)
    |> Enum.reject(&Enum.empty?(&1.scopes))
  end

  def permission_rows(scopes) do
    scope_options_by_scope =
      scope_options()
      |> Enum.flat_map(& &1.scopes)
      |> Enum.reject(&(&1.scope in ["ci", "mcp"]))
      |> Map.new(&{&1.scope, &1})

    scopes
    |> Checks.expand_scopes()
    |> Enum.uniq()
    |> Enum.map(fn scope ->
      Map.get(scope_options_by_scope, scope, %{scope: scope, label: scope, description: ""})
    end)
  end

  def project_handle(account, project), do: "#{account.name}/#{project.name}"

  def account_token_hint(%AccountToken{id: id, scopes: scopes}) do
    prefix =
      if AccountToken.scim_scope() in scopes do
        "tuist_scim_"
      else
        "tuist_"
      end

    prefix <> String.slice(id, 0, 8) <> String.duplicate("•", 6)
  end

  def expires_label(%AccountToken{expires_at: nil}), do: dgettext("dashboard_account", "Never")

  def expires_label(%AccountToken{expires_at: expires_at}), do: DateFormatter.from_now(expires_at)

  def last_used_label(%AccountToken{last_used_at: nil}), do: dgettext("dashboard_account", "Never")

  def last_used_label(%AccountToken{last_used_at: last_used_at}), do: DateFormatter.from_now(last_used_at)

  def created_label(%AccountToken{inserted_at: inserted_at}), do: DateFormatter.from_now(inserted_at)

  def created_by_label(%AccountToken{created_by_account: %{name: name}}) when is_binary(name), do: name

  def created_by_label(_account_token), do: dgettext("dashboard_account", "Unknown")
end
