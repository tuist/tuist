defmodule TuistWeb.API.RequestParams do
  @moduledoc """
  Helpers for turning CastAndValidate-processed request bodies into the
  string-keyed, struct-free maps that Ecto changesets and downstream action
  handlers expect.
  """

  @doc """
  Normalises a request body for use as changeset attrs.

  CastAndValidate materialises named schemas (modules created via
  `OpenApiSpex.schema/1`) into structs, so request bodies arrive as a mix
  of plain maps, schema structs, lists, and atom-keyed nested maps. This
  helper strips struct wrappers, drops `nil` values so optional fields
  don't leak into persisted JSON, and rewrites all keys to strings —
  matching the shape our pattern-matching validators and action handlers
  already assume.
  """
  def normalize(%_{} = struct), do: struct |> Map.from_struct() |> normalize()

  def normalize(params) when is_map(params) do
    params
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new(fn {key, value} -> {to_string(key), normalize(value)} end)
  end

  def normalize(params) when is_list(params), do: Enum.map(params, &normalize/1)

  def normalize(value), do: value

  @doc """
  Flattens an `Ecto.Changeset`'s errors into a single human-readable string
  suitable for returning in a 422 response body.
  """
  def format_errors(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map_join(", ", fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
  end
end
