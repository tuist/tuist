# frozen_string_literal: true

module Environment
  TRUTHY_VALUES = ["1", "true", "TRUE", "yes", "YES"]

  def self.use_env_variables?(env: ENV)
    truthy?(env["TUIST_CLOUD_ENV_VARIABLES"])
  end

  def self.truthy?(value)
    return false if value.blank?

    TRUTHY_VALUES.any? { |v| v == value.to_s }
  end
end
