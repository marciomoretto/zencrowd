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
    updates[:cidade] = imagem.cidade if evento.cidade.blank? && imagem.cidade.present?
    updates[:local] = imagem.local if evento.local.blank? && imagem.local.present?

    return if updates.empty?

    evento.update!(updates)
  rescue StandardError => e
    Rails.logger.warn("Nao foi possivel sincronizar evento ##{evento&.id} a partir da imagem ##{imagem.id}: #{e.class} - #{e.message}")
  end
end
