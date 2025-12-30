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
  end

  object :cache do
    action :create do
      desc("Allows users of a project's account to create entries in the project cache.")
      allow([:authenticated_as_user, user_role: :user])

      desc("Allows the admin of a project's account to create entries in the project cache.")
      allow([:authenticated_as_user, user_role: :admin])

      desc("Allows the authenticated project to read the cache if it matches the project whose cache is being read.")

      allow([:authenticated_as_project, :projects_match])

      desc("Allows an account token with project:cache:write scope to create cache entries.")
      allow([:authenticated_as_account, scopes_permit: "project:cache:write"])
    end

    action :read do
      desc("Allows the authenticated subject to read a project's cache if the project is public.")
      allow(:public_project)

      desc("Allows users of a project's account to read the project cache.")
      allow([:authenticated_as_user, user_role: :user])

      desc("Allows the admin of a project's account to read the project cache.")
      allow([:authenticated_as_user, user_role: :admin])

      desc("Allows the authenticated project to read the cache if it matches the project whose cache is being read.")

      allow([:authenticated_as_project, :projects_match])

      desc("Allows users with ops access to read any cache.")
      allow([:authenticated_as_user, :ops_access])

      desc("Allows an account token with project:cache:read or project:cache:write scope to read cache.")
      allow([:authenticated_as_account, scopes_permit: "project:cache:read"])
      allow([:authenticated_as_account, scopes_permit: "project:cache:write"])
    end

    action :update do
      desc("Allows users of a project to update cache.")
      allow([:authenticated_as_user, user_role: :user])

      desc("Allows the admin of a project to update cache.")
      allow([:authenticated_as_user, user_role: :admin])

      desc("Allows the authenticated project to update cache if it matches the project.")
      allow([:authenticated_as_project, :projects_match])

      desc("Allows an account token with project:cache:write scope to update cache.")
      allow([:authenticated_as_account, scopes_permit: "project:cache:write"])
    end
  end

  object :registry do
    action :create do
      desc("Allows users of an account to create entries in its registry.")
      allow([:authenticated_as_user, user_role: :user])

      desc("Allows the admin of an account to create entries in its registry.")
      allow([:authenticated_as_user, user_role: :admin])

      desc(
        "Allows the authenticated account to read the account registry if it matches the account whose registry is being read."
      )

      allow([:authenticated_as_account, :accounts_match, scopes_permit: "account:registry:read"])

      desc("Allows the authenticated project to read the cache if it matches the project whose cache is being read.")

      allow([:authenticated_as_project, :accounts_match])
    end

    action :read do
      desc("Allows users of an account to read its registry.")
      allow([:authenticated_as_user, user_role: :user])

      desc("Allows the admin of an account to read its registry.")
      allow([:authenticated_as_user, user_role: :admin])

      desc(
        "Allows the authenticated account to read the account registry if it matches the account whose registry is being read."
      )

      allow([:authenticated_as_account, :accounts_match, scopes_permit: "account:registry:read"])
      allow([:authenticated_as_account, :accounts_match, scopes_permit: "account:registry:write"])

      desc("Allows the authenticated project to read the cache if it matches the project whose cache is being read.")

      allow([:authenticated_as_project, :accounts_match])

      desc("Allows users with ops access to read any registry.")
      allow([:authenticated_as_user, :ops_access])
    end
  end

  object :account do
    action :update do
      desc("Allows the admin of an account to update its settings.")
      allow([:authenticated_as_user, user_role: :admin])
    end

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

  object :qa_step do
    action :create do
      desc("Allows an account token with qa_step_create scope to create QA steps.")
      allow([:authenticated_as_account, scopes_permit: "project:qa_step:create"])
    end

    action :update do
      desc("Allows an account token with qa_step_update scope to update QA steps.")
      allow([:authenticated_as_account, scopes_permit: "project:qa_step:update"])
    end
  end

  object :qa_screenshot do
    action :create do
      desc("Allows an account token with qa_screenshot_create scope to create QA screenshots.")

      allow([:authenticated_as_account, scopes_permit: "project:qa_screenshot:create"])
    end
  end

  object :qa_run do
    action :update do
      desc("Allows an account token with qa_run_update scope to update a QA run.")
      allow([:authenticated_as_account, scopes_permit: "project:qa_run:update"])
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
    end

    action :read do
      desc("Allows the admin of an account to read invitations.")
      allow([:authenticated_as_user, user_role: :admin])

      desc("Allows users with ops access to read any invitations.")
      allow([:authenticated_as_user, :ops_access])
    end

    action :delete do
      desc("Allows the admin of an account to delete invitations.")
      allow([:authenticated_as_user, user_role: :admin])
    end
  end

  object :member do
    action :update do
      desc("Allows the admin of an account to update members.")
      allow([:authenticated_as_user, user_role: :admin])
    end

    action :delete do
      desc("Allows the admin of an account to delete members.")
      allow([:authenticated_as_user, user_role: :admin])
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

  object :ops do
    action :read do
      desc("Allows ops access for authorized users.")
      allow([:authenticated_as_user, :ops_access])
    end
  end
end
