defmodule Tuist.MCP.Components.Tools.ListProjects do
  @moduledoc """
  List all projects accessible to the authenticated user.
  """

  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response
  alias Tuist.MCP.Authorization
  alias Tuist.Projects

  schema do
  end

  @impl true
  def execute(_arguments, frame) do
    subject = Authorization.authenticated_subject(frame.assigns)
    projects = Projects.list_accessible_projects(subject, preload: [:account])

    data =
      Enum.map(projects, fn project ->
        %{
          id: project.id,
          name: project.name,
          account_handle: project.account.name,
          full_handle: "#{project.account.name}/#{project.name}"
        }
      end)

    {:reply, Response.json(Response.tool(), data), frame}
  end
end
