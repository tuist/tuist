defmodule Condukt.Sandbox.NetworkPolicy.Event do
  @moduledoc """
  An event the egress runtime emits as telemetry per request lifecycle.

  The egress sidecar emits an event when a request starts (`:request_opened`),
  when policy decides on the request (`:request_allowed` or `:request_denied`),
  when its outcome is known (`:request_closed`), and when an allowed request
  never completes cleanly (`:request_failed`, e.g. the workspace rejected the
  session CA or the upstream was unreachable).

  Most callers only care about `:request_closed` and `:request_failed`. The
  lifecycle separation exists so suspension-point gating (held between
  `:request_opened` and the decision) can surface live in-flight requests to a
  UI or human reviewer.

  `:matched_rule` carries decision provenance on `:request_allowed` /
  `:request_denied`: `%{index: non_neg_integer, kind: :allow | :deny | :decide}`.
  It is `nil` for the default action and for lifecycle-only events.
  """

  alias Condukt.Sandbox.NetworkPolicy.Request

  defstruct [:kind, :request, :reason, :matched_rule, at: nil]

  @doc """
  Builds an event from a decoded `Condukt.Sandbox.NetworkPolicy.Request` plus kind.
  """
  def new(kind, %Request{} = request, opts \\ []) do
    %__MODULE__{
      kind: kind,
      request: request,
      reason: Keyword.get(opts, :reason),
      matched_rule: Keyword.get(opts, :matched_rule),
      at: Keyword.get(opts, :at, DateTime.utc_now())
    }
  end

  @doc """
  Normalises the wire `matched_rule` object into
  `%{index: non_neg_integer, kind: atom}`, or `nil` when absent.
  """
  def decode_matched_rule(%{"index" => index, "kind" => kind}) when is_integer(index) do
    %{index: index, kind: normalize_kind(kind)}
  end

  def decode_matched_rule(_), do: nil

  defp normalize_kind("allow"), do: :allow
  defp normalize_kind("deny"), do: :deny
  defp normalize_kind("decide"), do: :decide
  defp normalize_kind(other) when is_binary(other), do: other
end
