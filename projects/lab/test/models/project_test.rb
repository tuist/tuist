# frozen_string_literal: true
require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  test "validates that name is at least 5 characters" do
    # Given
    subject = Project.new(name: "test")

    # When
    subject.validate

    # Then
    assert_includes subject.errors.details[:name], { error: :too_short, count: 5 }
  end

  test "validates that name is at shorter than 30 characters" do
    # Given
    subject = Project.new(name: "testtesttesttesttesttesttesttesttesttesttest")

    # When
    subject.validate

    # Then
    assert_includes subject.errors.details[:name], { error: :too_long, count: 30 }
  end

  test "validates that repository_full_name has the right format" do
    # Given
    invalid = Project.new(repository_full_name: "test")
    valid = Project.new(repository_full_name: "tuist/lab")

    invalid.validate
    valid.validate

    assert_includes(
      invalid.errors.details[:repository_full_name],
      { error: :invalid, value: "test" }
    )
    assert_empty valid.errors.details[:repository_full_name]
  end

  test "api_token gets generated on save if it doesn't exist" do
    # Given
    user = User.create!(email: "test@tuist.io", password: Devise.friendly_token)
    account = Account.create!(owner: user, name: "test-account")

    # When
    project = Project.create!(
      name: "test-project",
      repository_full_name: "tuist/lab",
      account: account
    )

    # Then
    assert_not project.api_token.blank?
  end
end
