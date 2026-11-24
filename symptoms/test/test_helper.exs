# Tests tagged `:db` need PostgreSQL (`mix ecto.setup`, then
# `mix test --include db`). Everything else runs without a database, so the
# application does not start the repo in test; it is started here only when
# DB tests are included.
Mimic.copy(Req)
Mimic.copy(Symptoms.Evidence.Combine)
Mimic.copy(Symptoms.Log)
Mimic.copy(Symptoms.Repo)
Mimic.copy(Symptoms.Sources.Pulse)

Code.require_file("support/data_case.exs", __DIR__)
Code.require_file("support/fake_source.exs", __DIR__)

ExUnit.start(exclude: [:db])

if :db in Keyword.get(ExUnit.configuration(), :include, []) do
  {:ok, _} = Supervisor.start_child(Symptoms.Supervisor, Symptoms.Repo)
  {:ok, _} = Supervisor.start_child(Symptoms.Supervisor, {Oban, Application.fetch_env!(:symptoms, Oban)})
  Ecto.Adapters.SQL.Sandbox.mode(Symptoms.Repo, :manual)
end
