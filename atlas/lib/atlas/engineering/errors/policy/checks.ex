defmodule Atlas.Engineering.Errors.Policy.Checks do
  @moduledoc """
  Checks referenced by `Atlas.Engineering.Errors.Policy`.

  Atlas has no per-org membership model today; every authenticated user is
  treated as a member, and callers with the `engineering:write` scope count as
  admins.
  """

  alias Atlas.Users

  def member(%{id: _}, _object), do: true
  def member(_subject, _object), do: false

  def admin(%Atlas.Users.User{} = user, _object), do: Users.has_scope?(user, "engineering:write")
  def admin(_subject, _object), do: false
end
