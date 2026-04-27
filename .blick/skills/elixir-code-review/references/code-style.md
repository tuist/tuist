# Elixir Code Style

## Naming Conventions

### Modules
- CamelCase: `MyApp.UserAccount`
- Acronyms as words: `MyApp.HTTPClient` not `MyApp.HttpClient`

### Functions
- snake_case: `fetch_user`, `parse_response`
- Predicate functions end with `?`: `valid?`, `empty?`
- Dangerous functions end with `!`: `save!`, `fetch!`

### Variables
- snake_case: `user_name`, `total_count`
- Unused variables prefixed with `_`: `_ignored`

## Formatting

### Pipe Chains

```elixir
# BAD - starts with function call
String.trim(input)
|> String.downcase()
|> String.split()

# GOOD - starts with data
input
|> String.trim()
|> String.downcase()
|> String.split()
```

### Function Ordering

```elixir
defmodule MyModule do
  # 1. Module attributes
  @moduledoc "..."
  @behaviour SomeBehaviour

  # 2. use/import/alias/require
  use GenServer
  import Guards
  alias MyApp.User
  require Logger

  # 3. Module attributes (constants)
  @timeout 5000

  # 4. Struct definition
  defstruct [:field]

  # 5. Public functions
  def public_function, do: ...

  # 6. Callback implementations
  @impl true
  def handle_call(...), do: ...

  # 7. Private functions
  defp private_helper, do: ...
end
```

### Multi-clause Functions

```elixir
# GOOD - clauses grouped together
def process(nil), do: {:error, :nil_input}
def process([]), do: {:ok, []}
def process(list) when is_list(list), do: {:ok, Enum.map(list, &transform/1)}

# BAD - clauses separated by other code
def process(nil), do: {:error, :nil_input}

defp helper, do: ...

def process([]), do: {:ok, []}  # Should be with other process/1 clauses
```

## Review Questions

1. Do module names follow CamelCase convention?
2. Do function names follow snake_case with appropriate suffixes?
3. Do pipe chains start with data, not function calls?
4. Are public functions grouped before private functions?
5. Are multi-clause functions grouped together?
