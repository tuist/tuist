[
  import_deps: [:ecto, :ecto_sql, :phoenix, :open_api_spex, :let_me],
  subdirectories: ["priv/*/migrations"],
  plugins: [Phoenix.LiveView.HTMLFormatter, Styler],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test,runner}/**/*.{heex,ex,exs}", "priv/*/seeds.exs"]
]
