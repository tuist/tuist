defmodule Tuist.SCIM.Filter do
  @moduledoc """
  Minimal SCIM 2.0 filter expression parser (RFC 7644 §3.4.2.2).

  Supports the subset that real-world IdPs (Okta, Azure AD, JumpCloud) actually
  send for User and Group provisioning:

    * `userName eq "alice@example.com"`
    * `externalId eq "abc-123"`
    * `displayName eq "Admins"`
    * `members[value eq "user-id"]`

  Returns `%{attribute: String.t(), op: :eq, value: String.t()}` on success or
  `:error` on malformed/unsupported expressions. Controllers return SCIM
  `invalidFilter` responses for unsupported filters.
  """

  @pattern ~r/^\s*(?<attr>[a-zA-Z][a-zA-Z0-9]*)\s+(?<op>[a-zA-Z]+)\s+"(?<value>[^"]*)"\s*$/
  @member_value_path_pattern ~r/^\s*members\s*\[\s*value\s+eq\s+"(?<value>[^"]*)"\s*\]\s*$/i

  def parse(nil), do: nil
  def parse(""), do: nil

  def parse(expr) when is_binary(expr) do
    case Regex.named_captures(@pattern, expr) do
      %{"attr" => attr, "op" => op, "value" => value} ->
        case String.downcase(op) do
          "eq" -> %{attribute: attr, op: :eq, value: value}
          _ -> :error
        end

      nil ->
        :error
    end
  end

  def parse(_), do: :error

  def member_ids_from_path(path) when is_binary(path) do
    case Regex.named_captures(@member_value_path_pattern, path) do
      %{"value" => value} -> [value]
      nil -> []
    end
  end

  def member_ids_from_path(_), do: []
end
