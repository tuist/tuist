# frozen_string_literal: true

class DecipherService < ApplicationService
  attr_reader :key, :iv

  def initialize(key:, iv:)
    super()
    @key = key
    @iv = iv
  end

  def call
    decipher = OpenSSL::Cipher::AES.new(256, :CBC)
    decipher.decrypt
    decipher.key = Digest::MD5.hexdigest(Rails.application.credentials[:secret_key_base])
    decipher.iv = iv
    decipher.update(key) + decipher.final
  end
end
