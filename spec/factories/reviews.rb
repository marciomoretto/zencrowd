FactoryBot.define do
  factory :review do
    association :annotation
    association :reviewer, factory: :user, role: :reviewer
    status { :approved }
    comment { "Review comment" }
    reviewed_at { Time.current }

    trait :approved do
      status { :approved }
      comment { "Annotation approved" }
    end

    trait :rejected do
      status { :rejected }
      comment { "Annotation rejected" }
    end
  end
end
