FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    sequence(:name) { |n| "User #{n}" }
    password { "password123" }
    password_confirmation { "password123" }
    role { :annotator }
    blocked { false }

    trait :admin do
      role { :admin }
    end

    trait :annotator do
      role { :annotator }
    end

    trait :reviewer do
      role { :reviewer }
    end
  end
end
