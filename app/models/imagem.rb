class Imagem < ApplicationRecord
  self.table_name = 'imagens'

  has_one_attached :arquivo

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

  private

  def arquivo_deve_estar_presente
    errors.add(:arquivo, :blank) unless arquivo.attached?
  end
end
