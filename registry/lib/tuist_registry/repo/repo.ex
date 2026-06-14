defmodule TuistRegistry.Repo do
  use Ecto.Repo,
    otp_app: :tuist_registry,
    adapter: Ecto.Adapters.SQLite3
end
