defmodule Atlas.Engineering.Errors.Availability do
  @moduledoc """
  Single source of truth for whether error tracking is available on this
  instance.
  """

  def enabled? do
    Application.get_env(:atlas, :clickhouse_enabled, false)
  end
end
