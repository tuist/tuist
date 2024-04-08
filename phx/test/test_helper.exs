Mimic.copy(TuistCloud.Storage)
Mimic.copy(TuistCloud.Time)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(TuistCloud.Repo, :manual)
