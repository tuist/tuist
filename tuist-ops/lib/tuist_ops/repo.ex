defmodule TuistOps.Repo do
  use Ecto.Repo,
    otp_app: :tuist_ops,
    adapter: Ecto.Adapters.Postgres
end
