# frozen_string_literal: true

require "test_helper"

class DestroyOauth2UsersTest < ActiveSupport::TestCase
  test "user accepts an invitation" do
    # Given
    user = User.create!(email: "test@cloud.tuist.io", password: Devise.friendly_token.first(16))
    Oauth2Identity.create!(provider: "github", id_in_provider: "123", user: user)

    assert_difference 'User.count', -1 do
      DestroyOauth2Users.call(ids: ["123"], provider: :github)
    end
  end
end
