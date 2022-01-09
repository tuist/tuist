# frozen_string_literal: true

require "test_helper"

class APITokenStrategyTest < ActiveSupport::TestCase
  test "token's valid? method returns true when all the attributes are present" do
    # Given
    subject = APITokenStrategy::Token.new(
      "Project",
      "123",
      "token",
    )

    # Then
    assert subject.valid?
  end

  test "token's valid? method returns false when any of the attributes is missing" do
   # Given
   subject = APITokenStrategy::Token.new(
     "",
     "123",
     "token",
   )

   # Then
   assert_not subject.valid?
 end

  test "token's encoding/decoding" do
     # Given
     subject = APITokenStrategy::Token.new(
       "Project",
       "123",
       "token",
     )

     # Then
     encoded_token = subject.encode
     assert encoded_token
     decoded_token = APITokenStrategy::Token.decode(encoded_token)
     assert_equal subject.model_name, decoded_token.model_name
     assert_equal subject.id, decoded_token.id
     assert_equal subject.token, decoded_token.token
   end
end
