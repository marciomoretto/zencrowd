FactoryBot.define do
  factory :drone do
    sequence(:modelo) { |n| "drone_modelo_#{n}" }
    sequence(:lente) { |n| "lente_#{n}" }
    fov_diag_deg { 84.0 }
    aspect_ratio { '4:3' }
  end
end
