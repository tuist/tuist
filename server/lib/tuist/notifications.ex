defmodule Tuist.Notifications do
  @moduledoc """
  A user's own choices about which notifications they get, independent of how
  they are delivered.

  The choices are scoped by kind (today `new_preview`) and by account and project:
  `AccountPreference` covers one account's projects (the user's personal account
  or an organization), and `ProjectPreference` overrides it for one project.
  Missing rows mean the default: an account is enabled and a project follows its
  account. The same choices apply to every delivery channel: the Tuist apps
  (`Tuist.Push`) today, and email or the browser later. Which devices receive
  app notifications is governed by the device registry, not by a preference.

  Transactional email (sign-in, security, invitations, billing; see
  `Tuist.Accounts.UserNotifier`) is never governed by these preferences.
  """

  import Ecto.Query

  alias Tuist.Accounts
  alias Tuist.Accounts.User
  alias Tuist.Notifications.AccountPreference
  alias Tuist.Notifications.ProjectPreference
  alias Tuist.Projects.Project
  alias Tuist.Repo

  @kinds ["new_preview"]

  def kinds, do: @kinds

  @doc """
  `user`'s own `kind` choices for every account they belong to (their personal
  account and their organizations), sorted by name:

      [%{account: account, enabled: boolean,
         projects: [%{project: project, override: nil | boolean, enabled: boolean}]}]

  An account is enabled unless the user turned it off. A project's `override`
  is nil when it follows its account; `enabled` is the effective choice.
  """
  def preferences(%User{id: user_id} = user, kind) when kind in @kinds do
    account_choices =
      AccountPreference
      |> where([p], p.user_id == ^user_id and p.kind == ^kind)
      |> select([p], {p.account_id, p.enabled})
      |> Repo.all()
      |> Map.new()

    overrides =
      ProjectPreference
      |> where([p], p.user_id == ^user_id and p.kind == ^kind)
      |> select([p], {p.project_id, p.enabled})
      |> Repo.all()
      |> Map.new()

    accounts = accessible_accounts(user)
    account_ids = Enum.map(accounts, & &1.id)

    projects =
      Project
      |> where([p], p.account_id in ^account_ids)
      |> preload(:account)
      |> Repo.all()
      |> Enum.group_by(& &1.account_id)

    accounts
    |> Enum.map(fn account ->
      enabled = Map.get(account_choices, account.id, true)

      %{
        account: account,
        enabled: enabled,
        projects:
          projects
          |> Map.get(account.id, [])
          |> Enum.sort_by(& &1.name)
          |> Enum.map(fn project ->
            override = Map.get(overrides, project.id)
            %{project: project, override: override, enabled: if(is_nil(override), do: enabled, else: override)}
          end)
      }
    end)
    |> Enum.sort_by(& &1.account.name)
  end

  @doc """
  `user`'s `kind` choice for one project, as
  `%{override: nil | boolean, account_enabled: boolean, enabled: boolean}`,
  or nil when the project is outside the user's accounts (for example a public
  project they only browse).
  """
  def project_preference(%User{id: user_id} = user, kind, %Project{id: project_id, account_id: account_id})
      when kind in @kinds do
    if account_id in accessible_account_ids(user) do
      override =
        ProjectPreference
        |> where([p], p.user_id == ^user_id and p.project_id == ^project_id and p.kind == ^kind)
        |> select([p], p.enabled)
        |> Repo.one()

      account_enabled =
        AccountPreference
        |> where([p], p.user_id == ^user_id and p.account_id == ^account_id and p.kind == ^kind)
        |> select([p], p.enabled)
        |> Repo.one()
        |> Kernel.!=(false)

      %{
        override: override,
        account_enabled: account_enabled,
        enabled: if(is_nil(override), do: account_enabled, else: override)
      }
    end
  end

  def project_preference(_user, _kind, _project), do: nil

  @doc """
  Turns `kind` on or off for the projects of `account_id`, which must be the
  user's personal account or one of their organizations. Project overrides
  are kept. Returns `:ok` or `{:error, :invalid}`.
  """
  def update_account_preference(%User{id: user_id} = user, kind, account_id, enabled)
      when kind in @kinds and is_integer(account_id) and is_boolean(enabled) do
    if account_id in accessible_account_ids(user) do
      Repo.insert!(%AccountPreference{user_id: user_id, account_id: account_id, kind: kind, enabled: enabled},
        on_conflict: [set: [enabled: enabled, updated_at: now()]],
        conflict_target: [:user_id, :account_id, :kind]
      )

      :ok
    else
      {:error, :invalid}
    end
  end

  def update_account_preference(_user, _kind, _account_id, _enabled), do: {:error, :invalid}

  @doc """
  Overrides `kind` for one project the user can access: `true` or `false`, or
  `nil` to follow the project's account again. Returns `:ok` or
  `{:error, :invalid}`.
  """
  def update_project_preference(%User{id: user_id} = user, kind, project_id, override)
      when kind in @kinds and is_integer(project_id) and (is_boolean(override) or is_nil(override)) do
    case Repo.get(Project, project_id) do
      %Project{account_id: account_id} ->
        if account_id in accessible_account_ids(user) do
          save_project_override(user_id, kind, project_id, override)
        else
          {:error, :invalid}
        end

      nil ->
        {:error, :invalid}
    end
  end

  def update_project_preference(_user, _kind, _project_id, _override), do: {:error, :invalid}

  defp save_project_override(user_id, kind, project_id, nil) do
    ProjectPreference
    |> where([p], p.user_id == ^user_id and p.project_id == ^project_id and p.kind == ^kind)
    |> Repo.delete_all()

    :ok
  end

  defp save_project_override(user_id, kind, project_id, enabled) do
    Repo.insert!(%ProjectPreference{user_id: user_id, project_id: project_id, kind: kind, enabled: enabled},
      on_conflict: [set: [enabled: enabled, updated_at: now()]],
      conflict_target: [:user_id, :project_id, :kind]
    )

    :ok
  end

  defp accessible_accounts(user) do
    [Accounts.get_account_from_user(user) | Enum.map(Accounts.get_user_organization_accounts(user), & &1.account)]
  end

  defp accessible_account_ids(user), do: user |> accessible_accounts() |> Enum.map(& &1.id)

  @doc """
  Whether `user_id` wants `kind` notifications about `project_id`: their
  project override, else their choice for the project's account, else yes.
  Callers still have to check that the user can access the project at send time.
  """
  def notify?(user_id, kind, project_id) when kind in @kinds do
    Project
    |> where([p], p.id == ^project_id)
    |> join(:left, [p], o in ProjectPreference, on: o.project_id == p.id and o.user_id == ^user_id and o.kind == ^kind)
    |> join(:left, [p], a in AccountPreference,
      on: a.account_id == p.account_id and a.user_id == ^user_id and a.kind == ^kind
    )
    |> select([_p, o, a], coalesce(o.enabled, coalesce(a.enabled, true)))
    |> Repo.one()
    |> Kernel.==(true)
  end

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)
end
