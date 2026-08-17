user_agent = ENV.fetch('NOMINATIM_USER_AGENT', 'ZenCrowd geocoder/1.0')
contact_email = ENV['NOMINATIM_CONTACT_EMAIL']
geocoder_timeout = Float(ENV.fetch('GEOCODER_TIMEOUT_SECONDS', '8'))

Geocoder.configure(
  timeout: geocoder_timeout,
  lookup: :nominatim,
  language: 'pt-BR',
  units: :km,
  always_raise: [],
  http_headers: { 'User-Agent' => user_agent },
  params: contact_email.present? ? { email: contact_email } : {}
)
