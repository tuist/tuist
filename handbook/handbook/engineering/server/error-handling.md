---
{
  "title": "Error handling",
  "titleTemplate": ":title | Server | Engineering | Tuist Handbook",
  "description": "Our approach to error handling using Elixir on the server."
}
---
# Error handling

Matching Elixir conventions, Tuist server functions should return success and errors as values in form of `{:ok, result}` and `{:error, reason}` tuples.  
In order for us to leverage automatic error handling, we follow a standardized error format that is used across both domain and interface logic.

## Error format

1. Any successful function execution should return `{:ok, result}`, where `result` can be any value.
2. Any error where the function execution is not successful should return `{:error, reason}`, where `reason` is a string describing the error.

For generic errors, the `reason` should be an atom describing the error code:

1. `:unauthenticated` - There is no authenticated user.
2. `:unauthorized` - The authenticated user is not authorized to perform the requested action.
3. `:not_found` - The requested resource was not found.

> [!NOTE]
> In our controller error handling, `:unauthenticated` maps to HTTP error `401` and `:unauthorized` maps to HTTP error `403`. This does not
> match the HTTP status code name, but matches the cause of the error more closely.

For input errors, the preference is to return an `%Ecto.Changeset{}` containing the error messages pertaining to the related input fields.  
For all other errors, `reason` should be a string describing the error.

These error formats allow us to handle errors in a consistent way across domain logic and controllers, making it possible to simply return
the errors inside our controller actions and have automatic formatting and status code handling.

## Controller example

```elixir
with {:ok, account} <- get_account(handle), # returns {:ok, account} or {:error, :not_found}
     :ok <- can(conn.assigns.current_user, :update, account, :organization), # returns :ok or {:error, :unauthorized}
     {:ok, account} <- Accounts.update_account(account, params) do # returns {:ok, account} or {:error, changeset}
  conn
  |> put_status(:ok)
  |> json(%{id: account.id, handle: account.name})
end
```

Since the `with` clause returns all non-matching values as-is, the error paths will be passed onto the controller which will handle them
generically.
