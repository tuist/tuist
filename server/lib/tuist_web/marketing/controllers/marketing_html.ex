defmodule TuistWeb.Marketing.MarketingHTML do
  use TuistWeb, :html
  use Noora

  import TuistWeb.Marketing.MarketingComponents
  import TuistWeb.Marketing.MarketingLogos
  import TuistWeb.Marketing.MarketingOrgLogos
  import TuistWeb.Marketing.TestimonialOrgLogos

  embed_templates "marketing_html/*"
end
