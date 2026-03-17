FactoryBot.define do
  factory :assignment do
    association :user
    association :image
    status { 1 }
    expires_at { 2.days.from_now }
  end
end
