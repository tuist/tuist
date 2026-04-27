# OTP Basics

## GenServer

### Use handle_continue for Expensive Init

```elixir
# BAD - blocks supervisor during init
def init(args) do
  data = expensive_operation()  # Blocks!
  {:ok, data}
end

# GOOD - defers expensive work
def init(args) do
  {:ok, %{data: nil}, {:continue, :load_data}}
end

@impl true
def handle_continue(:load_data, state) do
  data = expensive_operation()
  {:noreply, %{state | data: data}}
end
```

### Call vs Cast

```elixir
# call - synchronous, returns result
def get_value(pid) do
  GenServer.call(pid, :get_value)
end

# cast - asynchronous, fire-and-forget
def increment(pid) do
  GenServer.cast(pid, :increment)
end
```

**When to use each:**
- `call` - Need the result, need confirmation, queries
- `cast` - Fire-and-forget, notifications, can't block caller

### Timeouts

```elixir
# Always consider timeouts for calls
def fetch_data(pid) do
  GenServer.call(pid, :fetch_data, 10_000)  # 10 second timeout
end

# Handle timeout in caller
case GenServer.call(pid, :fetch, 5_000) do
  {:ok, data} -> data
  {:error, reason} -> handle_error(reason)
rescue
  exit -> {:error, :timeout}
end
```

## Supervisor

### Restart Strategies

| Strategy | When to Use |
|----------|-------------|
| `:one_for_one` | Children are independent |
| `:one_for_all` | Children are interdependent |
| `:rest_for_one` | Later children depend on earlier |

### Child Specs

```elixir
# GOOD - explicit child spec
children = [
  {MyWorker, [name: :worker, arg: value]},
  {DynamicSupervisor, name: MyApp.DynamicSup, strategy: :one_for_one}
]

Supervisor.init(children, strategy: :one_for_one)
```

## Common Anti-Patterns

### Blocking in Callbacks

```elixir
# BAD - blocks the GenServer
@impl true
def handle_call(:fetch_external, _from, state) do
  result = HTTPClient.get!(url)  # Blocks all other messages!
  {:reply, result, state}
end

# GOOD - use Task for async work
@impl true
def handle_call(:fetch_external, from, state) do
  Task.async(fn -> HTTPClient.get!(url) end)
  {:noreply, %{state | pending: from}}
end

@impl true
def handle_info({ref, result}, %{pending: from} = state) do
  GenServer.reply(from, result)
  {:noreply, %{state | pending: nil}}
end
```

### Single Process Bottleneck

```elixir
# BAD - all requests through one GenServer
defmodule Cache do
  use GenServer
  def get(key), do: GenServer.call(__MODULE__, {:get, key})
  def put(key, val), do: GenServer.call(__MODULE__, {:put, key, val})
end

# GOOD - use ETS for read-heavy workloads
defmodule Cache do
  def get(key), do: :ets.lookup(:cache, key)
  def put(key, val), do: :ets.insert(:cache, {key, val})
end
```

## Review Questions

1. Does GenServer init do expensive work synchronously?
2. Are call/cast used appropriately (sync vs async)?
3. Is there a single GenServer becoming a bottleneck?
4. Do supervisors use appropriate restart strategies?
