# frozen_string_literal: true

class Organization < ApplicationRecord
  resourcify

  # Associations
  has_one :account, as: :owner, class_name: "Account", dependent: :destroy
  has_many :users, through: :roles, class_name: 'User', source: :users

  def name
    account.name
  end
end
