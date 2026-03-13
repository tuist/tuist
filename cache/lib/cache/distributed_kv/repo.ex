defmodule Cache.DistributedKV.Repo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :cache,
    adapter: Ecto.Adapters.Postgres
end
