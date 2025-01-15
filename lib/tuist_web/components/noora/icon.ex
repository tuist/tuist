defmodule TuistWeb.Noora.Icon do
  @moduledoc false
  use Phoenix.Component

  def arrow_left(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor">
      <path d="M15 6L9 12L15 18" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
    </svg>
    """
  end

  def arrow_right(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor">
      <path d="M9 6L15 12L9 18" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
    </svg>
    """
  end
end
