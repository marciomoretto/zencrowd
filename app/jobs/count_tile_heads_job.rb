class CountTileHeadsJob < ApplicationJob
  queue_as :processing

  def perform(tile_id)
    tile = Tile.find_by(id: tile_id)
    return unless tile

    TileHeadCounter.call(tile: tile, expose_error: false)
  rescue StandardError => e
    Rails.logger.error("Erro ao contar cabecas do tile ##{tile_id}: #{e.class} - #{e.message}")
  end
end
