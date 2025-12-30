database = Application.get_env(:tuist, Tuist.Repo)[:database]
Ecto.Adapters.SQL.query!(Tuist.Repo, "ALTER DATABASE #{database} SET TIMEZONE='UTC';", [])
