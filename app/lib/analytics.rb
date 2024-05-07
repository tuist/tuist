# frozen_string_literal: true

module Analytics
  # Attio API: https://attio.com/developers/rest/

  class << self
    def on_user_authentication(email, company_id: nil)
      nil unless Environment.attio_configured?
    end

    def on_organization_creation(name, owner_email:)
      nil unless Environment.attio_configured?
    end
  end
end
