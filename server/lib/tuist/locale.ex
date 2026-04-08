defmodule Tuist.Locale do
  @moduledoc false

  @supported_locales ~w(en es ja ko ru yue_Hant zh_Hans zh_Hant)

  def supported_locales, do: @supported_locales
end
