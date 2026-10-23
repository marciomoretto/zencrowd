module MosaicRendering
  # Fotos de uma pasta que entram no mosaico: as zenitais ou, se nenhuma for zenital, todas. Usada pelo render e
  # pelo preparo antecipado (PrepareMosaicCacheJob), que precisam olhar exatamente o mesmo conjunto.
  class PhotoSelection
    attr_reader :imagens, :source_total_count, :source_zenital_count, :selection_mode

    def self.for(evento:, pasta_param:)
      new(evento: evento, pasta_param: pasta_param)
    end

    def initialize(evento:, pasta_param:)
      todas = scope_for(evento, pasta_param.to_s.strip).to_a
      tolerance = AppSetting.zenith_tolerance_degrees
      zenitais = todas.select { |imagem| imagem.zenital?(tolerance_degrees: tolerance) }

      @imagens = zenitais.any? ? zenitais : todas
      @selection_mode = zenitais.any? ? 'zenital_only' : 'fallback_all'
      @source_total_count = todas.size
      @source_zenital_count = zenitais.size
    end

    def selected_count
      imagens.size
    end

    # Blobs de imagem anexados, na ordem das imagens selecionadas.
    def blobs
      imagens.filter_map do |imagem|
        next unless imagem.arquivo.attached?

        blob = imagem.arquivo.blob
        blob if blob.content_type.to_s.start_with?('image/')
      end
    end

    private

    def scope_for(evento, pasta_param)
      if pasta_param.present?
        evento.imagens.where(pasta: pasta_param)
      else
        evento.imagens.where(pasta: [nil, ''])
      end
    end
  end
end
