# frozen_string_literal: true

require "test_helper"

class TokenAuthenticatableTest < ActiveSupport::TestCase
  class AuthenticatableTestModel
    include ActiveModel::API
    extend ActiveModel::Callbacks

    define_model_callbacks :save
    attr_accessor :token, :name

    include TokenAuthenticatable

    autogenerates_token :token

    def save
      run_callbacks(:save) do
        # noop
      end
    end

    def id
      "123"
    end

    def self.exists?(*)
      false
    end
  end

  test "it generates the token when saving the model" do
    # Given
    subject = AuthenticatableTestModel.new(name: "name")

    # When
    subject.save

    # Then
    assert subject.token
  end

  test "encoded_token returns the encoded token value" do
    # Given
    subject = AuthenticatableTestModel.new(name: "name")

    # When
    subject.save

    # Then
    assert subject.encoded_token
  end
end
