defmodule Tuist.Authorization do
  @moduledoc ~S"""
  A module to deal with authorization in the system.
  """
  use LetMe.Policy, error_reason: :forbidden

  object :run do
    action :create do
      desc("Allows users of a project to create a run.")
      allow([:authenticated_as_user, user_role: :user])

      desc("Allows the admin of a project to create a run.")
      allow([:authenticated_as_user, user_role: :admin])

      desc(
        "Allows the authenticated project to create the run if it matches the project for which the run is being created."
      )

      allow([:authenticated_as_project, :projects_match])

      desc("Allows an account token with project:runs:write scope to create runs.")
      allow([:authenticated_as_account, scopes_permit: "project:runs:write"])
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

      desc("Allows users with ops access to read any run.")
      allow([:authenticated_as_user, :ops_access])

      desc("Allows an account token with project:runs:read or project:runs:write scope to read runs.")
      allow([:authenticated_as_account, scopes_permit: "project:runs:read"])
      allow([:authenticated_as_account, scopes_permit: "project:runs:write"])
    end

    action :update do
      desc("Allows users of a project to update a run.")
      allow([:authenticated_as_user, user_role: :user])

      desc("Allows the admin of a project to update a run.")
      allow([:authenticated_as_user, user_role: :admin])

      desc("Allows the authenticated project to update the run if it matches the project whose run is being read.")

      allow([:authenticated_as_project, :projects_match])

      desc("Allows an account token with project:runs:write scope to update runs.")
      allow([:authenticated_as_account, scopes_permit: "project:runs:write"])
    end
  end

  object :bundle do
    action :create do
      desc("Allows users of a project to create a bundle.")
      allow([:authenticated_as_user, user_role: :user])

      desc("Allows the admin of a project to create a bundle.")
      allow([:authenticated_as_user, user_role: :admin])

      desc(
        "Allows the authenticated project to create the bundle if it matches the project for which the bundle is being created."
      )

      allow([:authenticated_as_project, :projects_match])

      desc("Allows an account token with project:bundles:write scope to create bundles.")
      allow([:authenticated_as_account, scopes_permit: "project:bundles:write"])
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

      desc("Allows users with ops access to read any bundle.")
      allow([:authenticated_as_user, :ops_access])

      desc("Allows an account token with project:bundles:read or project:bundles:write scope to read bundles.")
      allow([:authenticated_as_account, scopes_permit: "project:bundles:read"])
      allow([:authenticated_as_account, scopes_permit: "project:bundles:write"])
    end

    action :delete do
      desc("Bundle deletion is dashboard-only and is not available to project or account tokens.")

      desc("Allows users of a project to delete a bundle.")
      allow([:authenticated_as_user, user_role: :user])

      desc("Allows the admin of a project to delete a bundle.")
      allow([:authenticated_as_user, user_role: :admin])

      desc("Allows users with ops write access to delete any bundle.")
      allow([:authenticated_as_user, :ops_write_access])
    end
  end

  object :account do
    action :cache_create do
      desc("Allows users of an account to create entries in the account cache.")
      allow([:authenticated_as_user, :cache_write_policy_permits_subject, user_role: :user])

      desc("Allows the admin of an account to create entries in the account cache.")
      allow([:authenticated_as_user, :cache_write_policy_permits_subject, user_role: :admin])

      desc("Allows an account token with account:cache:write scope to create account cache entries.")
      allow([:authenticated_as_account, :cache_write_policy_permits_subject, scopes_permit: "account:cache:write"])
    end

    action :cache_read do
      desc("Allows users of an account to read the account cache.")
      allow([:authenticated_as_user, user_role: :user])

      desc("Allows the admin of an account to read the account cache.")
      allow([:authenticated_as_user, user_role: :admin])

      desc("Allows an authenticated project to discover cache endpoints for its own account.")
      allow([:authenticated_as_project, :accounts_match])

      desc("Allows an account token with account:cache:read or account:cache:write scope to read account cache.")
      allow([:authenticated_as_account, :accounts_match, scopes_permit: "account:cache:read"])
      allow([:authenticated_as_account, :accounts_match, scopes_permit: "account:cache:write"])
    end

    action :update do
      desc("Allows the admin of an account to update its settings.")
      allow([:authenticated_as_user, user_role: :admin])

      desc("Allows users with ops write access to update any account's settings.")
      allow([:authenticated_as_user, :ops_write_access])
    end

    action :delete do
      desc("Allows the admin of an account to delete the account.")
      allow([:authenticated_as_user, user_role: :admin])
    end
  end

  object :account_token do
    action :create do
      desc("Allows the admin of an account to create an account token.")
      allow([:authenticated_as_user, user_role: :admin])
    end

    action :read do
      desc("Allows users of an account to read account tokens.")
      allow([:authenticated_as_user, user_role: :user])

      desc("Allows the admin of an account to read account tokens.")
      allow([:authenticated_as_user, user_role: :admin])

      desc("Allows users with ops access to read any account tokens.")
      allow([:authenticated_as_user, :ops_access])
    end

    action :delete do
      desc("Allows the admin of an account to delete account tokens.")
      allow([:authenticated_as_user, user_role: :admin])
    end
  end

  object :preview do
    action :create do
      desc("Allows users of a project to create a preview.")
      allow([:authenticated_as_user, user_role: :user])

      desc("Allows the admin of a project to create a preview.")
      allow([:authenticated_as_user, user_role: :admin])

      desc(
        "Allows the authenticated project to create the preview if it matches the project for which the preview is being created."
      )

      allow([:authenticated_as_project, :projects_match])

      desc("Allows an account token with project:previews:write scope to create previews.")
      allow([:authenticated_as_account, scopes_permit: "project:previews:write"])
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

      desc("Allows users with ops access to read any preview.")
      allow([:authenticated_as_user, :ops_access])

      desc("Allows an account token with project:previews:read or project:previews:write scope to read previews.")
      allow([:authenticated_as_account, scopes_permit: "project:previews:read"])
      allow([:authenticated_as_account, scopes_permit: "project:previews:write"])
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

      desc("Allows an account token with project:previews:write scope to delete previews.")
      allow([:authenticated_as_account, scopes_permit: "project:previews:write"])
    end
  end

  object :project do
    action :cache_create do
      desc("Allows users of a project's account to create entries in the project cache.")
      allow([:authenticated_as_user, :cache_write_policy_permits_subject, user_role: :user])

      desc("Allows the admin of a project's account to create entries in the project cache.")
      allow([:authenticated_as_user, :cache_write_policy_permits_subject, user_role: :admin])

      desc(
        "Allows the authenticated project to create cache entries if it matches the project whose cache is being written."
      )

      allow([:authenticated_as_project, :projects_match])

      desc("Allows an account token with project:cache:write scope to create project cache entries.")
      allow([:authenticated_as_account, :cache_write_policy_permits_subject, scopes_permit: "project:cache:write"])
    end

    action :cache_read do
      desc("Allows the authenticated subject to read a project's cache if the project is public.")
      allow(:public_project)

      desc("Allows users of a project's account to read the project cache.")
      allow([:authenticated_as_user, user_role: :user])

      desc("Allows the admin of a project's account to read the project cache.")
      allow([:authenticated_as_user, user_role: :admin])

      desc("Allows the authenticated project to read the cache if it matches the project whose cache is being read.")

      allow([:authenticated_as_project, :projects_match])

      desc("Allows users with ops access to read any project cache.")
      allow([:authenticated_as_user, :ops_access])

      desc("Allows an account token with project:cache:read or project:cache:write scope to read project cache.")
      allow([:authenticated_as_account, scopes_permit: "project:cache:read"])
      allow([:authenticated_as_account, scopes_permit: "project:cache:write"])
    end

    action :cache_update do
      desc("Allows users of a project's account to update project cache.")
      allow([:authenticated_as_user, :cache_write_policy_permits_subject, user_role: :user])

      desc("Allows the admin of a project's account to update project cache.")
      allow([:authenticated_as_user, :cache_write_policy_permits_subject, user_role: :admin])

      desc("Allows the authenticated project to update project cache if it matches the project.")
      allow([:authenticated_as_project, :projects_match])

      desc("Allows an account token with project:cache:write scope to update project cache.")
      allow([:authenticated_as_account, :cache_write_policy_permits_subject, scopes_permit: "project:cache:write"])
    end

    action :create do
      desc("Allows users of an account to create a project.")
      allow([:authenticated_as_user, user_role: :user])

      desc("Allows the admin of an account to create a project.")
      allow([:authenticated_as_user, user_role: :admin])
    end

    action :read do
      desc("Allows users of an account to read projects.")
      allow([:authenticated_as_user, user_role: :user])

      desc("Allows the admin of an account to read projects.")
      allow([:authenticated_as_user, user_role: :admin])

      desc("Allows users with ops access to read any projects.")
      allow([:authenticated_as_user, :ops_access])

      desc("Allows an account token with project:admin:read scope to read projects.")
      allow([:authenticated_as_account, scopes_permit: "project:admin:read"])
    end

    action :update do
      desc("Allows the admin of an account to update a project.")
      allow([:authenticated_as_user, user_role: :admin])
    end

    action :delete do
      desc("Allows the admin of an account to delete a project.")
      allow([:authenticated_as_user, user_role: :admin])
    end
  end

  object :dashboard do
    action :read do
      desc("Allows anyone to read a public project dashboard.")
      allow(:public_project)

      desc("Allows users of an account to read private project dashboards.")
      allow([:authenticated_as_user, user_role: :user])

      desc("Allows the admin of an account to read private project dashboards.")
      allow([:authenticated_as_user, user_role: :admin])

      desc("Allows users with ops access to read any dashboard.")
      allow([:authenticated_as_user, :ops_access])
    end
  end

  object :billing do
    action :read do
      desc("Allows admins to read billing information for Tuist hosted accounts.")
      allow([:authenticated_as_user, :billing_access])

      desc("Allows users with ops access to read any billing information.")
      allow([:authenticated_as_user, :ops_access])
    end

    action :update do
      desc("Allows admins to update billing information for Tuist hosted accounts.")
      allow([:authenticated_as_user, :billing_access])
    end

    action :usage_read do
      desc("Allows users of an account to read organization token usage.")
      allow([:authenticated_as_user, user_role: :user])

      desc("Allows the admin of an account to read organization token usage.")
      allow([:authenticated_as_user, user_role: :admin])

      desc("Allows users with ops access to read any organization token usage.")
      allow([:authenticated_as_user, :ops_access])
    end
  end

  object :projects do
    action :read do
      desc("Allows users of an account to read projects.")
      allow([:authenticated_as_user, user_role: :user])

      desc("Allows the admin of an account to read projects.")
      allow([:authenticated_as_user, user_role: :admin])

      desc("Allows users with ops access to read any projects.")
      allow([:authenticated_as_user, :ops_access])

      desc("Allows an account token with project:admin:read scope to read projects.")
      allow([:authenticated_as_account, scopes_permit: "project:admin:read"])
    end
  end

  object :runners do
    action :read do
      desc("Allows users of an account to read runner jobs, workflows, and live runner state.")
      allow([:authenticated_as_user, user_role: :user])

      desc("Allows the admin of an account to read runner jobs, workflows, and live runner state.")

      allow([:authenticated_as_user, user_role: :admin])

      desc("Allows users with ops access to read runner jobs, workflows, and live runner state.")
      allow([:authenticated_as_user, :ops_access])
    end
  end

  object :organization do
    action :read do
      desc("Allows users of an account to read organization info.")
      allow([:authenticated_as_user, user_role: :user])

      desc("Allows the admin of an account to read organization info.")
      allow([:authenticated_as_user, user_role: :admin])

      desc("Allows users with ops access to read any organization info.")
      allow([:authenticated_as_user, :ops_access])

      desc(
        "Allows an account token with account:members:read or account:members:write scope to read organization members."
      )

      allow([:authenticated_as_account, :accounts_match, scopes_permit: "account:members:read"])
      allow([:authenticated_as_account, :accounts_match, scopes_permit: "account:members:write"])
    end

    action :update do
      desc("Allows the admin of an account to update organization info.")
      allow([:authenticated_as_user, user_role: :admin])
    end

    action :delete do
      desc("Allows the admin of an account to delete organization.")
      allow([:authenticated_as_user, user_role: :admin])
    end
  end

  object :invitation do
    action :create do
      desc("Allows the admin of an account to create invitations.")
      allow([:authenticated_as_user, user_role: :admin])

      desc("Allows an account token with account:members:write scope to create invitations.")
      allow([:authenticated_as_account, :accounts_match, scopes_permit: "account:members:write"])
    end

    action :read do
      desc("Allows the admin of an account to read invitations.")
      allow([:authenticated_as_user, user_role: :admin])

      desc("Allows users with ops access to read any invitations.")
      allow([:authenticated_as_user, :ops_access])

      desc("Allows an account token with account:members:read or account:members:write scope to read invitations.")
      allow([:authenticated_as_account, :accounts_match, scopes_permit: "account:members:read"])
      allow([:authenticated_as_account, :accounts_match, scopes_permit: "account:members:write"])
    end

    action :delete do
      desc("Allows the admin of an account to delete invitations.")
      allow([:authenticated_as_user, user_role: :admin])

      desc("Allows an account token with account:members:write scope to delete invitations.")
      allow([:authenticated_as_account, :accounts_match, scopes_permit: "account:members:write"])
    end
  end

  object :member do
    action :update do
      desc("Allows the admin of an account to update members.")
      allow([:authenticated_as_user, user_role: :admin])

      desc("Allows an account token with account:members:write scope to update members.")
      allow([:authenticated_as_account, :accounts_match, scopes_permit: "account:members:write"])
    end

    action :delete do
      desc("Allows the admin of an account to delete members.")
      allow([:authenticated_as_user, user_role: :admin])

      desc("Allows an account token with account:members:write scope to delete members.")
      allow([:authenticated_as_account, :accounts_match, scopes_permit: "account:members:write"])
    end
  end

  object :project_url do
    action :access do
      desc("Allows anyone to access public project URLs.")
      allow(:public_project)

      desc("Allows users of an account to access private project URLs.")
      allow([:authenticated_as_user, user_role: :user])

      desc("Allows the admin of an account to access private project URLs.")
      allow([:authenticated_as_user, user_role: :admin])
    end
  end

  object :command_event do
    action :read do
      desc("Allows reading command events if the user can read the associated project or if the project is public.")

      allow(:command_event_project_access)

      desc("Allows users with ops access to read any command events.")
      allow([:authenticated_as_user, :ops_access])
    end
  end

  object :automation_alert do
    action :create do
      desc("Allows the admin of a project to create an automation alert.")
      allow([:authenticated_as_user, user_role: :admin])
    end

    action :read do
      desc("Allows users of a project to read automation alerts.")
      allow([:authenticated_as_user, user_role: :user])

      desc("Allows the admin of a project to read automation alerts.")
      allow([:authenticated_as_user, user_role: :admin])

      desc("Allows users with ops access to read any automation alerts.")
      allow([:authenticated_as_user, :ops_access])
    end

    action :update do
      desc("Allows the admin of a project to update an automation alert.")
      allow([:authenticated_as_user, user_role: :admin])
    end

    action :delete do
      desc("Allows the admin of a project to delete an automation alert.")
      allow([:authenticated_as_user, user_role: :admin])
    end
  end

  object :test do
    action :create do
      desc("Allows users of a project to create a test.")
      allow([:authenticated_as_user, user_role: :user])

      desc("Allows the admin of a project to create a test.")
      allow([:authenticated_as_user, user_role: :admin])

      desc(
        "Allows the authenticated project to create the test if it matches the project for which the test is being created."
      )

      allow([:authenticated_as_project, :projects_match])

      desc("Allows an account token with project:tests:write scope to create tests.")
      allow([:authenticated_as_account, scopes_permit: "project:tests:write"])
    end

    action :read do
      desc("Allows the authenticated subject to read a project's tests if the project is public.")
      allow(:public_project)

      desc("Allows users of a project to read tests.")
      allow([:authenticated_as_user, user_role: :user])

      desc("Allows the admin of a project to read tests.")
      allow([:authenticated_as_user, user_role: :admin])

      desc("Allows the authenticated project to read tests if it matches the project.")
      allow([:authenticated_as_project, :projects_match])

      desc("Allows users with ops access to read any tests.")
      allow([:authenticated_as_user, :ops_access])

      desc("Allows an account token with project:tests:read or project:tests:write scope to read tests.")
      allow([:authenticated_as_account, scopes_permit: "project:tests:read"])
      allow([:authenticated_as_account, scopes_permit: "project:tests:write"])
    end

    action :update do
      desc("Allows users of a project to update a tests data.")
      allow([:authenticated_as_user, user_role: :user])

      desc("Allows the admin of a project to update tests data.")
      allow([:authenticated_as_user, user_role: :admin])

      desc("Allows an account token with project:tests:write scope to update tests data.")
      allow([:authenticated_as_account, scopes_permit: "project:tests:write"])
    end
  end

  object :build do
    action :create do
      desc("Allows users of a project to create a build.")
      allow([:authenticated_as_user, user_role: :user])

      desc("Allows the admin of a project to create a build.")
      allow([:authenticated_as_user, user_role: :admin])

      desc(
        "Allows the authenticated project to create the build if it matches the project for which the build is being created."
      )

      allow([:authenticated_as_project, :projects_match])

      desc("Allows an account token with project:builds:write scope to create builds.")
      allow([:authenticated_as_account, scopes_permit: "project:builds:write"])
    end

    action :read do
      desc("Allows the authenticated subject to read a project's builds if the project is public.")
      allow(:public_project)

      desc("Allows users of a project to read builds.")
      allow([:authenticated_as_user, user_role: :user])

      desc("Allows the admin of a project to read builds.")
      allow([:authenticated_as_user, user_role: :admin])

      desc("Allows the authenticated project to read builds if it matches the project.")
      allow([:authenticated_as_project, :projects_match])

      desc("Allows users with ops access to read any builds.")
      allow([:authenticated_as_user, :ops_access])

      desc("Allows an account token with project:builds:read or project:builds:write scope to read builds.")
      allow([:authenticated_as_account, scopes_permit: "project:builds:read"])
      allow([:authenticated_as_account, scopes_permit: "project:builds:write"])
    end
  end

  object :ops do
    action :read do
      desc("Allows Tuist operators to access the internal ops panel.")
      allow([:authenticated_as_user, :internal_ops_access])
    end
  end
end
