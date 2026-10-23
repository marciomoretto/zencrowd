class P2pnetInferenceSettings
  DEFAULT_DEVICE = 'cpu'.freeze
  DEFAULT_THRESHOLD = 0.3
  DEFAULT_MAX_PIXELS = 18_000_000
  DEFAULT_TILE_MAX_PIXELS = 1_500_000
  DEFAULT_TILE_OVERLAP_PX = 128
  DEFAULT_MIN_TEXTURE = 12.0
  DEFAULT_MAX_GREEN_FRACTION = 0.6

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

    # Filtros aplicados pelo worker de contagem a cada deteccao (ver filter_points em cloud_run/count_worker/worker.py):
    # descarta pontos em superficie lisa (desvio-padrao do cinza 13x13 abaixo de min_texture: mar, areia) ou com a
    # vizinhanca 25x25 quase toda verde (acima de max_green_fraction: copas de arvore). 0 desliga o filtro.
    def min_texture
      non_negative_float('P2PNET_MIN_TEXTURE', DEFAULT_MIN_TEXTURE)
    end

    def max_green_fraction
      non_negative_float('P2PNET_MAX_GREEN_FRACTION', DEFAULT_MAX_GREEN_FRACTION)
    end

    private

    def non_negative_float(name, default)
      value = Float(ENV.fetch(name, default))
      value.finite? && value >= 0 ? value : default
    rescue ArgumentError, TypeError
      default
    end

    def clamp_float(value, min:, max:, fallback:)
      return fallback unless value.finite?

      [[value, min].max, max].min
    rescue StandardError
      fallback
    end
  end
end