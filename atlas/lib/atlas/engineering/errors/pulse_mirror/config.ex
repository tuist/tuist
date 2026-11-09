defmodule Atlas.Engineering.Errors.PulseMirror.Config do
  @moduledoc false

  alias Atlas.Engineering.Errors.PulseMirror

  def options, do: Application.get_env(:atlas, PulseMirror, [])
  def table, do: :ets.whereis(PulseMirror)
end
