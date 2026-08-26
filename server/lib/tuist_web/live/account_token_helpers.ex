defmodule TuistWeb.AccountTokenHelpers do
  @moduledoc false

  use Gettext, backend: TuistWeb.Gettext

  alias Tuist.Accounts.AccountToken
  alias Tuist.Utilities.DateFormatter

  @ci_scope AccountToken.ci_scope()

  def scope_options do
    user_creatable_scopes = AccountToken.user_creatable_scopes()

    [
      %{
        key: "presets",
        label: dgettext("dashboard_account", "Presets"),
        scopes:
          user_creatable_scopes
          |> Enum.filter(&AccountToken.preset_scope?/1)
          |> Enum.map(&scope_option/1)
      },
      %{
        key: "account",
        label: dgettext("dashboard_account", "Account"),
        scopes: scope_options_for_entity(user_creatable_scopes, "account")
      },
      %{
        key: "project",
        label: dgettext("dashboard_account", "Project"),
        scopes: scope_options_for_entity(user_creatable_scopes, "project")
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
    scope_options = scope_options()

    scope_options_by_scope =
      scope_options
      |> Enum.flat_map(& &1.scopes)
      |> Enum.reject(&AccountToken.preset_scope?(&1.scope))
      |> Map.new(&{&1.scope, &1})

    scope_order =
      scope_options
      |> Enum.flat_map(& &1.scopes)
      |> Enum.map(& &1.scope)
      |> Enum.with_index()
      |> Map.new()

    scopes
    |> AccountToken.expand_scopes()
    |> with_implied_read_scopes()
    |> Enum.sort_by(&Map.get(scope_order, &1, 999))
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

  defp scope_options_for_entity(scopes, entity) do
    scopes
    |> Enum.filter(&match_scope_entity?(&1, entity))
    |> Enum.map(&scope_option/1)
  end

  defp match_scope_entity?(scope, entity) do
    case String.split(scope, ":", parts: 3) do
      [^entity, _subject, _access] -> true
      _ -> false
    end
  end

  defp scope_option(@ci_scope) do
    %{
      scope: @ci_scope,
      label: dgettext("dashboard_account", "CI"),
      description:
        dgettext(
          "dashboard_account",
          "Cache writes, previews, bundles, tests, builds, and runs for CI jobs."
        )
    }
  end

  defp scope_option(scope) do
    case String.split(scope, ":", parts: 3) do
      [entity, subject, access] ->
        %{
          scope: scope,
          label: scope_label(subject, access),
          description: scope_description(entity, subject, access)
        }

      _ ->
        %{scope: scope, label: scope, description: ""}
    end
  end

  defp scope_label("admin", "read"), do: dgettext("dashboard_account", "Admin read")
  defp scope_label("admin", "write"), do: dgettext("dashboard_account", "Admin write")
  defp scope_label("builds", "read"), do: dgettext("dashboard_account", "Builds read")
  defp scope_label("builds", "write"), do: dgettext("dashboard_account", "Builds write")
  defp scope_label("bundles", "read"), do: dgettext("dashboard_account", "Bundles read")
  defp scope_label("bundles", "write"), do: dgettext("dashboard_account", "Bundles write")
  defp scope_label("cache", "read"), do: dgettext("dashboard_account", "Cache read")
  defp scope_label("cache", "write"), do: dgettext("dashboard_account", "Cache write")
  defp scope_label("members", "read"), do: dgettext("dashboard_account", "Members read")
  defp scope_label("members", "write"), do: dgettext("dashboard_account", "Members write")
  defp scope_label("previews", "read"), do: dgettext("dashboard_account", "Previews read")
  defp scope_label("previews", "write"), do: dgettext("dashboard_account", "Previews write")
  defp scope_label("registry", "read"), do: dgettext("dashboard_account", "Registry read")
  defp scope_label("registry", "write"), do: dgettext("dashboard_account", "Registry write")
  defp scope_label("runs", "read"), do: dgettext("dashboard_account", "Runs read")
  defp scope_label("runs", "write"), do: dgettext("dashboard_account", "Runs write")
  defp scope_label("tests", "read"), do: dgettext("dashboard_account", "Tests read")
  defp scope_label("tests", "write"), do: dgettext("dashboard_account", "Tests write")
  defp scope_label(subject, access), do: "#{String.capitalize(subject)} #{access}"

  defp scope_description("account", "cache", "read") do
    dgettext("dashboard_account", "Read account-level cache entries.")
  end

  defp scope_description("account", "cache", "write") do
    dgettext("dashboard_account", "Read and write account-level cache entries.")
  end

  defp scope_description("account", "members", "read") do
    dgettext("dashboard_account", "Read organization members and invitations.")
  end

  defp scope_description("account", "members", "write") do
    dgettext("dashboard_account", "Manage organization members and invitations.")
  end

  defp scope_description("account", "registry", "read") do
    dgettext("dashboard_account", "Read packages from the account registry.")
  end

  defp scope_description("account", "registry", "write") do
    dgettext("dashboard_account", "Publish packages to the account registry.")
  end

  defp scope_description("project", "admin", "read") do
    dgettext("dashboard_account", "Read project administration data.")
  end

  defp scope_description("project", "admin", "write") do
    dgettext("dashboard_account", "Manage project administration data.")
  end

  defp scope_description("project", "cache", "read") do
    dgettext("dashboard_account", "Read project cache entries.")
  end

  defp scope_description("project", "cache", "write") do
    dgettext("dashboard_account", "Read and write project cache entries.")
  end

  defp scope_description("project", "previews", "read") do
    dgettext("dashboard_account", "Read previews.")
  end

  defp scope_description("project", "previews", "write") do
    dgettext("dashboard_account", "Create and manage previews.")
  end

  defp scope_description("project", "bundles", "read") do
    dgettext("dashboard_account", "Read bundle analytics.")
  end

  defp scope_description("project", "bundles", "write") do
    dgettext("dashboard_account", "Upload and manage bundle data.")
  end

  defp scope_description("project", "tests", "read") do
    dgettext("dashboard_account", "Read test analytics.")
  end

  defp scope_description("project", "tests", "write") do
    dgettext("dashboard_account", "Upload and manage test data.")
  end

  defp scope_description("project", "builds", "read") do
    dgettext("dashboard_account", "Read build analytics.")
  end

  defp scope_description("project", "builds", "write") do
    dgettext("dashboard_account", "Upload and manage build data.")
  end

  defp scope_description("project", "runs", "read") do
    dgettext("dashboard_account", "Read runs.")
  end

  defp scope_description("project", "runs", "write") do
    dgettext("dashboard_account", "Create and manage runs.")
  end

  defp scope_description(_entity, _subject, _access), do: ""

  defp with_implied_read_scopes(scopes) do
    read_scopes =
      scopes
      |> Enum.map(&read_scope_for_write_scope/1)
      |> Enum.reject(&is_nil/1)

    scopes
    |> Enum.concat(read_scopes)
    |> Enum.filter(&(&1 in AccountToken.valid_scopes()))
    |> Enum.uniq()
  end

  defp read_scope_for_write_scope(scope) do
    case String.split(scope, ":") do
      [entity, subject, "write"] -> "#{entity}:#{subject}:read"
      _ -> nil
    end
  end
end
