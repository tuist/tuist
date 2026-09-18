defmodule Atlas.Engineering.Errors.Policy do
  @moduledoc """
  Authorization rules for the error tracking surface.

  The ingest endpoint (`POST /api/:project_id/envelope/`) is authenticated
  by DSN public key, not by session, so it is not covered by this policy.
  """

  use LetMe.Policy, check_module: Atlas.Engineering.Errors.Policy.Checks, error: :unauthorized

  object :error_issue do
    action :read do
      allow(:member)
    end

    action :resolve do
      allow(:member)
    end

    action :ignore do
      allow(:member)
    end
  end

  object :error_project_key do
    action :read do
      allow(:member)
    end

    action :create do
      allow(:admin)
    end
  end
end
