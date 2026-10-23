# Backends que rodam a inferencia do P2PNet nas janelas do mosaico.
#
# Interface:
#   prepare(source_path:)          -> chamado uma vez, antes das janelas (source_path nil: so janelas de fotos)
#   prepare_photos(blobs)          -> garante as fotos originais acessiveis ao backend
#   photo_source(blob)             -> referencia da foto usada em Item#image
#   infer(items) { |item, outcome| } -> processa as janelas; chama o bloco a cada resultado
#   cleanup                        -> libera recursos temporarios
#
# MOSAIC_COUNT_BACKEND=local (padrao) roda no proprio servidor; cloud_run paraleliza em um Cloud Run Job.
module MosaicCounting
  # image: nil recorta a janela do mosaico; senao, da foto original indicada (ver photo_source).
  Item = Struct.new(:id, :window, :image, keyword_init: true)

  # status: :ok (points no sistema de coordenadas da imagem redimensionada) ou :oom (janela deve ser subdividida)
  Outcome = Struct.new(:status, :points, :resized_width, :resized_height, keyword_init: true) do
    def ok?
      status == :ok
    end

    def oom?
      status == :oom
    end
  end

  class BackendError < StandardError; end

  def self.build(work_dir:)
    Settings.cloud_run? ? CloudRun.new : Local.new(work_dir: work_dir)
  end
end
