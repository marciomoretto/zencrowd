class TilePointSet < ApplicationRecord
  class PayloadError < StandardError; end

  belongs_to :tile, class_name: 'Tile', inverse_of: :tile_point_set

  validates :tile_id, uniqueness: true
  validates :axis, presence: true
  validate :points_payload_is_valid

  def finalized?
    finalized_at.present?
  end

  def as_zen_plot_payload
    {
      axis: axis.presence || 'image',
      points: normalized_points_with_ids(points),
      finalized: finalized?,
      finalized_at: finalized_at
    }
  end

  def self.normalize_payload(payload)
    normalized_payload = payload.is_a?(ActionController::Parameters) ? payload.to_unsafe_h : payload

    axis_value = normalized_payload.is_a?(Hash) ? (normalized_payload[:axis] || normalized_payload['axis']) : nil
    points_value = normalized_payload.is_a?(Hash) ? (normalized_payload[:points] || normalized_payload['points']) : normalized_payload

    axis = axis_value.to_s.strip.presence || 'image'

    unless points_value.is_a?(Array)
      raise PayloadError, 'Formato de pontos inválido: expected points array'
    end

    points = points_value.each_with_index.map do |point, index|
      normalize_point(point, index)
    end

    {
      axis: axis,
      points: points
    }
  end

  def self.normalize_point(point, index)
    unless point.is_a?(Hash)
      raise PayloadError, "Ponto ##{index + 1} é inválido"
    end

    x = parse_coordinate(point[:x] || point['x'], index, :x)
    y = parse_coordinate(point[:y] || point['y'], index, :y)

    id = point[:id] || point['id']
    normalized_id = id.to_i.positive? ? id.to_i : index + 1

    {
      id: normalized_id,
      x: x,
      y: y
    }
  end

  def self.parse_coordinate(value, index, axis)
    numeric_value = Float(value)
    raise PayloadError, "Ponto ##{index + 1} tem coordenada #{axis} inválida" unless numeric_value.finite?

    rounded_value = numeric_value.round(2)
    if rounded_value.negative?
      raise PayloadError, "Ponto ##{index + 1} tem coordenada #{axis} negativa"
    end

    rounded_value
  rescue ArgumentError, TypeError
    raise PayloadError, "Ponto ##{index + 1} tem coordenada #{axis} inválida"
  end

  private

  def points_payload_is_valid
    normalized = self.class.normalize_payload(axis: axis, points: points)
    self.axis = normalized[:axis]
    self.points = normalized[:points]
  rescue PayloadError => e
    errors.add(:points, e.message)
  end

  def normalized_points_with_ids(raw_points)
    self.class.normalize_payload(axis: axis, points: raw_points)[:points]
  rescue PayloadError
    []
  end
end
