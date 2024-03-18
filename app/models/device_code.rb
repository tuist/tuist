# frozen_string_literal: true

class DeviceCode < ApplicationRecord
  belongs_to :user, optional: true
end
