defmodule TuistWeb.BazelBuildsLive do
  @moduledoc false
  use TuistWeb, :live_view

  alias TuistWeb.BazelInvocationsLive

  def mount(params, session, socket) do
    socket =
      socket
      |> assign(:bazel_resource, dgettext("dashboard_projects", "Builds"))
      |> assign(:bazel_base_path, "builds")
      |> assign(:bazel_invocation_commands, ["build"])

    BazelInvocationsLive.mount(params, session, socket)
  end

  defdelegate handle_params(params, uri, socket), to: BazelInvocationsLive
  defdelegate handle_event(event, params, socket), to: BazelInvocationsLive
  defdelegate render(assigns), to: BazelInvocationsLive
end
