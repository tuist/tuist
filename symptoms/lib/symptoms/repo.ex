defmodule Symptoms.Repo do
  @moduledoc """
  The evaluator's own PostgreSQL database (CNPG). It is the only writer of
  detection state; see `symptoms/README.md` "Systems of record".
  """
  use Ecto.Repo,
    otp_app: :symptoms,
    adapter: Ecto.Adapters.Postgres
end
