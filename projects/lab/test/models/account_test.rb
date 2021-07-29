# frozen_string_literal: true
require "test_helper"

class AccountTest < ActiveSupport::TestCase
  test "validates that name is at least 5 characters" do
    # Given
    subject = Account.new(name: "test")

    # When
    subject.validate

    # Then
    assert_includes subject.errors.details[:name], { error: :too_short, count: 5 }
  end

  test "validates that name is at shorter than 30 characters" do
    # Given
    subject = Account.new(name: "testtesttesttesttesttesttesttesttesttesttest")

    # When
    subject.validate

    # Then
    assert_includes subject.errors.details[:name], { error: :too_long, count: 30 }
  end

  test "validates that the name is present" do
    # Given
    subject = Account.new

    # When
    subject.validate

    # Then
    assert_includes subject.errors.details[:name], { error: :blank }
  end

  test "validates that name is unique" do
    # Given
    first_owner = Organization.create!
    second_owner = Organization.create!
    Account.create!(owner: first_owner, name: "test-account")
    account = Account.new(owner: second_owner, name: "test-account")

    # When
    account.validate

    # Then
    assert_includes account.errors.details[:name], { error: :taken, value: "test-account" }
  end

  test "validates the uniqueness of the owner" do
    # Given
    owner = Organization.create!
    Account.create!(owner: owner, name: "test-account")
    account = Account.new(owner: owner, name: "test-account")

    # When
    account.validate

    # Then
    assert_includes account.errors.details[:owner_id], { error: :taken, value: owner.id }
  end

  test "validates the format of the name" do
    # Given
    subject = Account.new(name: "invalid.name! test")

    # When
    subject.validate

    # Then
    assert_includes subject.errors.details[:name], { error: :invalid, value: subject.name }
  end
end
