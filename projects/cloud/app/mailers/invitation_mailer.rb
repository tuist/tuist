# frozen_string_literal: true

class InvitationMailer < ApplicationMailer
  def invitation_mail(inviter:, invitee_email:, organization:, token:)
    @inviter = inviter
    @invitee_email = invitee_email
    @organization = organization
    @token = token

    mail(to: invitee_email, subject: "#{inviter.account.name} invited you to #{organization.name}")
  end
end
