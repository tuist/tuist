defmodule Atlas.Repo do
  use Ecto.Repo,
    otp_app: :atlas,
    adapter: Ecto.Adapters.Postgres

  @impl true
  def default_options(_operation) do
    [prepare: :unnamed]
  end
end
