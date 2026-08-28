defmodule TuistWeb.BazelInvocationLogsController do
  use TuistWeb, :controller

  alias Tuist.Bazel
  alias TuistWeb.Errors.NotFoundError

  def download(%{assigns: %{selected_project: project}} = conn, %{"invocation_id" => invocation_id}) do
    logs = Bazel.invocation_logs(project.id, invocation_id)

    if logs == [] do
      raise NotFoundError, dgettext("dashboard_projects", "Bazel invocation logs not found.")
    end

    conn
    |> put_resp_content_type("text/plain")
    |> put_resp_header("content-disposition", ~s(attachment; filename="bazel-invocation.log"))
    |> send_resp(:ok, Enum.map_join(logs, "", & &1.message))
  end
end
