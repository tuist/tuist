# Documentation

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

### @doc with @spec

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
@spec fetch_user(pos_integer()) :: {:ok, User.t()} | {:error, :not_found}
def fetch_user(id) when is_integer(id) and id > 0 do
  # ...
end
```

### @spec Patterns

```elixir
# Basic types
@spec add(integer(), integer()) :: integer()

# Union types
@spec parse(String.t()) :: {:ok, map()} | {:error, term()}

# Custom types
@type result :: {:ok, t()} | {:error, reason()}
@spec fetch(id()) :: result()

# Keyword options
@spec start_link(keyword()) :: GenServer.on_start()

# When clauses for type variables
@spec map(list(a), (a -> b)) :: list(b) when a: term(), b: term()
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

1. Do all public modules have @moduledoc?
2. Do all public functions have @doc and @spec?
3. Are doctests used for pure, deterministic functions?
4. Do @specs accurately reflect function signatures?
