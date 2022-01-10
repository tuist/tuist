# frozen_string_literal: true

class InvitationMailer < ApplicationMailer
  def invitation_mail(inviter:, invitee:, organization:, token:)
    @inviter = inviter
    @invitee = invitee
    @organization = organization
    @token = token

    mail(to: invitee, subject: "#{inviter.account.name} invited you to #{organization.name}")
  end
end
