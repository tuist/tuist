defmodule TuistWeb.Marketing.MarketingHTML do
  use TuistWeb, :html
  import TuistWeb.Marketing.MarketingLayoutComponents
  import TuistWeb.Marketing.MarketingLogos

  embed_templates "marketing_html/*"
end
