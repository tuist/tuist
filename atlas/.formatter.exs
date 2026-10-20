[
  import_deps: [:ecto, :ecto_sql, :phoenix],
  subdirectories: ["priv/*/migrations"],
  plugins: [Quokka, Phoenix.LiveView.HTMLFormatter],
  inputs: ["*.{heex,ex,exs}", "{config,credo_checks,lib,test}/**/*.{heex,ex,exs}", "priv/*/seeds.exs"]
]
