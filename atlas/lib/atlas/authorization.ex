defmodule Atlas.Authorization do
  @moduledoc """
  Scope catalog and helpers for Atlas' role-based authorization.

  A scope is `"<area>:<action>"` where `action` is `read` or `write`. Holding
  the write scope for an area implies holding the read scope for the same area.

  Areas are the top-level Atlas concerns that can be gated independently. Roles
  are named collections of scopes assigned to users; a user's effective scopes
  are the union across every role they hold.
  """

  @areas %{
    "accounts" => "Commercial accounts, contacts, and feature interests",
    "assets" => "Hardware assets, data centers, and financings",
    "audit" => "Audit trail for changes across Atlas",
    "briefs" => "Leadership briefs and brief-driven action items",
    "contracts" => "Enterprise contract templates and generation",
    "documents" => "The document library and document downloads",
    "engineering" => "Engineering projects, domains, errors, and postmortems",
    "finance" => "Finance transactions, invoices, and reconciliation",
    "gtm" => "GTM opportunities, outreach, and campaigns",
    "inference" => "LLM inference relay tokens, profiles, and providers",
    "insurance" => "Insurance policies, members, and claims",
    "letters" => "Postal letters and outbound mailings",
    "licenses" => "Self-hosted license issuance and checkout",
    "notes" => "Shared Markdown notes",
    "support" => "Customer support threads and messages",
    "admin" => "Admin section access (users, roles, identities, sessions, MCP)"
  }

  @actions [:read, :write]

  @doc "All known areas, as `%{area => description}`."
  def areas, do: @areas

  @doc "All known area slugs, sorted alphabetically."
  def area_slugs, do: @areas |> Map.keys() |> Enum.sort()

  @doc "The two actions a scope may take."
  def actions, do: @actions

  @doc "Every valid scope string, sorted."
  def all_scopes do
    for area <- area_slugs(), action <- @actions, do: scope(area, action)
  end

  @doc "Build a scope string from an area and action."
  def scope(area, action) when is_binary(area) and action in @actions do
    "#{area}:#{action}"
  end

  @doc """
  Split a scope back into `{area, action}` as strings. Returns `:error` for
  values that do not match a known area/action pair.
  """
  def parse(scope) when is_binary(scope) do
    case String.split(scope, ":", parts: 2) do
      [area, action] when action in ~w(read write) ->
        if Map.has_key?(@areas, area), do: {:ok, area, String.to_existing_atom(action)}, else: :error

      _other ->
        :error
    end
  end

  def parse(_scope), do: :error

  @doc """
  Expand a list of granted scopes so that every `write` scope also grants the
  matching `read` scope. Duplicates are removed.
  """
  def expand(scopes) when is_list(scopes) do
    scopes
    |> Enum.flat_map(fn scope ->
      case parse(scope) do
        {:ok, area, :write} -> [scope(area, :read), scope(area, :write)]
        {:ok, _area, :read} -> [scope]
        :error -> []
      end
    end)
    |> Enum.uniq()
  end

  @doc "True if `granted` (already expanded or not) covers `required`."
  def granted?(granted, required) when is_list(granted) and is_binary(required) do
    required in expand(granted)
  end

  @doc "The full scope set, used to seed the top-level `executive` role."
  def executive_scopes, do: all_scopes()
end
