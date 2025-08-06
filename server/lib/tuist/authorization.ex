defmodule Tuist.Authorization do
  @moduledoc ~S"""
  A module to deal with authorization in the system.
  """
  use LetMe.Policy, error_reason: :forbidden

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Accounts.User
  alias Tuist.Billing
  alias Tuist.CommandEvents
  alias Tuist.Environment
  alias Tuist.Projects.Project
  alias Tuist.VCS

  object :project_run do
    action :create do
      desc("Allows users of a project to create a run.")
      allow([:authenticated_as_user, user_role: :user])

      desc("Allows the admin of a project to create a run.")
      allow([:authenticated_as_user, user_role: :admin])

      desc(
        "Allows the authenticated project to create the run if it matches the project for which the run is being created."
      )

      allow([:authenticated_as_project, :projects_match])
    end

    action :read do
      desc("Allows the authenticated subject to read a project's run if the project is public.")
      allow(:public_project)

      desc("Allows users of a project to read a run.")
      allow([:authenticated_as_user, user_role: :user])

      desc("Allows the admin of a project to read a run.")
      allow([:authenticated_as_user, user_role: :admin])

      desc("Allows the authenticated project to read the run if it matches the project whose run is being read.")

      allow([:authenticated_as_project, :projects_match])
    end

    action :update do
      desc("Allows users of a project to update a run.")
      allow([:authenticated_as_user, user_role: :user])

      desc("Allows the admin of a project to update a run.")
      allow([:authenticated_as_user, user_role: :admin])

      desc("Allows the authenticated project to update the run if it matches the project whose run is being read.")

      allow([:authenticated_as_project, :projects_match])
    end
  end

  object :project_bundle do
    action :create do
      desc("Allows users of a project to create a bundle.")
      allow([:authenticated_as_user, user_role: :user])

      desc("Allows the admin of a project to create a bundle.")
      allow([:authenticated_as_user, user_role: :admin])

      desc(
        "Allows the authenticated project to create the bundle if it matches the project for which the bundle is being created."
      )

      allow([:authenticated_as_project, :projects_match])
    end

    action :read do
      desc("Allows the authenticated subject to read a project's bundle if the project is public.")

      allow(:public_project)

      desc("Allows users of a project to read a bundle.")
      allow([:authenticated_as_user, user_role: :user])

      desc("Allows the admin of a project to read a bundle.")
      allow([:authenticated_as_user, user_role: :admin])

      desc("Allows the authenticated project to read the bundle if it matches the project whose bundle is being read.")

      allow([:authenticated_as_project, :projects_match])
    end
  end

  object :project_cache do
    action :read do
      desc("Allows the authenticated subject to read a project's cache if the project is public.")
      allow(:public_project)

      desc("Allows users of a project's account to read the project cache.")
      allow([:authenticated_as_user, user_role: :user])

      desc("Allows the admin of a project's account to read the project cache.")
      allow([:authenticated_as_user, user_role: :admin])

      desc("Allows the authenticated project to read the cache if it matches the project whose cache is being read.")

      allow([:authenticated_as_project, :projects_match])
    end
  end

  object :account_registry do
    action :read do
      desc("Allows users of an account to read its registry.")
      allow([:authenticated_as_user, user_role: :user])

      desc("Allows the admin of an account to read its registry.")
      allow([:authenticated_as_user, user_role: :admin])

      desc(
        "Allows the authenticated account to read the account registry if it matches the account whose registry is being read."
      )

      allow([:authenticated_as_account, :accounts_match, scopes_permit: :account_registry_read])

      desc("Allows the authenticated project to read the cache if it matches the project whose cache is being read.")

      allow([:authenticated_as_project, :accounts_match])
    end
  end

  object :account_settings do
    action :update do
      desc("Allows the admin of an account to update its settings.")
      allow([:authenticated_as_user, user_role: :admin])
    end
  end

  object :account do
    action :delete do
      desc("Allows the admin of an account to delete the account.")
      allow([:authenticated_as_user, user_role: :admin])
    end
  end

  object :account_token do
    action :create do
      desc("Allows users of an account to create an account token.")
      allow([:authenticated_as_user, user_role: :user])

      desc("Allows the admin of an account to create an account token.")
      allow([:authenticated_as_user, user_role: :admin])
    end
  end

  object :account_organization do
    action :update do
      desc("Allows the admin of an account to update its organization.")
      allow([:authenticated_as_user, user_role: :admin])
    end
  end

  object :project_qa_step do
    action :create do
      desc("Allows an account token with project_qa_step_create scope to create QA steps.")
      allow([:authenticated_as_account, scopes_permit: :project_qa_step_create])
    end
  end

  object :project_qa_screenshot do
    action :create do
      desc("Allows an account token with project_qa_screenshot_create scope to create QA screenshots.")
      allow([:authenticated_as_account, scopes_permit: :project_qa_screenshot_create])
    end
  end

  object :project_qa_run do
    action :update do
      desc("Allows an account token with project_qa_run_update scope to update a QA run.")
      allow([:authenticated_as_account, scopes_permit: :project_qa_run_update])
    end
  end

  object :project_preview do
    action :create do
      desc("Allows users of a project to create a preview.")
      allow([:authenticated_as_user, user_role: :user])

      desc("Allows the admin of a project to create a preview.")
      allow([:authenticated_as_user, user_role: :admin])

      desc(
        "Allows the authenticated project to create the preview if it matches the project for which the preview is being created."
      )

      allow([:authenticated_as_project, :projects_match])
    end

    action :read do
      desc("Allows the authenticated subject to read a project's preview if the project is public.")

      allow(:public_project)

      desc("Allows users of a project to read a preview.")
      allow([:authenticated_as_user, user_role: :user])

      desc("Allows the admin of a project to read a preview.")
      allow([:authenticated_as_user, user_role: :admin])

      desc("Allows the authenticated project to read the preview if it matches the project whose preview is being read.")

      allow([:authenticated_as_project, :projects_match])
    end

    action :delete do
      desc("Allows users of a project to delete a preview.")
      allow([:authenticated_as_user, user_role: :user])

      desc("Allows the admin of a project to delete a preview.")
      allow([:authenticated_as_user, user_role: :admin])

      desc(
        "Allows the authenticated project to delete the preview if it matches the project whose preview is being deleted."
      )

      allow([:authenticated_as_project, :projects_match])
    end
  end

  def can(%User{} = user, :create, %Account{} = account, :project) do
    Accounts.owns_account_or_belongs_to_account_organization?(user, account)
  end

  def can(%User{} = user, :read, %Account{} = account, :project) do
    Accounts.owns_account_or_belongs_to_account_organization?(user, account)
  end

  def can(%User{} = user, :update, %Project{} = project, %{repository: %VCS.Repositories.Repository{} = repository}) do
    account = Accounts.get_account_by_id(project.account_id)

    if can(user, :update, account, :project) do
      case VCS.get_user_permission(%{user: user, repository: repository}) do
        {:ok, %VCS.Repositories.Permission{permission: permission}} ->
          Enum.member?(["admin", "write"], permission)

        _ ->
          false
      end
    else
      false
    end
  end

  def can(_, :read, %Project{visibility: :public}, :dashboard) do
    true
  end

  def can(nil, :read, %Project{visibility: :private}, :dashboard) do
    false
  end

  def can(%User{} = user, :read, %Project{visibility: :private} = project, :dashboard) do
    account = Accounts.get_account_by_id(project.account_id)
    can(user, :read, account, :project)
  end

  def can(%User{} = user, :update, %Account{} = account, :project) do
    Accounts.owns_account_or_is_admin_to_account_organization?(user, account)
  end

  def can(%User{} = user, :delete, %Account{} = account, :project) do
    Accounts.owns_account_or_is_admin_to_account_organization?(user, account)
  end

  def can(%User{} = user, :create, %Project{} = project, :cache) do
    Accounts.owns_account_or_belongs_to_account_organization?(user, %{id: project.account_id})
  end

  def can(%User{} = user, :update, %Project{} = project, :cache) do
    Accounts.owns_account_or_belongs_to_account_organization?(user, %{id: project.account_id})
  end

  def can(%User{} = user, :update, %Account{} = account, :billing) do
    subscription = Billing.get_current_active_subscription(account)

    if not Environment.tuist_hosted?() or
         (not is_nil(subscription) and subscription.plan == :open_source) do
      false
    else
      Accounts.owns_account_or_is_admin_to_account_organization?(user, account)
    end
  end

  def can(%User{} = user, :read, %Account{} = account, :billing) do
    subscription = Billing.get_current_active_subscription(account)

    if not Environment.tuist_hosted?() or
         (not is_nil(subscription) and subscription.plan == :open_source) do
      false
    else
      Accounts.owns_account_or_is_admin_to_account_organization?(user, account)
    end
  end

  def can(nil, :update, _account, :billing) do
    false
  end

  def can(%User{} = user, :read, %Account{} = account, :projects) do
    Accounts.owns_account_or_belongs_to_account_organization?(user, account)
  end

  def can(%User{} = user, :read, %Account{} = account, :organization) do
    Accounts.owns_account_or_belongs_to_account_organization?(user, account)
  end

  def can(%User{} = user, :read, %Account{} = account, :organization_usage) do
    Accounts.owns_account_or_belongs_to_account_organization?(user, account)
  end

  def can(%User{} = user, :update, %Account{} = account, :organization) do
    Accounts.owns_account_or_is_admin_to_account_organization?(user, account)
  end

  def can(%User{} = user, :delete, %Account{} = account, :organization) do
    Accounts.owns_account_or_is_admin_to_account_organization?(user, account)
  end

  def can(%User{} = user, :create, %Account{} = account, :invitation) do
    Accounts.owns_account_or_is_admin_to_account_organization?(user, account)
  end

  def can(%User{} = user, :read, %Account{} = account, :invitation) do
    Accounts.owns_account_or_is_admin_to_account_organization?(user, account)
  end

  def can(%User{} = user, :delete, %Account{} = account, :invitation) do
    Accounts.owns_account_or_is_admin_to_account_organization?(user, account)
  end

  def can(%User{} = user, :delete, %Account{} = account, :member) do
    Accounts.owns_account_or_is_admin_to_account_organization?(user, account)
  end

  def can(%User{} = user, :update, %Account{} = account, :member) do
    Accounts.owns_account_or_is_admin_to_account_organization?(user, account)
  end

  def can(%User{} = user, :create, %Account{} = account, :token) do
    Accounts.owns_account_or_belongs_to_account_organization?(user, account)
  end

  def can(%User{} = user, :read, %Account{} = account, :token) do
    Accounts.owns_account_or_belongs_to_account_organization?(user, account)
  end

  def can(%User{} = user, :delete, %Account{} = account, :token) do
    Accounts.owns_account_or_is_admin_to_account_organization?(user, account)
  end

  def can(%User{} = user, :update, %Project{} = project, :settings) do
    Accounts.owns_account_or_is_admin_to_account_organization?(user, %{id: project.account_id})
  end

  def can(%Project{} = current_project, :create, %Project{} = project, :cache) do
    current_project.id == project.id
  end

  def can(%Project{} = current_project, :update, %Project{} = project, :cache) do
    current_project.id == project.id
  end

  def can(_, :access, %Project{visibility: :public}, :url) do
    true
  end

  def can(nil, :access, %Project{visibility: :private}, :url) do
    false
  end

  def can(user, :access, %Project{visibility: :private, account: %Account{} = account}, :url) do
    Accounts.owns_account_or_belongs_to_account_organization?(user, account)
  end

  def can(subject, :read, command_event)
      when command_event.__struct__ in [Tuist.CommandEvents.Postgres.Event, Tuist.CommandEvents.Clickhouse.Event] do
    case CommandEvents.get_project_for_command_event(command_event) do
      {:ok, project} -> can?(:project_run_read, subject, project)
      {:error, _} -> false
    end
  end

  def can(%User{} = user, :read, :ops) do
    if Environment.dev?() do
      true
    else
      user.account.name in Environment.ops_user_handles()
    end
  end

  def can?(action, subject, object) do
    authorize(action, subject, object) == :ok
  end
end
