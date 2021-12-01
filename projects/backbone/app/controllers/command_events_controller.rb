# frozen_string_literal: true

class CommandEventsController < ApplicationController
  skip_before_action :verify_authenticity_token, if: :json_request?

  # POST /command_events
  # POST /command_events.json
  def create
    @command_event = CommandEvent.new(command_event_params)

    respond_to do |format|
      if @command_event.save
        format.html { redirect_to(@command_event, notice: "Command event was successfully created.") }
        format.json { render(:show, status: :created, location: @command_event) }
      else
        format.html { render(:new) }
        format.json { render(json: @command_event.errors, status: :unprocessable_entity) }
      end
    end
  end

  private
    # Only allow a list of trusted parameters through.
    def command_event_params
      params.require(:command_event).permit(
        :name,
        :subcommand,
        :duration,
        :client_id,
        :tuist_version,
        :swift_version,
        :macos_version,
        :machine_hardware_name,
        :is_ci,
        params: {} # Allow any key inside the params JSON
      )
    end

    def restrict_to_development
      head(:bad_request) unless Rails.env.development?
    end

    def json_request?
      request.format.json?
    end
end
