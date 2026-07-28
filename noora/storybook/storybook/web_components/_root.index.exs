defmodule TuistWeb.Storybook.WebComponents do
  @moduledoc false
  use PhoenixStorybook.Index

  def folder_icon, do: {:fa, "cube", :light, "psb-mr-1"}
  def folder_name, do: "Web components"
end
