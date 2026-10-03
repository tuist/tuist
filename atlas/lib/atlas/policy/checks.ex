defmodule Atlas.Policy.Checks do
  def authenticated(%{current_user: %{id: _}}, _object), do: true
  def authenticated(_subject, _object), do: false
end
