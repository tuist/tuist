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
      {TuistCommon.PromExPhoenixPlugin,
       router: CacheWeb.Router,
       endpoint: CacheWeb.Endpoint,
       duration_buckets: [10, 100, 500, 1000, 5000, 10_000, 30_000]},
      PromEx.Plugins.Oban,
      Cache.Xcode.PromExPlugin,
      Cache.KeyValue.PromExPlugin,
      Cache.XcodeModule.PromExPlugin,
      Cache.Repo.PromExPlugin,
      Cache.Finch.PromExPlugin,
      Cache.SQLiteBuffer.PromExPlugin,
      Cache.S3Transfers.PromExPlugin,
      Cache.S3.PromExPlugin,
      Cache.Authentication.PromExPlugin,
      TuistCommon.HTTP.TransportPromExPlugin
    ]
  end
end
