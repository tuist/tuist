defmodule SwiftRegistry.PromEx do
  @moduledoc """
  PromEx setup for the Swift registry service.
  """

  use PromEx, otp_app: :swift_registry

  @impl true
  def plugins do
    [
      PromEx.Plugins.Beam,
      {TuistCommon.PromExPhoenixPlugin,
       router: SwiftRegistryWeb.Router,
       endpoint: SwiftRegistryWeb.Endpoint,
       http_status_tag: :status_class,
       include_controller_action_tags: false,
       duration_buckets: [10, 100, 500, 1000, 5000, 10_000, 30_000]},
      PromEx.Plugins.Oban,
      SwiftRegistry.Repo.PromExPlugin,
      SwiftRegistry.Finch.PromExPlugin,
      SwiftRegistry.SQLiteBuffer.PromExPlugin,
      SwiftRegistry.S3Transfers.PromExPlugin,
      SwiftRegistry.S3.PromExPlugin,
      TuistCommon.HTTP.TransportPromExPlugin
    ]
  end
end
