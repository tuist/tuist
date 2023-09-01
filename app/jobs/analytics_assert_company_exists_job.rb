class AnalyticsAssertCompanyExistsJob < Que::Job
  include Attioble

  def run(name, owner_email: nil)
    return unless Environment.attio_configured?

    domain = "#{name}.cloud.tuist.io"
    company_id = send_attio_request("put", "/v2/objects/companies/records?matching_attribute=domains", json: { "data": { "values": { "name": [ {"value": name} ], "domains": [{"domain": domain}] }} }).json()["data"]["id"]
    company = if company_id.present?
      [{
        "target_object": company_id["object_id"],
        "target_record_id": company_id["record_id"]
      }]
    else
      []
    end

    send_attio_request("put", "/v2/objects/people/records?matching_attribute=email_addresses",
      json: { "data": { "values": { "email_addresses": [{"email_address": owner_email}], "company": company } } }
    )
  end
end
