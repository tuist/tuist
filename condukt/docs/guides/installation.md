# Installation

Add `:condukt` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:condukt, "~> 1.5"}
  ]
end
```

Then fetch dependencies:

```sh
mix deps.get
```

Condukt is designed to live inside your own OTP supervision tree. Continue with
[Getting Started](getting-started.md) to define your first agent.
