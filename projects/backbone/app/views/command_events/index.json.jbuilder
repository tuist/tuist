# frozen_string_literal: true

json.array!(@command_events, partial: "command_events/command_event", as: :command_event)
