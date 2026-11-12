defmodule Pulse.LogQL.StreamMatchers do
  @moduledoc """
  Storage form of a LogQL stream selector, shared by log queries and label
  discovery so both select exactly the same streams.

  Like Loki (and Prometheus), `=~` and `!~` match the whole label value:
  `{app=~"api"}` selects `api`, not `api-gateway`. Patterns are anchored
  here once, in a form both the Rust and PCRE engines accept.

  An exact `service`/`service_name` matcher moves to the dedicated
  `service` option, which reads the dictionary-encoded promoted column.
  """

  alias Pulse.LogQL.AST

  @type storage_matcher :: {String.t(), :eq | :neq | :re | :nre, String.t()}

  @spec split([AST.Matcher.t()]) :: {String.t() | nil, [storage_matcher()]}
  def split(matchers) do
    {service, rest} =
      Enum.reduce(matchers, {nil, []}, fn
        %AST.Matcher{name: name, op: :eq, value: value}, {nil, acc} when name in ["service", "service_name"] ->
          {value, acc}

        matcher, {service, acc} ->
          {service, [to_tuple(matcher) | acc]}
      end)

    {service, Enum.reverse(rest)}
  end

  @doc "Anchor a label-matcher regex so it must match the complete value."
  @spec anchor(String.t()) :: String.t()
  defdelegate anchor(pattern), to: Pulse.QueryRegex

  defp to_tuple(%AST.Matcher{name: name, op: op, value: value}) when op in [:re, :nre], do: {name, op, anchor(value)}
  defp to_tuple(%AST.Matcher{name: name, op: op, value: value}), do: {name, op, value}
end
