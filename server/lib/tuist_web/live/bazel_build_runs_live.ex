defmodule TuistWeb.BazelBuildRunsLive do
  @moduledoc false
  use TuistWeb, :live_view

  alias TuistWeb.BazelInvocationsLive

  def mount(params, session, socket) do
    socket =
      socket
      |> assign(:bazel_resource, dgettext("dashboard_projects", "Build Runs"))
      |> assign(:bazel_resource_kind, :builds)
      |> assign(:bazel_base_path, "builds/build-runs")
      |> assign(:bazel_invocation_commands, ["build"])
      |> assign(:bazel_show_analytics, false)

    BazelInvocationsLive.mount(params, session, socket)
  end

  defdelegate handle_params(params, uri, socket), to: BazelInvocationsLive
  defdelegate handle_event(event, params, socket), to: BazelInvocationsLive
  defdelegate render(assigns), to: BazelInvocationsLive
end
