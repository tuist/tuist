# frozen_string_literal: true

require "test_helper"

class ApplicationControllerTest < ActionDispatch::IntegrationTest
  test "ready returns a successful response" do
    # Given
    get ready_url

    # Then
    assert_response :success
  end
end
