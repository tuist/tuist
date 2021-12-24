# frozen_string_literal: true

class InvitationMailer < ApplicationMailer
  attr_reader :inviter, :invitee, :organization, :token

  def initialize(inviter:, invitee:, organization:, token:)
    @inviter = inviter
    @invitee = invitee
    @organization = organization
    @token = token
  end

  def invitation_mail
    mail(to: invitee, subject: "#{inviter.account.name} invited you to #{organization.name}")
  end
end
