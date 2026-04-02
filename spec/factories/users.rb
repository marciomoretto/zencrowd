FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}-#{SecureRandom.hex(4)}@example.com" }
    sequence(:name) { |n| "User #{n}" }
    usp_login { nil }
    cpf { nil }
    phone { nil }
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

    trait :uploader do
      role { :uploader }
    end

    trait :finance do
      role { :finance }
    end
  end
end
