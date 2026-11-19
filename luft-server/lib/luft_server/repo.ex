defmodule LuftServer.Repo do
  use Ecto.Repo,
    otp_app: :luft_server,
    adapter: Ecto.Adapters.Postgres
end
