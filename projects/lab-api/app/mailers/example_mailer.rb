# frozen_string_literal: true
class ExampleMailer < ApplicationMailer
  def example_email
    mail(to: "pedro@ppinera.es", subject: "Welcome to My Awesome Site")
  end
end
