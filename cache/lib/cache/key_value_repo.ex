defmodule Cache.KeyValueRepo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :cache,
    adapter: Ecto.Adapters.SQLite3
end
