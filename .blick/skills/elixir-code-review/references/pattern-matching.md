# Pattern Matching

## With Clauses

### Always Handle Errors

```elixir
# BAD - no else clause
with {:ok, user} <- fetch_user(id),
     {:ok, account} <- fetch_account(user) do
  {:ok, account}
end
# Returns {:error, reason} tuple unhandled!

# GOOD - explicit error handling
with {:ok, user} <- fetch_user(id),
     {:ok, account} <- fetch_account(user) do
  {:ok, account}
else
  {:error, :not_found} -> {:error, :user_not_found}
  {:error, reason} -> {:error, reason}
end
```

### Use Tagged Tuples for Clarity

```elixir
# BAD - ambiguous which step failed
with {:ok, user} <- fetch_user(id),
     {:ok, posts} <- fetch_posts(user) do
  {:ok, posts}
else
  {:error, reason} -> {:error, reason}  # Which operation failed?
end

# GOOD - tagged for clarity with helper
defp tag_error({:error, reason}, tag), do: {:error, tag, reason}
defp tag_error(other, _tag), do: other

with {:ok, user} <- tag_error(fetch_user(id), :user),
     {:ok, posts} <- tag_error(fetch_posts(user), :posts) do
  {:ok, posts}
else
  {:error, :user, reason} -> {:error, {:user_fetch_failed, reason}}
  {:error, :posts, reason} -> {:error, {:posts_fetch_failed, reason}}
end
```

## Guards

### Prefer Guards Over Runtime Checks

```elixir
# BAD - runtime check
def process(value) do
  if is_binary(value) do
    String.upcase(value)
  else
    raise ArgumentError
  end
end

# GOOD - guard clause
def process(value) when is_binary(value) do
  String.upcase(value)
end
```

### Multiple Guards

```elixir
# GOOD - multiple function heads with guards
def categorize(n) when n < 0, do: :negative
def categorize(0), do: :zero
def categorize(n) when n > 0, do: :positive
```

## Destructuring

### In Function Heads

```elixir
# BAD - destructure in body
def process(user) do
  name = user.name
  email = user.email
  # ...
end

# GOOD - destructure in head
def process(%{name: name, email: email} = user) do
  # name and email available, plus full user if needed
end
```

### In Case Statements

```elixir
# GOOD - pattern match extracts what you need
case fetch_user(id) do
  {:ok, %User{name: name, active: true}} ->
    {:ok, "Active user: #{name}"}

  {:ok, %User{active: false}} ->
    {:error, :inactive}

  {:error, reason} ->
    {:error, reason}
end
```

## Review Questions

1. Do with statements have else clauses handling all error cases?
2. Are guards used instead of runtime type checks?
3. Is destructuring done in function heads where possible?
4. Are pattern matches exhaustive (no unhandled cases)?
