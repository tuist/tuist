defmodule Pulse.Runtime.Registry do
  @moduledoc false
  def child_spec(opts), do: Registry.child_spec(Keyword.update!(opts, :name, &Pulse.Runtime.name/1))
  def register_name({registry, key}, pid), do: Registry.register_name({Pulse.Runtime.name(registry), key}, pid)
  def unregister_name({registry, key}), do: Registry.unregister_name({Pulse.Runtime.name(registry), key})
  def whereis_name({registry, key}), do: Registry.whereis_name({Pulse.Runtime.name(registry), key})
  def send({registry, key}, message), do: Registry.send({Pulse.Runtime.name(registry), key}, message)
  def lookup(registry, key), do: Registry.lookup(Pulse.Runtime.name(registry), key)
  def select(registry, spec), do: Registry.select(Pulse.Runtime.name(registry), spec)
  def register(registry, key, value), do: Registry.register(Pulse.Runtime.name(registry), key, value)
  def unregister(registry, key), do: Registry.unregister(Pulse.Runtime.name(registry), key)
  def update_value(registry, key, fun), do: Registry.update_value(Pulse.Runtime.name(registry), key, fun)
  def count(registry), do: Registry.count(Pulse.Runtime.name(registry))
end
