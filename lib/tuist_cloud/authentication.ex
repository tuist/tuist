defmodule TuistCloud.Authentication do
  @moduledoc ~S"""
  A module to deal with authentication in the system.
  """
  alias TuistCloud.Projects
  alias TuistCloud.Accounts

  def authenticated_subject(token) do
    project = Projects.get_project_by_token(token)
    user = Accounts.get_user_by_token(token)

    case {project, user} do
      {nil, nil} -> nil
      {project, nil} -> {:project, project}
      {nil, user} -> {:user, user}
    end
  end
end
