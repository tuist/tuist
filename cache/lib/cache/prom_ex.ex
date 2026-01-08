defmodule Cache.PromEx do
  @moduledoc """
  PromEx setup for the Cache service.

  Exposes a `/metrics` endpoint via `PromEx.Plug` and registers both
  built-in plugins (Beam, Phoenix, Ecto, Oban) and custom CAS metrics.
  """

  use PromEx, otp_app: :cache

  @impl true
  def plugins do
    [
      PromEx.Plugins.Beam,
      {PromEx.Plugins.Phoenix,
       router: CacheWeb.Router,
       endpoint: CacheWeb.Endpoint,
       duration_buckets: [10, 100, 500, 1000, 5000, 10_000, 30_000]},
      PromEx.Plugins.Ecto,
      PromEx.Plugins.Oban,
      Cache.CAS.PromExPlugin,
      Cache.KeyValue.PromExPlugin,
      Cache.Module.PromExPlugin,
      Cache.S3Transfers.PromExPlugin
    ]
  end
end
