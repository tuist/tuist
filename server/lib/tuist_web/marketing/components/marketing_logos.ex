defmodule TuistWeb.Marketing.MarketingLogos do
  @moduledoc ~S"""
  A collection of company logos to include in the marketing pages.
  """
  use TuistWeb, :live_component

  embed_templates "marketing_logos/*"
end
