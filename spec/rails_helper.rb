# This file is copied to spec/ when you run 'rails generate rspec:install'
require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
require 'cgi' # Workaround for Ruby 3.2.10 CGI bug
require_relative '../config/environment'
# Prevent database truncation if the environment is production
abort("The Rails environment is running in production mode!") if Rails.env.production?
require 'rspec/rails'
# Add additional requires below this line. Rails is not loaded until this point!

# Capybara for feature testing
require 'capybara/rspec'
require 'capybara/rails'

# Requires supporting ruby files with custom matchers and macros, etc, in
# spec/support/ and its subdirectories. Files matching `spec/**/*_spec.rb` are
# run as spec files by default. This means that files in spec/support that end
# in _spec.rb will both be required and run as specs, causing the specs to be
# run twice. It is recommended that you do not name files matching this glob to
# end with _spec.rb. You can configure this pattern with the --pattern
# option on the command line or in ~/.rspec, .rspec or `.rspec-local`.
#
# The following line is provided for convenience purposes. It has the downside
# of increasing the boot-up time by auto-requiring all files in the support
# directory. Alternatively, in the individual `*_spec.rb` files, manually
# require only the support files necessary.
#
Rails.root.glob('spec/support/**/*.rb').sort_by(&:to_s).each { |f| require f }

# Checks for pending migrations and applies them before tests are run.
# If you are not using ActiveRecord, you can remove these lines.
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
    # Garante que o locale esteja em pt-BR para todos os testes
    config.before(:suite) do
      I18n.locale = :'pt-BR'
    end

    # Forçar host 127.0.0.1 em todos os testes de request para evitar erro de Blocked hosts
    config.before(:each, type: :request) do
      host! "127.0.0.1"
    end

    # Remove this line if you're not using ActiveRecord or ActiveRecord fixtures
    config.fixture_paths = [
      Rails.root.join('spec/fixtures')
    ]

    # If you're not using ActiveRecord, or you'd prefer not to run each of your
    # examples within a transaction, remove the following line or assign false
    # instead of true.
    config.use_transactional_fixtures = true

    # You can uncomment this line to turn off ActiveRecord support entirely.
    # config.use_active_record = false

    # RSpec Rails can automatically mix in different behaviours to your tests
    # based on their file location, for example enabling you to call `get` and
    # `post` in specs under `spec/controllers`.
    #
    # You can disable this behaviour by removing the line below, and instead
    # explicitly tag your specs with their type, e.g.:
    #
    #     RSpec.describe UsersController, type: :controller do
    #       # ...
    #     end
    #
    # The different available types are documented in the features, such as in
    # https://rspec.info/features/6-0/rspec-rails
    config.infer_spec_type_from_file_location!

    # Filter lines from Rails gems in backtraces.
    config.filter_rails_from_backtrace!
    # arbitrary gems may also be filtered via:
    # config.filter_gems_from_backtrace("gem name")
end

# Forçar Capybara a usar 127.0.0.1 como host padrão
Capybara.server_host = '127.0.0.1'
# Evita apontar para um servidor externo (ex.: dev em :3000) durante specs.
# Isso mantém os testes de feature no app in-process do próprio Capybara.
Capybara.app_host = nil

# Garante que a proteção CSRF está desabilitada em todos os controllers nos testes
ActionController::Base.allow_forgery_protection = false

# Garante que a proteção CSRF está desabilitada nos testes
Rails.application.config.action_controller.allow_forgery_protection = false
