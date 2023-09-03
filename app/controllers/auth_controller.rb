# frozen_string_literal: true

class AuthController < ApplicationController
  skip_before_action :authenticate_user!

  def after_auth_path(session, user, root_path)
    if session["is_cli_authenticating"]
      '/auth/cli/success'
    elsif session["invitation_token"]
      InvitationAcceptService.call(token: session["invitation_token"], user: user)
      session["invitation_token"] = nil
      '/get-started'
    elsif user.legacy?
      root_path
    else
      '/get-started'
    end
  end

  def authenticate
    if current_user.nil?
      session["is_cli_authenticating"] = true
      authenticate_user!
    end

    session["is_cli_authenticating"] = false

    redirect_to("/auth/cli/success")
  end

  def accept_invitation
    if current_user.nil?
      session["invitation_token"] = params[:token]
      authenticate_user!
    end

    @invitation = InvitationFetchService.call(token: params[:token])
    InvitationAcceptService.call(token: params[:token], user: current_user)
    redirect_to('/get_started')
  end

  def cli_success
    session["is_cli_authenticating"] = false
    render "auth/cli/success"
  end
end
