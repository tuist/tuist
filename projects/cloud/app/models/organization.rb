# frozen_string_literal: true

class Organization < ApplicationRecord
  resourcify

  # Associations
  has_one :account, as: :owner, class_name: "Account", dependent: :destroy
end
