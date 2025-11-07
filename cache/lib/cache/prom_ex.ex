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
      {PromEx.Plugins.Phoenix, router: CacheWeb.Router, endpoint: CacheWeb.Endpoint},
      PromEx.Plugins.Ecto,
      PromEx.Plugins.Oban,
      Cache.CAS.PromExPlugin,
      Cache.KeyValue.PromExPlugin
    ]
  end
end
