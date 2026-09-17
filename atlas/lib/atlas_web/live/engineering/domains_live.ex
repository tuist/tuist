defmodule AtlasWeb.Engineering.DomainsLive do
  @moduledoc """
  Placeholder LiveView for `/engineering/domains`. Full port from Hive
  scheduled for follow-on PR.
  """

  use AtlasWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, gettext("Domains"))}
  end

  def render(assigns) do
    ~H"""
    <div class="p-8">
      <h1 class="text-2xl font-semibold">{gettext("Domains")}</h1>
      <p class="mt-4 text-neutral-500">
        {gettext("The Engineering Domains surface is being ported from Hive. Coming soon.")}
      </p>
    </div>
    """
  end
end
