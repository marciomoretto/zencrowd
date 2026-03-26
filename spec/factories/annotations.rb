FactoryBot.define do
  factory :annotation do
    association :image
    association :user, factory: :user, role: :annotator
    submitted_at { Time.current }
  end
end
