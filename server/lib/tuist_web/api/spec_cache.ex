defmodule TuistWeb.API.SpecCache do
  @moduledoc """
  `OpenApiSpex.Plug.PersistentTermCache`, written once per spec.

  The default cache puts the spec with its operation lookup again for every
  controller action it resolves for the first time, and each put copies the
  whole spec into the literal area, where the copy it replaces lingers until
  every process has been scanned. A freshly booted server resolves every API
  action within seconds, which filled the literal area and crashed the VM
  (`literal_alloc: Cannot allocate`).

  The first put stores the lookup with every routed controller action already
  resolved, the state the default cache ends up in, so requests find their
  operation with a map lookup and nothing is put again.
  """
  @behaviour OpenApiSpex.Plug.Cache

  alias OpenApiSpex.Operation
  alias OpenApiSpex.Plug.PersistentTermCache
  alias TuistWeb.Router

  @impl true
  def get(spec_module), do: PersistentTermCache.get(spec_module)

  @impl true
  def put(spec_module, {spec, operation_lookup}) do
    if is_nil(get(spec_module)) do
      PersistentTermCache.put(spec_module, {spec, Map.merge(controller_actions(operation_lookup), operation_lookup)})
    end

    :ok
  end

  @impl true
  def erase(spec_module), do: PersistentTermCache.erase(spec_module)

  defp controller_actions(operation_lookup) do
    for %{plug: controller, plug_opts: action} <- Router.__routes__(),
        is_atom(action),
        Code.ensure_loaded?(controller),
        function_exported?(controller, :open_api_operation, 1),
        %Operation{operationId: operation_id} <- [controller.open_api_operation(action)],
        %Operation{} = operation <- [Map.get(operation_lookup, operation_id)],
        into: %{},
        do: {{controller, action}, operation}
  end
end
