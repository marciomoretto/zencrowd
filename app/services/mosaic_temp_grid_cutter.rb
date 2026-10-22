require 'fileutils'
require 'securerandom'

# Conta cabecas no mosaico em resolucao maxima. O grid de recortes e calculado por MosaicTilePlanner; cada recorte
# e inferido (localmente ou no Cloud Run, ver MosaicCounting) com margem de sobreposicao e so os pontos dentro do
# seu "core" sao contados.
class MosaicTempGridCutter
  Result = Struct.new(:success?, :error, :files_count, :total_heads, :piece_counts, :points, :rows, :cols, keyword_init: true)

  MAX_SPLIT_DEPTH = 3
  BLANK_PIXEL_MAX = 8

  class CutterError < StandardError; end

  def initialize(source_path:, evento_id:, pasta_nome:)
    @source_path = source_path.to_s
    @evento_id = evento_id
    @pasta_nome = pasta_nome.to_s
  end

  def call(progress_callback: nil)
    return failure('Arquivo de mosaico nao encontrado.') unless File.exist?(@source_path)

    ensure_vips_available!

    @source_image = Vips::Image.new_from_file(@source_path)
    plan = MosaicTilePlanner.plan(width: @source_image.width, height: @source_image.height)

    @work_dir = build_work_dir
    FileUtils.mkdir_p(@work_dir)

    backend = MosaicCounting.build(work_dir: @work_dir)
    backend.prepare(source_path: @source_path)

    points_by_tile = count_tiles(plan, backend, progress_callback)

    piece_counts = plan.tiles.map do |tile|
      {
        row_index: tile.row_index,
        col_index: tile.col_index,
        estimated_heads: points_by_tile[[tile.row_index, tile.col_index]].size
      }
    end
    all_points = points_by_tile.values.flatten(1)

    Result.new(
      success?: true,
      files_count: plan.tiles.size,
      total_heads: all_points.size,
      piece_counts: piece_counts,
      points: all_points,
      rows: plan.rows,
      cols: plan.cols
    )
  rescue StandardError => e
    Rails.logger.error("Falha ao contar mosaico: #{e.class} - #{e.message}")
    failure(error_message_for(e))
  ensure
    backend&.cleanup
    FileUtils.rm_rf(@work_dir) if @work_dir
  end

  private

  def ensure_vips_available!
    require 'vips'
  rescue LoadError
    raise CutterError, "Dependencia 'vips' nao encontrada. Rode com 'bundle exec' e instale as dependencias (gem ruby-vips e libvips)."
  end

  # Processa as janelas em rodadas: janelas sem memoria suficiente sao subdivididas em 4 e voltam na rodada seguinte.
  # Retorna { [row, col] => [[x, y], ...] } com os pontos (no mosaico) dentro do core de cada tile.
  def count_tiles(plan, backend, progress_callback)
    total_count = plan.tiles.size
    points_by_tile = Hash.new { |hash, key| hash[key] = [] }
    remaining = Hash.new(0)
    completed = 0

    emit_progress(progress_callback, processed_count: 0, total_count: total_count)

    pending = []
    plan.tiles.each do |tile|
      key = tile_key(tile)
      points_by_tile[key] # garante a chave, mesmo sem pontos

      if blank_area?(tile.core)
        completed += 1
      else
        remaining[key] += 1
        pending << tile
      end
    end
    emit_progress(progress_callback, processed_count: completed, total_count: total_count) if completed.positive?

    depth = 0
    until pending.empty?
      tiles_by_item = {}
      items = pending.each_with_index.map do |tile, index|
        item = MosaicCounting::Item.new(id: "r#{tile.row_index}c#{tile.col_index}-d#{depth}-#{index}", window: tile.window)
        tiles_by_item[item.id] = tile
        item
      end

      next_pending = []
      backend.infer(items) do |item, outcome|
        tile = tiles_by_item.fetch(item.id)
        key = tile_key(tile)

        if outcome.ok?
          points_by_tile[key].concat(points_in_core(outcome, tile))
          remaining[key] -= 1

          if remaining[key].zero?
            completed += 1
            emit_progress(progress_callback, processed_count: completed, total_count: total_count)
          end
        else
          sub_tiles = depth < MAX_SPLIT_DEPTH ? MosaicTilePlanner.split(tile, plan) : nil
          raise CutterError, 'Memoria insuficiente para contar o mosaico, mesmo apos subdividir os recortes.' unless sub_tiles

          remaining[key] += sub_tiles.size - 1
          next_pending.concat(sub_tiles)
        end
      end

      pending = next_pending
      depth += 1
    end

    points_by_tile
  end

  def tile_key(tile)
    [tile.row_index, tile.col_index]
  end

  # Areas sem dados (bordas pretas do canvas rotacionado) nao precisam de inferencia.
  def blank_area?(rect)
    @source_image.crop(rect.x, rect.y, rect.width, rect.height).bandmean.max < BLANK_PIXEL_MAX
  end

  # Os pontos vem nas coordenadas da imagem redimensionada (multiplos de 128) usada pelo P2PNet.
  def points_in_core(outcome, tile)
    window = tile.window
    scale_x = window.width.to_f / outcome.resized_width
    scale_y = window.height.to_f / outcome.resized_height

    Array(outcome.points).filter_map do |point_x, point_y|
      global_x = window.x + (point_x * scale_x)
      global_y = window.y + (point_y * scale_y)
      [global_x, global_y] if tile.core.contains?(global_x, global_y)
    end
  end

  def build_work_dir
    Rails.root.join(
      'tmp',
      'mosaic_cuts',
      "evento_#{@evento_id}",
      safe_file_fragment(@pasta_nome),
      "#{Time.current.strftime('%Y%m%d_%H%M%S')}_#{SecureRandom.hex(3)}"
    ).to_s
  end

  def safe_file_fragment(value)
    text = value.to_s.strip
    text = 'sem_pasta' if text.empty?
    text.gsub(/[^a-zA-Z0-9._-]/, '_')
  end

  def error_message_for(error)
    return error.message if error.is_a?(CutterError) || error.is_a?(MosaicCounting::BackendError)

    'Nao foi possivel contar o mosaico. Tente novamente.'
  end

  def failure(message)
    Result.new(success?: false, error: message, files_count: 0, total_heads: 0, piece_counts: [], points: [], rows: 0, cols: 0)
  end

  def emit_progress(progress_callback, processed_count:, total_count:)
    return unless progress_callback

    progress_callback.call(
      processed_count: processed_count,
      total_count: total_count,
      message: 'Contando recortes do mosaico...'
    )
  end
end
