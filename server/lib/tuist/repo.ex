defmodule Tuist.Repo do
  use Ecto.Repo,
    otp_app: :tuist,
    adapter: Ecto.Adapters.Postgres,
    pool_timeout: 15_000
end
