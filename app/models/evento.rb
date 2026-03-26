class Evento < ApplicationRecord
  has_many :imagens, dependent: :nullify, inverse_of: :evento
  has_many :pasta_head_estimates,
           class_name: 'EventoPastaHeadEstimate',
           dependent: :destroy,
           inverse_of: :evento
  has_many :mosaic_piece_head_counts,
           class_name: 'EventoMosaicPieceHeadCount',
           dependent: :destroy,
           inverse_of: :evento
  belongs_to :drone, optional: true

  enum categoria: {
    direita: 0,
    esquerda: 1,
    outro: 2
  }, _prefix: :categoria

  validates :nome, presence: true
end
