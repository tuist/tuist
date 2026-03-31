defmodule TuistWeb.AccountProjectBreadcrumbs do
  @moduledoc """
  Shared helpers for building account and project breadcrumb data.
  Used by both the dashboard layout and the docs layout.
  """
  use TuistWeb, :verified_routes
  use Gettext, backend: TuistWeb.Gettext

  alias Tuist.Accounts
  alias Tuist.Authorization
  alias Tuist.Projects

  def account_breadcrumb(selected_account, current_user_accounts, opts \\ []) do
    docs_base_path = Keyword.get(opts, :docs_base_path)

    %{
      label: selected_account.name,
      icon: "smart_home",
      show_avatar: true,
      avatar_color: Accounts.avatar_color(selected_account),
      items:
        Enum.map(current_user_accounts, fn account ->
          href =
            if docs_base_path,
              do: "#{docs_base_path}?account=#{account.id}",
              else: ~p"/#{account.name}/projects"

          %{
            label: account.name,
            value: account.id,
            selected: account.id == selected_account.id,
            href: href,
            show_avatar: true,
            avatar_color: Accounts.avatar_color(account)
          }
        end) ++
          [
            %{
              label: dgettext("dashboard", "Create organization"),
              value: "create-organization",
              href: ~p"/organizations/new",
              icon: "building_plus",
              selected: false
            }
          ]
    }
  end

  def project_breadcrumb(selected_project, selected_account, projects, opts \\ []) do
    docs_base_path = Keyword.get(opts, :docs_base_path)

    label =
      if is_nil(selected_project),
        do: dgettext("dashboard", "Select project"),
        else: selected_project.name

    badge =
      if is_nil(selected_project),
        do: nil,
        else: build_system_badge(selected_project.build_system)

    %{
      label: label,
      badge: badge,
      items:
        Enum.map(projects, fn project ->
          href =
            if docs_base_path,
              do: "#{docs_base_path}?account=#{selected_account.id}&project=#{project.id}",
              else: ~p"/#{selected_account.name}/#{project.name}"

          %{
            label: project.name,
            value: project.id,
            selected: not is_nil(selected_project) and selected_project.id == project.id,
            href: href,
            badge: build_system_badge(project.build_system)
          }
        end) ++
          [
            %{
              label: dgettext("dashboard", "Create project"),
              value: "create-project",
              href: ~p"/projects/new?account_id=#{selected_account.id}",
              icon: "circle_plus",
              selected: false
            }
          ]
    }
  end

  def get_user_accounts(user) do
    if is_nil(user) do
      []
    else
      organization_accounts =
        user |> Accounts.get_user_organization_accounts() |> Enum.map(& &1.account)

      organization_accounts ++ [user.account]
    end
  end

  def get_account_projects(account, current_user) do
    account
    |> Projects.get_all_project_accounts()
    |> Enum.filter(fn %{account: account, project: project} ->
      Authorization.authorize(:project_url_access, current_user, %{project | account: account}) ==
        :ok
    end)
    |> Enum.map(&%{&1.project | account: &1.account})
  end

  defp build_system_badge(:xcode), do: %{label: "Xcode", color: "focus"}
  defp build_system_badge(:gradle), do: %{label: "Gradle", color: "success"}
  defp build_system_badge(_), do: nil
end
