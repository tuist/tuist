defmodule Pulse.Runtime.ProcessGroup do
  @moduledoc false
  def join(scope, group, pid), do: :pg.join(Pulse.Runtime.name(scope), group, pid)
  def leave(scope, group, pid), do: :pg.leave(Pulse.Runtime.name(scope), group, pid)
  def get_members(scope, group), do: :pg.get_members(Pulse.Runtime.name(scope), group)
  def get_local_members(scope, group), do: :pg.get_local_members(Pulse.Runtime.name(scope), group)
end
