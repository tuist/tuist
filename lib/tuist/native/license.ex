defmodule Tuist.Native.License do
  @moduledoc """
  This module defines the metadata of a license
  """
  @enforce_keys [:id, :features, :expiration_date, :valid]
  defstruct [:id, :features, :expiration_date, :valid]
end
