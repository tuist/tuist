# frozen_string_literal: true

require "test_helper"

class UserCreateServiceTest < ActiveSupport::TestCase
  def test_returns_the_user
    # Given
    email = "test@cloud.tuist.io"
    password = "123456"

    # When
    got = UserCreateService.call(email: email, password: password)

    # Then
    assert_equal(email, got.email)
    assert_equal(password, got.password)
    assert(got.account)
    assert_equal("test", got.account.name)
  end

  def test_returns_the_user_if_it_already_exists
    # Given
    email = "test@cloud.tuist.io"
    password = "123456"

    # When
    first_user = UserCreateService.call(email: email, password: password)
    second_user = UserCreateService.call(email: email, password: password)

    # Then
    assert_equal(second_user, first_user)
  end

  def test_changes_the_account_name_if_another_user_with_the_same_account_name_exists
    # When
    UserCreateService.call(email: "test@cloud.tuist.io", password: "123456")
    user = UserCreateService.call(email: "test@tuist.io", password: "123456")

    # Then
    assert_equal("test1", user.account.name)
  end

  def test_raises_an_error_if_it_cant_find_a_name_for_the_account
    # Given
    UserCreateService.call(email: "test@cloud.tuist.io", password: "123456")
    (1..5).each do |index|
      UserCreateService.call(email: "test#{index}@cloud.tuist.io", password: "123456")
    end

    # Then
    assert_raises(User::Error::CantObtainAccountName) do
      UserCreateService.call(email: "test@tuist.io", password: "123456")
    end
  end
end
