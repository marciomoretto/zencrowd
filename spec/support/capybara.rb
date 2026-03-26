# Força Selenium a usar o chromedriver do sistema
# Selenium::WebDriver::Chrome::Service.driver_path = '/usr/bin/chromedriver'
# frozen_string_literal: true

require 'capybara/rspec'
require 'selenium/webdriver'


Capybara.register_driver :selenium_chrome_headless do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument('--headless')
  options.add_argument('--disable-gpu')
  options.add_argument('--no-sandbox')
  options.add_argument('--disable-dev-shm-usage')
  # Usa o binário do Chromium instalado no container
  options.binary = '/usr/bin/chromium' if File.exist?('/usr/bin/chromium')
  options.binary = '/usr/bin/chromium-browser' if File.exist?('/usr/bin/chromium-browser')
  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end

Capybara.javascript_driver = :selenium_chrome_headless
