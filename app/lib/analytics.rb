module Analytics
  # Attio API: https://attio.com/developers/rest/

  def self.on_user_authentication(email, company_id: nil)
    return unless Environment.attio_configured?
    AnalyticsAssertUserExistsJob.enqueue(email, company_id: company_id)
  end

  def self.on_organization_creation(name, owner_email:)
    return unless Environment.attio_configured?
    AnalyticsAssertCompanyExistsJob.enqueue(name, owner_email: owner_email)
  end
end
