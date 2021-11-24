# frozen_string_literal: true

require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "name's exclusion is validated" do
    # Given
    subject = Account.new(name: Defaults.fetch(:blocklisted_slug_keywords).first)

    # When
    subject.validate

    # Then
    assert_includes subject.errors.details[:name], { error: :exclusion, value: "new" }
  end
end
