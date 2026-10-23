class P2pnetInferenceSettings
  DEFAULT_DEVICE = 'cpu'.freeze
  DEFAULT_THRESHOLD = 0.3
  DEFAULT_MAX_PIXELS = 18_000_000
  DEFAULT_TILE_MAX_PIXELS = 1_500_000
  DEFAULT_TILE_OVERLAP_PX = 128

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

    # Orcamento de pixels por janela de inferencia ao contar o mosaico (nao reduz a resolucao, so define o recorte).
    def tile_max_pixels
      value = ENV.fetch('P2PNET_TILE_MAX_PIXELS', DEFAULT_TILE_MAX_PIXELS).to_i
      value.positive? ? value : DEFAULT_TILE_MAX_PIXELS
    end

    # Margem (px) de cada lado dos recortes; evita perder ou duplicar pessoas na divisa entre tiles.
    def tile_overlap_px
      value = ENV.fetch('P2PNET_TILE_OVERLAP_PX', DEFAULT_TILE_OVERLAP_PX).to_i
      value.negative? ? DEFAULT_TILE_OVERLAP_PX : value
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