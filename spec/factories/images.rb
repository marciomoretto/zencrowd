FactoryBot.define do
  factory :image do
    original_filename { "MyString" }
    storage_path { "MyString" }
    status { 1 }
    task_value { "9.99" }
    uploaded_by { nil }
    reserved_by { 1 }
    reserved_at { "2026-03-17 00:14:34" }
  end
end
