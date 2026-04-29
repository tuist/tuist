defmodule Tuist.SCIM.Filter do
  @moduledoc """
  Minimal SCIM 2.0 filter expression parser (RFC 7644 §3.4.2.2).

  Supports the subset that real-world IdPs (Okta, Azure AD, JumpCloud) actually
  send for User and Group provisioning:

    * `userName eq "alice@example.com"`
    * `externalId eq "abc-123"`
    * `displayName eq "Admins"`

  Returns `%{attribute: String.t(), op: :eq, value: String.t()}` on success or
  `:error` on anything else. Callers treat `:error` as "ignore the filter and
  return all results" to stay forgiving with non-conformant clients.
  """

  @pattern ~r/^\s*(?<attr>[a-zA-Z][a-zA-Z0-9]*)\s+(?<op>[a-zA-Z]+)\s+"(?<value>[^"]*)"\s*$/

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
end
