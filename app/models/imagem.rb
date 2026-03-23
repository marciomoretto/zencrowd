class Imagem < ApplicationRecord
  self.table_name = 'imagens'

  has_one_attached :arquivo
  belongs_to :evento, optional: true

  has_many :imagem_tiles, dependent: :destroy, inverse_of: :imagem
  has_many :tiles, through: :imagem_tiles, source: :tile

  enum posicao: {
    esquerda: 0,
    direita: 1,
    outro: 2
  }, _prefix: :posicao

  validates :data_hora, presence: true
  validates :gps_location, presence: true
  validates :cidade, presence: true
  validates :local, presence: true
  validate :arquivo_deve_estar_presente

  def gimbal_pitch_degree
    flattened = flatten_metadata_for_pitch(
      'exif' => exif_metadata || {},
      'xmp' => xmp_metadata || {}
    )

    find_first_pitch_value(flattened)
  end

  def zenital?(tolerance_degrees: AppSetting.zenith_tolerance_degrees)
    pitch = gimbal_pitch_degree
    return nil if pitch.nil?

    tolerance = tolerance_degrees.to_f.abs
    (pitch.abs - 90.0).abs <= tolerance
  end

  private

  def flatten_metadata_for_pitch(value, prefix = nil, result = {})
    case value
    when Hash
      value.each do |key, inner_value|
        new_prefix = prefix ? "#{prefix}.#{key}" : key.to_s
        flatten_metadata_for_pitch(inner_value, new_prefix, result)
      end
    when Array
      value.each_with_index do |inner_value, index|
        new_prefix = "#{prefix}[#{index}]"
        flatten_metadata_for_pitch(inner_value, new_prefix, result)
      end
    else
      result[prefix] = value unless prefix.nil?
    end

    result
  end

  def find_first_pitch_value(flattened)
    key_fragments = %w[
      gimbalpitchdegree
      gimbalpitch
      flightpitchdegree
      pitchdegree
      camera.pitch
      gimbal.pitch
    ]

    normalized_fragments = key_fragments.map { |fragment| normalize_pitch_key(fragment) }

    normalized_fragments.each do |fragment|
      flattened.each do |key, raw_value|
        normalized_key = normalize_pitch_key(key)
        next unless normalized_key.include?(fragment)

        parsed = parse_pitch_numeric(raw_value)
        return parsed unless parsed.nil?
      end
    end

    nil
  end

  def normalize_pitch_key(value)
    value.to_s.downcase.gsub(/[^a-z0-9]/, '')
  end

  def parse_pitch_numeric(value)
    return value.to_f if value.is_a?(Numeric)
    return nil if value.nil?

    text = value.to_s.tr(',', '.').strip
    return nil if text.empty?

    match = text.match(/-?\d+(?:\.\d+)?/)
    return nil unless match

    Float(match[0])
  rescue ArgumentError, TypeError
    nil
  end

  def arquivo_deve_estar_presente
    errors.add(:arquivo, :blank) unless arquivo.attached?
  end
end
