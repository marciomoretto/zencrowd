class P2pnetInferenceSettings
  DEFAULT_DEVICE = 'cpu'.freeze
  DEFAULT_THRESHOLD = 0.3
  DEFAULT_MAX_PIXELS = 18_000_000

  class << self
    def device
      ENV.fetch('P2PNET_DEVICE', DEFAULT_DEVICE).to_s.strip.presence || DEFAULT_DEVICE
    end

    def threshold
      clamp_float(
        ENV.fetch('P2PNET_THRESHOLD', DEFAULT_THRESHOLD).to_f,
        min: 0.05,
        max: 0.95,
        fallback: DEFAULT_THRESHOLD
      )
    end

    def max_pixels
      value = ENV.fetch('P2PNET_MAX_PIXELS', DEFAULT_MAX_PIXELS).to_i
      value.positive? ? value : DEFAULT_MAX_PIXELS
    end

    private

    def clamp_float(value, min:, max:, fallback:)
      return fallback unless value.finite?

      [[value, min].max, max].min
    rescue StandardError
      fallback
    end
  end
end