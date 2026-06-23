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
      {TuistCommon.Finch.PromExPlugin,
       prefix: :tuist_registry, finch_name: TuistRegistry.Finch, pools_module: TuistRegistry.Finch.Pools},
      {TuistCommon.S3.PromExPlugin, prefix: :tuist_registry},
      TuistRegistry.Swift.PromExPlugin,
      TuistCommon.HTTP.TransportPromExPlugin
    ]
  end
end
