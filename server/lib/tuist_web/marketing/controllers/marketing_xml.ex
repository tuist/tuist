defmodule TuistWeb.Marketing.MarketingXML do
  @moduledoc ~S"""
  This module handles generating XML content for the marketing website, such as RSS feeds and sitemaps.
  The XML templates are embedded from the marketing_xml directory.
  """
  use TuistWeb, :xml

  embed_templates "marketing_xml/*"
end
