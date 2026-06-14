defmodule TuistRegistry.PromEx do
  @moduledoc """
  PromEx setup for the Swift registry service.
  """

  use PromEx, otp_app: :tuist_registry

  @impl true
  def plugins do
    [
      PromEx.Plugins.Beam,
      {TuistCommon.PromExPhoenixPlugin,
       router: TuistRegistryWeb.Router,
       endpoint: TuistRegistryWeb.Endpoint,
       http_status_tag: :status_class,
       include_controller_action_tags: false,
       duration_buckets: [10, 100, 500, 1000, 5000, 10_000, 30_000]},
      PromEx.Plugins.Oban,
      TuistRegistry.Repo.PromExPlugin,
      TuistRegistry.Finch.PromExPlugin,
      TuistRegistry.SQLiteBuffer.PromExPlugin,
      TuistRegistry.S3Transfers.PromExPlugin,
      TuistRegistry.S3.PromExPlugin,
      TuistCommon.HTTP.TransportPromExPlugin
    ]
  end
end
