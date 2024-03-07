defmodule TuistCloud.Repo do
  use Ecto.Repo,
    otp_app: :tuist_cloud,
    adapter: Ecto.Adapters.Postgres,
    pool_timeout: 15000
end
