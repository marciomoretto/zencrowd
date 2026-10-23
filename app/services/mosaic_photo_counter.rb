# Conta cabecas nas fotos originais, em resolucao nativa, e devolve os pontos no sistema de coordenadas do mosaico.
#
# Cada foto e dividida em janelas por MosaicTilePlanner (como o mosaico era); janelas sem nenhum pixel que a foto
# possua no mosaico nem vao para a inferencia. Cada ponto e levado ao mosaico pela matriz da foto e so vale se cair
# num pixel que pertence a ela (MosaicPhotoMapping), entao ninguem e contado duas vezes nas sobreposicoes.
class MosaicPhotoCounter
  MAX_SPLIT_DEPTH = 3

  class CounterError < StandardError; end

  Window = Struct.new(:photo, :plan, :tile, :root_id, keyword_init: true)

  def initialize(mapping:, backend:)
    @mapping = mapping
    @backend = backend
  end

  # Retorna nil quando alguma foto do mapa nao existe mais (o chamador volta a contar no mosaico).
  def call(progress_callback: nil)
    blobs_by_key = ActiveStorage::Blob.where(key: @mapping.photos.map(&:key)).index_by(&:key)
    return nil unless @mapping.photos.all? { |photo| blobs_by_key.key?(photo.key) }

    @backend.prepare_photos(@mapping.photos.map { |photo| blobs_by_key.fetch(photo.key) })
    @sources = @mapping.photos.to_h { |photo| [photo.index, @backend.photo_source(blobs_by_key.fetch(photo.key))] }

    count_windows(build_windows, progress_callback)
  end

  private

  def build_windows
    @mapping.photos.flat_map do |photo|
      plan = MosaicTilePlanner.plan(width: photo.width, height: photo.height)
      plan.tiles.filter_map do |tile|
        next unless @mapping.owns_any?(photo, tile.core)

        Window.new(photo: photo, plan: plan, tile: tile, root_id: "p#{photo.index}r#{tile.row_index}c#{tile.col_index}")
      end
    end
  end

  # Mesmo esquema de rodadas do MosaicTempGridCutter: janelas sem memoria sao subdivididas em 4.
  def count_windows(windows, progress_callback)
    total_count = windows.size
    remaining = windows.map(&:root_id).tally
    completed = 0
    points = []
    emit_progress(progress_callback, 0, total_count)

    pending = windows
    depth = 0
    until pending.empty?
      by_item = {}
      items = pending.each_with_index.map do |window, index|
        item = MosaicCounting::Item.new(
          id: "#{window.root_id}-d#{depth}-#{index}",
          window: window.tile.window,
          image: @sources.fetch(window.photo.index)
        )
        by_item[item.id] = window
        item
      end

      next_pending = []
      @backend.infer(items) do |item, outcome|
        window = by_item.fetch(item.id)

        if outcome.ok?
          points.concat(accepted_points(outcome, window))
          remaining[window.root_id] -= 1
          if remaining[window.root_id].zero?
            completed += 1
            emit_progress(progress_callback, completed, total_count)
          end
        else
          sub_tiles = depth < MAX_SPLIT_DEPTH ? MosaicTilePlanner.split(window.tile, window.plan) : nil
          raise CounterError, 'Memoria insuficiente para contar as fotos, mesmo apos subdividir os recortes.' unless sub_tiles

          remaining[window.root_id] += sub_tiles.size - 1
          next_pending.concat(sub_tiles.map { |tile| window.dup.tap { |sub| sub.tile = tile } })
        end
      end

      pending = next_pending
      depth += 1
    end

    points
  end

  # Pontos vem na imagem redimensionada pelo P2PNet; voltam para a foto, ficam so os do core e vao para o mosaico.
  def accepted_points(outcome, window)
    rect = window.tile.window
    scale_x = rect.width.to_f / outcome.resized_width
    scale_y = rect.height.to_f / outcome.resized_height
    photo = window.photo

    Array(outcome.points).filter_map do |point_x, point_y|
      photo_x = rect.x + (point_x * scale_x)
      photo_y = rect.y + (point_y * scale_y)
      next unless window.tile.core.contains?(photo_x, photo_y)

      mosaic_x, mosaic_y = photo.to_mosaic(photo_x, photo_y)
      [mosaic_x, mosaic_y] if @mapping.owner_at(mosaic_x, mosaic_y) == photo.index
    end
  end

  def emit_progress(callback, processed_count, total_count)
    callback&.call(processed_count: processed_count, total_count: total_count, message: 'Contando cabecas nas fotos originais...')
  end
end
