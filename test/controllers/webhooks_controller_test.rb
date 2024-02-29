# frozen_string_literal: true

require "test_helper"

class WebhooksControllerTest < ActionDispatch::IntegrationTest
  test "okta_verify when the challenge is missing" do
    # Given
    headers = {}

    # When
    get webhooks_okta_url, headers: headers

    # Then
    assert_response :bad_request
  end

  test "okta_verify when the challenge is present" do
    # Given
    headers = { "x-okta-verification-challenge" => "1234" }

    # When
    get webhooks_okta_url, headers: headers

    # Then
    assert_response :success
    assert_equal "1234", response.parsed_body["verification"]
  end

  test "okta when the authorization header is missing" do
    # Given
    headers = {}

    # When
    post webhooks_okta_url, headers: headers

    # Then
    assert_response :bad_request
  end

  test "okta when the authorization header is invalid" do
    # Given
    headers = { "authorization" => "invalid" }

    # When
    post webhooks_okta_url, headers: headers

    # Then
    assert_response :bad_request
  end

  test "okta when the authorization header is valid but the body is not a JSON" do
    # Given
    Environment.expects(:okta_event_hook_secret).returns("secret")
    headers = { "authorization" => "secret" }

    # When
    post webhooks_okta_url, headers: headers, params: "body"

    # Then
    assert_response :bad_request
  end

  test "okta deletes the user when the event type is application.user_membership.remove and it contains the tuist cloud application as target" do
    # Given
    Environment.expects(:okta_event_hook_secret).returns("secret")
    Environment.expects(:okta_client_id).returns("id")
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    oauth2_identity = Oauth2Identity.create!(provider: :okta, id_in_provider: "123", user: user)

    headers = { "authorization" => "secret", 'CONTENT_TYPE' => 'application/json' }
    payload = {
      "eventType" => "other",
      "data" => {
        "events" => [{
          "eventType" => "application.user_membership.remove",
          "target" => [
            {
              "type" => "AppInstance",
              "id" => "id",
            },
            {
              "type" => "User",
              "id" => oauth2_identity.id_in_provider,
            },
          ],
        }],
      },
    }

    # When
    assert_difference 'User.count', -1 do
      post webhooks_okta_url, headers: headers, params: payload.to_json
    end

    # Then
    assert_response :ok
  end

  test "okta doesn't delete the user when the event type is application.user_membership.remove and it doesn't contain the tuist cloud application as target" do
    # Given
    Environment.expects(:okta_event_hook_secret).returns("secret")
    Environment.expects(:okta_client_id).returns("id")
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    oauth2_identity = Oauth2Identity.create!(provider: :okta, id_in_provider: "123", user: user)

    headers = { "authorization" => "secret", 'CONTENT_TYPE' => 'application/json' }
    payload = {
      "eventType" => "other",
      "data" => {
        "events" => [{
          "eventType" => "application.user_membership.remove",
          "target" => [
            {
              "type" => "AppInstance",
              "id" => "another-id", # <- Event for another app
            },
            {
              "type" => "AppUser",
              "id" => oauth2_identity.id_in_provider,
            },
          ],
        }],
      },
    }

    # When
    assert_difference 'User.count', 0 do
      post webhooks_okta_url, headers: headers, params: payload.to_json
    end

    # Then
    assert_response :ok
  end
end
