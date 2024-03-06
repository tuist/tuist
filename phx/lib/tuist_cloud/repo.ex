defmodule TuistCloud.Repo do
  use Ecto.Repo,
    otp_app: :tuist_cloud,
    adapter: Ecto.Adapters.Postgres
end
