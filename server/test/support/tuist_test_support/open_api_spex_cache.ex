defmodule TuistTestSupport.OpenApiSpexCache do
  @moduledoc """
  `OpenApiSpex.Plug.PersistentTermCache`, written once per spec.

  The default cache puts the spec with its operation lookup again for every
  controller action it resolves for the first time, and each put copies the
  whole spec into the literal area, where the copy it replaces lingers while
  any process still refers to it. Across the controller tests that filled the
  area and crashed the VM (`literal_alloc: Cannot allocate`). Keeping the
  first put leaves each action to be resolved by its operation id on every
  request, which is a map lookup.
  """
  @behaviour OpenApiSpex.Plug.Cache

  alias OpenApiSpex.Plug.PersistentTermCache

  @impl true
  def get(spec_module), do: PersistentTermCache.get(spec_module)

  @impl true
  def put(spec_module, spec) do
    if is_nil(get(spec_module)), do: PersistentTermCache.put(spec_module, spec)
    :ok
  end

  @impl true
  def erase(spec_module), do: PersistentTermCache.erase(spec_module)
end
