defmodule TuistWeb.Storybook.Welcome do
  @moduledoc false
  use PhoenixStorybook.Story, :page

  def render(assigns) do
    ~H"""
    <div>
      Welcome to Noora's Storybook. Noora is a library of components built on web standards.
    </div>
    """
  end
end
