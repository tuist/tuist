defmodule TuistWeb.BazelBuildInvocationLive do
  @moduledoc false
  use TuistWeb, :live_view

  alias TuistWeb.BazelInvocationLive

  def mount(params, session, socket) do
    socket =
      socket
      |> assign(:bazel_back_label, dgettext("dashboard_projects", "Builds"))
      |> assign(:bazel_back_path, "builds")
      |> assign(:bazel_detail_path, "builds/invocations")
      |> assign(:bazel_details_title, dgettext("dashboard_projects", "Details"))

    BazelInvocationLive.mount(params, session, socket)
  end

  defdelegate render(assigns), to: BazelInvocationLive
  defdelegate handle_params(params, uri, socket), to: BazelInvocationLive
  defdelegate handle_event(event, params, socket), to: BazelInvocationLive
end
