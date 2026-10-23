# Envia a foto recem-processada ao bucket do Cloud Run e agenda o preparo antecipado do mosaico da pasta, para que
# SIFT e registro de pares ja estejam no cache quando o mosaico for gerado.
class MosaicPhotoSyncJob < ApplicationJob
  queue_as :processing

  # Falha de rede com o GCS: tenta de novo; se nao der, o render reenvia a foto que faltar.
  retry_on StandardError, wait: :polynomially_longer, attempts: 4

  def perform(imagem_id)
    return unless MosaicRendering::Settings.cloud_run?

    imagem = Imagem.find_by(id: imagem_id)
    return unless imagem&.arquivo&.attached?

    MosaicRendering::PhotoStore.new.ensure_uploaded!([imagem.arquivo.blob])

    PrepareMosaicCacheJob.schedule(evento_id: imagem.evento_id, pasta_param: imagem.pasta) if imagem.evento_id
  end
end
