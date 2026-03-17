FactoryBot.define do
  factory :review do
    annotation { nil }
    reviewer { nil }
    status { 1 }
    comment { "MyText" }
    reviewed_at { "2026-03-17 00:16:17" }
  end
end
