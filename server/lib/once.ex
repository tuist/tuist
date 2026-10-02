defmodule Once do
  @moduledoc """
  Boundary for the generated `once.events.v1` protobuf and gRPC modules.

  Nothing here is hand-written: `Once.Events.V1.*` is regenerated from
  `priv/proto/once/events/v1/events.proto`, so the boundary exists only to
  give those modules a home and let `Tuist.OnceEvents` reference them.
  """
  use Boundary, top_level?: true, deps: [], exports: :all
end
