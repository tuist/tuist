defmodule TuistWeb.AppsignalTracePlug do
  @moduledoc ~S"""
  A module that wraps a plug and traces its execution using AppSignal's tracing API.
  """
  def init(opts), do: opts

  def call(conn, opts) do
    module = List.first(opts)
    module_opts = if length(opts) == 1, do: [], else: module.init(List.last(opts))

    if Tuist.Environment.error_tracking_enabled?() do
      Appsignal.instrument(module |> to_string(), fn ->
        module.call(conn, module_opts)
      end)
    else
      module.call(conn, module_opts)
    end
  end
end
