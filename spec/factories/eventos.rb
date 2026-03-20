FactoryBot.define do
  factory :evento do
    sequence(:nome) { |n| "Evento #{n}" }
    categoria { nil }
    data { nil }
  end
end
