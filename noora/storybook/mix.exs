defmodule NooraStorybook.MixProject do
  use Mix.Project

  def project do
    [
      app: :noora_storybook,
      version: "0.1.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      elixirc_options: [check_cwd: false],
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  def application do
    [
      mod: {NooraStorybook.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.8.1"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
      {:floki, ">= 0.30.0", only: :test},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:jason, "~> 1.2"},
      {:phoenix_storybook, "~> 1.3"},
      {:bandit, "~> 1.12"},
      {:hackney, "~> 4.5.2", override: true},
      {:tailwind, "~> 0.4", runtime: false},
      {:noora, path: ".."}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      # Path dependencies inherit Storybook's compile lock, so Noora must be compiled last for
      # Phoenix's code reloader to see a current dependency manifest.
      "phx.server": ["compile", "cmd mix deps.compile noora --force", "phx.server"],
      "assets.setup": ["esbuild.install --if-missing", "tailwind.install --if-missing"],
      "assets.build": ["esbuild noora_storybook"],
      "assets.deploy": [
        "esbuild noora_storybook --minify",
        "tailwind storybook --minify",
        "phx.digest"
      ]
    ]
  end
end
