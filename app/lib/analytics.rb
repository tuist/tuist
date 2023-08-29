module Analytics
  # Attio API: https://attio.com/developers/rest/

  def self.assert_user_exists(email, company_id: nil)
    return unless Environment.attio_configured?
    company = if company_id.present?
      [{
        "target_object": company_id["object_id"],
        "target_record_id": company_id["record_id"]
      }]
    else
      []
    end

    self.attio_request("put", "/v2/objects/people/records?matching_attribute=email_addresses",
      json: { "data": { "values": { "email_addresses": [{"email_address": email}], "company": company } } }
    )
  end

  def self.assert_organization_exists(name, owner_email:)
    return unless Environment.attio_configured?
    domain = "#{name}.cloud.tuist.io"
    company = self.attio_request("put", "/v2/objects/companies/records?matching_attribute=domains", json: { "data": { "values": { "name": [ {"value": name} ], "domains": [{"domain": domain}] }} }).json()
    owner_id = self.assert_user_exists(owner_email, company_id: company["data"]["id"])
  end

  private

  def self.attio_request(method, path, **kwargs)
    url = URI.parse("https://api.attio.com").merge(path)
    http = HTTPX.with(headers: {"content-type" => "application/json", "authorization" => "Bearer #{Environment.attio_api_key}"})
    response = http.send(method, url, **kwargs)
    error = response.error
    throw error unless error.nil?
    response
  end
end
