class Evento < ApplicationRecord
  has_many :imagens, dependent: :nullify, inverse_of: :evento

  enum categoria: {
    direita: 0,
    esquerda: 1,
    outro: 2
  }, _prefix: :categoria

  validates :nome, presence: true
end
