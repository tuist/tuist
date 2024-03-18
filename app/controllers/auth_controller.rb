# frozen_string_literal: true

class AuthController < ApplicationController
  skip_before_action :authenticate_user!

  def after_auth_path(session, cookies, user, root_path, stored_location)
    if !cookies.signed[:device_code].nil? || session[:is_cli_authenticating]
      '/auth/cli/success'
    elsif session["invitation_token"]
      InvitationAcceptService.call(token: session["invitation_token"], user: user)
      session["invitation_token"] = nil
      '/get-started'
    elsif !stored_location.nil?
      stored_location
    else
      root_path
    end
  end

  def authenticate
    cookies.signed[:device_code] = params[:device_code]

    if current_user.nil?
      unless params[:device_code].nil?
        DeviceCode.create!(code: params[:device_code])
      end
      session["is_cli_authenticating"] = true
      authenticate_user!
    else
      unless params[:device_code].nil?
        @authenticated_with_device_code = true
        DeviceCode.create!(code: params[:device_code], authenticated: true, user_id: current_user.id)
      end
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

    unless cookies.signed[:device_code].nil?
      device_code = DeviceCode.find_by(code: cookies.signed[:device_code])
      unless device_code.nil?
        @authenticated_with_device_code = true
        device_code.update!(
          authenticated: true,
          user_id: current_user.id,
        )
      end
    end

    render("auth/cli/success")
  end
end
