defmodule Tuist.Time do
  @moduledoc """
  A module that provides functions to interact with time.
  """
  def utc_now do
    DateTime.utc_now()
  end

  def naive_utc_now do
    NaiveDateTime.utc_now()
  end
end
