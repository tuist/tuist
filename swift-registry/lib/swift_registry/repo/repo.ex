defmodule SwiftRegistry.Repo do
  use Ecto.Repo,
    otp_app: :swift_registry,
    adapter: Ecto.Adapters.SQLite3
end
