# frozen_string_literal: true

require "test_helper"

class RemoveMemberServiceTest < ActiveSupport::TestCase
  test "user not found error is thrown when user with a given username does not exist" do
    # Given
    organization = Organization.create!
    Account.create!(owner: organization, name: "some-org")
    remover = User.create!(email: "test1@cloud.tuist.io", password: Devise.friendly_token.first(16))
    remover.add_role(:admin, organization)

    # When / Then
    assert_raises(RemoveMemberService::Error::MemberNotFound) do
      RemoveMemberService.call(
        username: "non-existing-username",
        organization_name: "some-org",
        remover: remover,
      )
    end
  end
end
