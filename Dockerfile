# syntax = docker/dockerfile:1

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version and Gemfile
ARG RUBY_VERSION=3.3.0
ARG RAILS_ENV=production
ARG APP_REVISION=unknown
ARG TUIST_VERSION=""
FROM registry.docker.com/library/ruby:$RUBY_VERSION-slim as base

# Rails app lives here
WORKDIR /rails

# Install packages needed to build gems and NPM packages
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl

# Set production environment
ENV RAILS_ENV=${RAILS_ENV} \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development"
ENV TUIST_VERSION=${TUIST_VERSION}

# Install JavaScript dependencies
ARG NODE_VERSION=18.18.0
ARG YARN_VERSION=1.22.17
ENV PATH=/usr/local/node/bin:$PATH
RUN curl -sL https://github.com/nodenv/node-build/archive/master.tar.gz | tar xz -C /tmp/ && \
    /tmp/node-build-master/bin/node-build "${NODE_VERSION}" /usr/local/node && \
    rm -rf /tmp/node-build-master

# Throw-away build stage to reduce size of final image
FROM base as build

ARG RAILS_ENV=production
ENV RAILS_ENV=${RAILS_ENV}
ARG APP_REVISION=unknown
ENV APP_REVISION=${APP_REVISION}
ARG TUIST_VERSION=""
ENV TUIST_VERSION=${TUIST_VERSION}

# Install packages needed to build gems and NPM packages
RUN apt-get install --no-install-recommends -y build-essential git libpq-dev libvips pkg-config

# Install application gems
COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times
RUN bundle exec bootsnap precompile app/ lib/

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
RUN SECRET_KEY_BASE_DUMMY=1 SECRET_KEY_BASE=1 ./bin/rails assets:precompile


# Final stage for app image
FROM base

# Set the description
LABEL org.opencontainers.image.title="Tuist Cloud"
LABEL org.opencontainers.image.vendor="Tuist GmbH"
LABEL org.opencontainers.image.source=https://github.com/tuist/cloud-on-premise

ARG RAILS_ENV=production
ENV RAILS_ENV=${RAILS_ENV}
ARG APP_REVISION=unknown
ENV APP_REVISION=${APP_REVISION}
ARG TUIST_VERSION=""
ENV TUIST_VERSION=${TUIST_VERSION}
ENV TRAEFIK_VERSION "3.0.0-rc1"

# Install packages needed for deployment
RUN apt-get install --no-install-recommends -y curl libvips postgresql-client supervisor && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install Traefik
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl && \
    curl -L "https://github.com/traefik/traefik/releases/download/v${TRAEFIK_VERSION}/traefik_v${TRAEFIK_VERSION}_linux_amd64.tar.gz" -o /tmp/traefik.tar.gz && \
    tar -xzf /tmp/traefik.tar.gz -C /usr/local/bin traefik && \
    rm /tmp/traefik.tar.gz && \
    chmod +x /usr/local/bin/traefik && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy Traefik configuration file
COPY traefik.yml traefik.yml
COPY .traefik/ .traefik/

# Supervisor configuration file
RUN mkdir -p /var/log/supervisor
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Copy built artifacts: gems, application
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /rails /rails

# Run and own only the runtime files as a non-root user for security
RUN useradd rails --create-home --shell /bin/bash && \
    chown -R rails:rails db log tmp
USER rails:rails

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start the server by default, this can be overwritten at runtime
EXPOSE 3000
CMD ["/usr/bin/supervisord"]
