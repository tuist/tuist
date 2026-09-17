defmodule AtlasWeb.Engineering.ErrorsLive do
  @moduledoc """
  Placeholder LiveView for `/engineering/errors`. Full port from Hive
  (index/show/event) scheduled for follow-on PR.
  """

  use AtlasWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, gettext("Errors"))}
  end

  def render(assigns) do
    ~H"""
    <div class="p-8">
      <h1 class="text-2xl font-semibold">{gettext("Errors")}</h1>
      <p class="mt-4 text-neutral-500">
        {gettext("The Engineering Errors surface is being ported from Hive. Coming soon.")}
      </p>
    </div>
    """
  end
end
