defmodule Atlas.Engineering.Errors.Policy.Checks do
  @moduledoc """
  Checks referenced by `Atlas.Engineering.Errors.Policy`.

  Atlas has no per-org membership model today; every authenticated user is
  treated as a member, and executives count as admins.
  """

  def member(%{role: role}, _object) when role in [:executive, :employee, "executive", "employee"], do: true

  def member(%{id: _}, _object), do: true
  def member(_subject, _object), do: false

  def admin(%{role: :executive}, _object), do: true
  def admin(%{role: "executive"}, _object), do: true
  def admin(_subject, _object), do: false
end
