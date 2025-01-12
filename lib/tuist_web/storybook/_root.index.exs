defmodule TuistWeb.Storybook.Root do
  use PhoenixStorybook.Index

  def folder_icon, do: {:fa, "book-open", :light, "psb-mr-1"}
  def folder_name, do: "Noora"
end
