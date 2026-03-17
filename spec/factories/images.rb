FactoryBot.define do
  factory :image do
    sequence(:original_filename) { |n| "image_#{n}.jpg" }
    sequence(:storage_path) { |n| "/storage/images/image_#{n}.jpg" }
    status { :available }
    task_value { 10.0 }
    association :uploader, factory: :user, role: :admin
    reserver { nil }
    reserved_at { nil }

    trait :reserved do
      status { :reserved }
      association :reserver, factory: :user, role: :annotator
      reserved_at { Time.current }
    end

    trait :submitted do
      status { :submitted }
    end

    trait :in_review do
      status { :in_review }
    end

    trait :approved do
      status { :approved }
    end

    trait :rejected do
      status { :rejected }
    end

    trait :paid do
      status { :paid }
    end
  end
end
