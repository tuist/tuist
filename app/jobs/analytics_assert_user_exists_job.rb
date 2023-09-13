# frozen_string_literal: true

class AnalyticsAssertUserExistsJob < Que::Job
  include Attioble

  def run(email, company_id: nil)
    return unless Environment.attio_configured?

    company = if company_id.present?
      [{
        'target_object': company_id["object_id"],
        'target_record_id': company_id["record_id"],
      }]
    else
      []
    end

    send_attio_request(
      "put",
      "/v2/objects/people/records?matching_attribute=email_addresses",
      json: { 'data': { 'values': { 'email_addresses': [{ 'email_address': email }], 'company': company } } },
    )
  end
end
