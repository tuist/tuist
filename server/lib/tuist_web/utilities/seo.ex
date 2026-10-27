defmodule TuistWeb.Utilities.SEO do
  @moduledoc """
  Shared canonical URLs and route-level indexing policy. Visibility and
  authorization must still be checked before indexing a dashboard response.
  """

  alias Tuist.Environment
  alias TuistWeb.Router

  def canonical_url(path) do
    path = URI.parse(path || "/").path || "/"

    path =
      case String.split(path, "/", trim: true) do
        [account, project, "analytics"] -> "/#{account}/#{project}"
        [account, project, "invocations", id] -> "/#{account}/#{project}/builds/invocations/#{id}"
        segments -> "/" <> Enum.join(segments, "/")
      end

    Environment.app_url(path: path)
  end

  def public_project_route?(path) do
    case Phoenix.Router.route_info(Router, "GET", path, "") do
      %{public_project: true} -> true
      _ -> false
    end
  end
end
