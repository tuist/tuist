defmodule NooraStorybook.MixProject do
  use Mix.Project

  def project do
    [
      app: :noora_storybook,
      version: "0.1.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
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
      {:phoenix_storybook, "== 0.9.3"},
      {:bandit, "~> 1.5"},
      {:tailwind, "~> 0.4", runtime: false},
      {:noora, path: ".."}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
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
