defmodule TuistCloud.Time do
  @moduledoc """
  A module that provides functions to interact with time.
  """
  def utc_now do
    DateTime.utc_now()
  end
end
