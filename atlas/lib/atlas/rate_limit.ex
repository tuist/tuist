defmodule Atlas.RateLimit do
  @moduledoc """
  Fixed-window rate limiting, backed by an ETS table in the node.

  Counters are per node rather than shared, so with more than one replica the
  effective limit is the configured one times the replica count. That is fine
  for the traffic this guards, which is a public signup form rather than an
  API with a contractual limit.
  """

  use Hammer, backend: :ets
end
