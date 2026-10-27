[
  import_deps: [:phoenix, :ecto, :ecto_sql, :phoenix_live_view],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}"],
  line_length: 120,
  plugins: [Styler, Phoenix.LiveView.HTMLFormatter]
]
