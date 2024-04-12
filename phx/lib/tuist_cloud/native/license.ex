defmodule TuistCloud.Native.License do
  @moduledoc """
  This module defines the metadata of a license
  """
  defstruct [:id, :features, :expiration_date]

  def expired?(license) do
    Date.utc_today() > Date.from_iso8601(license.expiration_date)
  end
end
