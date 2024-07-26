defmodule Tuist.Native.License do
  @moduledoc """
  This module defines the metadata of a license
  """
  defstruct [:id, :features, :expiration_date]

  def expired?(license) do
    if license.expiration_date == "none" do
      false
    else
      {:ok, expiration_date} = Date.from_iso8601(license.expiration_date)
      Date.after?(Tuist.Date.utc_today(), expiration_date)
    end
  end
end
