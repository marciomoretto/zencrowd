class EventoRelatorio < ApplicationRecord
  belongs_to :evento, inverse_of: :relatorio

  validates :evento_id, uniqueness: true
end
