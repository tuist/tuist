# Documentation

> **Repository override:** this codebase intentionally does **not** use
> typespecs. Treat any `@spec`/`@type`/`@typep` content below as
> historical context only — do **not** flag missing typespecs in review,
> and do not suggest adding them.

## Module Documentation

### @moduledoc

```elixir
defmodule MyApp.UserManager do
  @moduledoc """
  Manages user lifecycle operations including creation, updates, and deletion.

  This module provides the primary interface for user management and delegates
  to the appropriate subsystems for persistence and notification.

  ## Examples

      iex> UserManager.create(%{name: "Alice", email: "alice@example.com"})
      {:ok, %User{}}

  ## Configuration

  Requires `:user_manager` config with `:repo` key.
  """
end
```

### When to Use @moduledoc false

```elixir
# Valid uses of @moduledoc false:
# 1. Private implementation modules
defmodule MyApp.Internal.Helper do
  @moduledoc false
  # ...
end

# 2. Protocol implementations
defimpl Jason.Encoder, for: MyStruct do
  @moduledoc false
  # ...
end
```

## Function Documentation

### @doc

```elixir
@doc """
Fetches a user by their unique identifier.

Returns `{:ok, user}` if found, `{:error, :not_found}` otherwise.

## Examples

    iex> fetch_user(123)
    {:ok, %User{id: 123}}

    iex> fetch_user(-1)
    {:error, :not_found}
"""
def fetch_user(id) when is_integer(id) and id > 0 do
  # ...
end
```

## Doctests

### When to Use

```elixir
# GOOD - pure function, predictable output
@doc """
Calculates the factorial of n.

## Examples

    iex> Math.factorial(0)
    1

    iex> Math.factorial(5)
    120
"""
def factorial(0), do: 1
def factorial(n), do: n * factorial(n - 1)
```

### When NOT to Use

```elixir
# BAD - side effects, unpredictable
@doc """
Creates a user in the database.

## Examples

    iex> create_user(%{name: "Test"})  # Don't doctest DB operations!
    {:ok, %User{}}
"""
```

## Review Questions

1. Do public-API modules (controllers, contexts, public boundaries) have @moduledoc?
2. Do public-API functions have @doc?
3. Are doctests used for pure, deterministic functions?
