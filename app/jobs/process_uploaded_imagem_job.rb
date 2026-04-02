class ProcessUploadedImagemJob < ApplicationJob
  queue_as :processing

  def perform(imagem_id, options = {})
    imagem = Imagem.includes(:evento).find_by(id: imagem_id)
    return unless imagem&.arquivo&.attached?

    protected_fields = Array(options['protected_fields'] || options[:protected_fields]).map(&:to_s)
    sync_evento = options['sync_evento'] || options[:sync_evento]

    metadata = ImagemMetadataExtractor.extract(imagem.arquivo)
    normalized = (metadata[:normalized] || {}).with_indifferent_access

    updates = {
      exif_metadata: metadata[:exif] || {},
      xmp_metadata: metadata[:xmp] || {}
    }

    %w[data_hora gps_location cidade local].each do |field|
      next if protected_fields.include?(field)
      next if normalized[field].blank?
      next if %w[cidade local].include?(field) && location_blank_or_default?(normalized[field], field)

      updates[field] = normalized[field]
    end

    imagem.update!(updates)

    sync_evento_with_imagem!(imagem, normalized) if sync_evento
  rescue StandardError => e
    Rails.logger.error("Erro ao processar metadados da imagem ##{imagem_id}: #{e.class} - #{e.message}")
  end

  private

  def sync_evento_with_imagem!(imagem, normalized)
    evento = imagem.evento
    return unless evento

    updates = {}

    metadata_date = normalized['data_hora']&.to_date
    updates[:data] = metadata_date if evento.data.blank? && metadata_date.present?
    if location_blank_or_default?(evento.cidade, 'cidade') && location_present_and_not_default?(imagem.cidade, 'cidade')
      updates[:cidade] = imagem.cidade
    end

    if location_blank_or_default?(evento.local, 'local') && location_present_and_not_default?(imagem.local, 'local')
      updates[:local] = imagem.local
    end

    return if updates.empty?

    evento.update!(updates)
  rescue StandardError => e
    Rails.logger.warn("Nao foi possivel sincronizar evento ##{evento&.id} a partir da imagem ##{imagem.id}: #{e.class} - #{e.message}")
  end

  def location_blank_or_default?(value, field)
    normalized_value = normalize_location(value)
    return true if normalized_value.blank?

    normalized_value == default_location_placeholder(field)
  end

  def location_present_and_not_default?(value, field)
    normalized_value = normalize_location(value)
    normalized_value.present? && normalized_value != default_location_placeholder(field)
  end

  def default_location_placeholder(field)
    case field.to_s
    when 'cidade'
      'nao informada'
    when 'local'
      'nao informado'
    end
  end

  def normalize_location(value)
    I18n.transliterate(value.to_s).strip.downcase
  end
end
