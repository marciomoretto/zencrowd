class MosaicTilePlanner
  MIN_CORE_SIDE = 256

  Rect = Struct.new(:x, :y, :width, :height) do
    def right
      x + width
    end

    def bottom
      y + height
    end

    def contains?(point_x, point_y)
      point_x >= x && point_x < right && point_y >= y && point_y < bottom
    end
  end

  # core: area em que os pontos sao contados; window: core + margem de sobreposicao (o que vai para a inferencia).
  Tile = Struct.new(:row_index, :col_index, :core, :window, keyword_init: true)
  Plan = Struct.new(:width, :height, :rows, :cols, :overlap, :tiles, keyword_init: true)

  class << self
    def plan(width:, height:, max_pixels: P2pnetInferenceSettings.tile_max_pixels, overlap: P2pnetInferenceSettings.tile_overlap_px)
      width = width.to_i
      height = height.to_i
      raise ArgumentError, 'Dimensoes do mosaico invalidas.' unless width.positive? && height.positive?

      window_side = Math.sqrt(max_pixels.to_f).floor
      core_side = [window_side - (2 * overlap), MIN_CORE_SIDE].max

      cols = (width.to_f / core_side).ceil
      rows = (height.to_f / core_side).ceil
      x_edges = build_edges(width, cols)
      y_edges = build_edges(height, rows)

      tiles = Array.new(rows) do |row|
        Array.new(cols) do |col|
          core = Rect.new(
            x_edges[col],
            y_edges[row],
            x_edges[col + 1] - x_edges[col],
            y_edges[row + 1] - y_edges[row]
          )

          Tile.new(row_index: row + 1, col_index: col + 1, core: core, window: window_for(core, width, height, overlap))
        end
      end.flatten

      Plan.new(width: width, height: height, rows: rows, cols: cols, overlap: overlap, tiles: tiles)
    end

    def plan_for_file(path)
      require 'vips'

      image = Vips::Image.new_from_file(path.to_s)
      plan(width: image.width, height: image.height)
    end

    # Divide um tile em 4 quando a inferencia nao cabe na memoria. Retorna nil se ja estiver no tamanho minimo.
    def split(tile, plan)
      core = tile.core
      return nil if core.width < 2 * MIN_CORE_SIDE || core.height < 2 * MIN_CORE_SIDE

      x_edges = build_edges(core.width, 2).map { |edge| core.x + edge }
      y_edges = build_edges(core.height, 2).map { |edge| core.y + edge }

      [0, 1].product([0, 1]).map do |row, col|
        sub_core = Rect.new(
          x_edges[col],
          y_edges[row],
          x_edges[col + 1] - x_edges[col],
          y_edges[row + 1] - y_edges[row]
        )

        Tile.new(
          row_index: tile.row_index,
          col_index: tile.col_index,
          core: sub_core,
          window: window_for(sub_core, plan.width, plan.height, plan.overlap)
        )
      end
    end

    private

    def window_for(core, width, height, overlap)
      left = [core.x - overlap, 0].max
      top = [core.y - overlap, 0].max
      right = [core.right + overlap, width].min
      bottom = [core.bottom + overlap, height].min

      Rect.new(left, top, right - left, bottom - top)
    end

    def build_edges(total, slices)
      edges = Array.new(slices + 1) { |index| ((index * total.to_f) / slices).round }
      edges[0] = 0
      edges[-1] = total
      edges
    end
  end
end
