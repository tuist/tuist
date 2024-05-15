defmodule TuistCloud.Authentication do
  @moduledoc ~S"""
  A module to deal with authentication in the system.
  """
  alias TuistCloud.Projects
  alias TuistCloud.Accounts

  def authenticated_subject(token) do
    project = Projects.get_project_by_token(token)
    account = Accounts.get_user_by_token(token)

    case {project, account} do
      {nil, nil} -> nil
      {project, nil} -> {:project, project}
      {nil, account} -> {:user, account}
    end
  end
end
