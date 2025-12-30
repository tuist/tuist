defmodule Tuist.Zip do
  @moduledoc ~S"""
  A module to deal with zips.
  """
  def create(name, file_list, options) do
    :zip.create(name, file_list, options)
  end

  def extract(archive, options) do
    :zip.extract(archive, options)
  end
end
