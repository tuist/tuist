module Octokit

  # Default setup options for preview features
  module Preview

    PREVIEW_TYPES = {
      :applications_api       => 'application/vnd.github.doctor-strange-preview+json'.freeze,
      :branch_protection      => 'application/vnd.github.luke-cage-preview+json'.freeze,
      :commit_search          => 'application/vnd.github.cloak-preview+json'.freeze,
      :commit_pulls           => 'application/vnd.github.groot-preview+json'.freeze,
      :commit_branches        => 'application/vnd.github.groot-preview+json'.freeze,
      :migrations             => 'application/vnd.github.wyandotte-preview+json'.freeze,
      :licenses               => 'application/vnd.github.drax-preview+json'.freeze,
      :source_imports         => 'application/vnd.github.barred-rock-preview'.freeze,
      :reactions              => 'application/vnd.github.squirrel-girl-preview'.freeze,
      :transfer_repository    => 'application/vnd.github.nightshade-preview+json'.freeze,
      :issue_timelines        => 'application/vnd.github.mockingbird-preview+json'.freeze,
      :nested_teams           => 'application/vnd.github.hellcat-preview+json'.freeze,
      :pages                  => 'application/vnd.github.mister-fantastic-preview+json'.freeze,
      :projects               => 'application/vnd.github.inertia-preview+json'.freeze,
      :traffic                => 'application/vnd.github.spiderman-preview'.freeze,
      :topics                 => 'application/vnd.github.mercy-preview+json'.freeze,
      :community_profile      => 'application/vnd.github.black-panther-preview+json'.freeze,
      :strict_validation      => 'application/vnd.github.speedy-preview+json'.freeze,
      :template_repositories  => 'application/vnd.github.baptiste-preview+json'.freeze,
      :project_card_events    => 'application/vnd.github.starfox-preview+json'.freeze,
      :vulnerability_alerts   => 'application/vnd.github.dorian-preview+json'.freeze,
    }

    def ensure_api_media_type(type, options)
      if options[:accept].nil?
        options[:accept] = PREVIEW_TYPES[type]
        warn_preview(type)
      end
      options
    end

    def warn_preview(type)
      octokit_warn <<-EOS
WARNING: The preview version of the #{type.to_s.capitalize} API is not yet suitable for production use.
You can avoid this message by supplying an appropriate media type in the 'Accept' request
header.
EOS
    end
  end
end
