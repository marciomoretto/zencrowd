FactoryBot.define do
  factory :annotation_point do
    association :annotation
    sequence(:x) { |n| 100 + n }
    sequence(:y) { |n| 200 + n }
  end
end
