defmodule AtlasWeb.Engineering.ProjectsLive do
  @moduledoc """
  Placeholder LiveView for `/engineering/projects`. The full port from
  Hive's `HiveWeb.ProjectLive.Index` + `.Show` is scheduled for a
  follow-on PR — see `scratchpad/port-summary.md`.
  """

  use AtlasWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, gettext("Projects"))}
  end

  def render(assigns) do
    ~H"""
    <div class="p-8">
      <h1 class="text-2xl font-semibold">{gettext("Projects")}</h1>
      <p class="mt-4 text-neutral-500">
        {gettext("The Engineering Projects surface is being ported from Hive. Coming soon.")}
      </p>
    </div>
    """
  end
end
