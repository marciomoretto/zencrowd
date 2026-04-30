# syntax = docker/dockerfile:1

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version and Gemfile
ARG RUBY_VERSION=3.2.10
FROM registry.docker.com/library/ruby:$RUBY_VERSION-slim as base

# Rails app lives here
WORKDIR /rails

# Set production environment
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development"


# Throw-away build stage to reduce size of final image
FROM base as build


# Install packages needed to build gems, Chrome, and ChromeDriver (no apt-key)
RUN set -e && \
        apt-get update -qq && \
        apt-get install --no-install-recommends -y \
            build-essential git libpq-dev libvips pkg-config libyaml-dev \
            wget gnupg2 gpg unzip curl ca-certificates chromium chromium-driver

# Install application gems
COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times
RUN bundle exec bootsnap precompile app/ lib/

# Precompile assets in build stage with safe DB env defaults.
RUN SECRET_KEY_BASE_DUMMY=1 DATABASE_HOST=db DATABASE_USER=postgres DATABASE_PASSWORD=postgres ./bin/rails assets:precompile


# Final stage for app image
FROM base

# Install packages needed for deployment and runtime gem compilation in dev containers.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
            build-essential \
      curl \
      git \
    imagemagick \
      libvips \
      postgresql-client \
      python3 \
      python3-pip \
      python3-venv && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Copy built artifacts: gems, application
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /rails /rails

# Create isolated Python runtime for P2PNet inference.
RUN python3 -m venv /opt/p2pnet-venv && \
        /opt/p2pnet-venv/bin/pip install --no-cache-dir --upgrade pip && \
        for attempt in 1 2 3; do \
            /opt/p2pnet-venv/bin/pip install --no-cache-dir --retries 5 --timeout 120 \
                --index-url https://download.pytorch.org/whl/cpu \
                --extra-index-url https://pypi.org/simple \
                torch torchvision && break; \
            echo "torch install failed (attempt ${attempt}/3), retrying..."; \
            if [ "$attempt" -eq 3 ]; then exit 1; fi; \
        done && \
        /opt/p2pnet-venv/bin/pip install --no-cache-dir --retries 5 --timeout 120 -r /rails/requirements-p2pnet.txt

ENV P2PNET_PYTHON_BIN="/opt/p2pnet-venv/bin/python"

# Run and own only the runtime files as a non-root user for security
RUN useradd rails --create-home --shell /bin/bash && \
    chown -R rails:rails db log storage tmp
USER rails:rails

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start the server by default, this can be overwritten at runtime
EXPOSE 3000
CMD ["./bin/rails", "server"]
