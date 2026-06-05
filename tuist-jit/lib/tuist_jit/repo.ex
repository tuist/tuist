defmodule TuistJit.Repo do
  use Ecto.Repo,
    otp_app: :tuist_jit,
    adapter: Ecto.Adapters.Postgres
end
