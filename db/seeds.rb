# Clear existing data in development
if Rails.env.development?
  puts "Cleaning database..."
  Review.destroy_all
  AnnotationPoint.destroy_all
  Annotation.destroy_all
  Image.destroy_all
  User.destroy_all
  puts "Database cleaned!"
end

puts "Creating users..."

# Admin user
admin = User.find_or_create_by!(email: 'admin@example.com') do |u|
  u.name = 'Admin User'
  u.role = :admin
  u.password = 'password123'
  u.password_confirmation = 'password123'
end
puts "  - Admin created: #{admin.email} (password: password123)"

# Annotators
annotator1 = User.find_or_create_by!(email: 'annotator@example.com') do |u|
  u.name = 'João Silva'
  u.role = :annotator
  u.password = 'password123'
  u.password_confirmation = 'password123'
end
puts "  - Annotator 1 created: #{annotator1.email} (password: password123)"

annotator2 = User.find_or_create_by!(email: 'anotador2@zencrowd.com') do |u|
  u.name = 'Maria Santos'
  u.role = :annotator
  u.password = 'password123'
  u.password_confirmation = 'password123'
end
puts "  - Annotator 2 created: #{annotator2.email} (password: password123)"

annotator3 = User.find_or_create_by!(email: 'anotador3@zencrowd.com') do |u|
  u.name = 'Pedro Costa'
  u.role = :annotator
  u.password = 'password123'
  u.password_confirmation = 'password123'
end
puts "  - Annotator 3 created: #{annotator3.email} (password: password123)"

# Reviewers
reviewer1 = User.find_or_create_by!(email: 'reviewer@example.com') do |u|
  u.name = 'Ana Oliveira'
  u.role = :reviewer
  u.password = 'password123'
  u.password_confirmation = 'password123'
end
puts "  - Reviewer 1 created: #{reviewer1.email} (password: password123)"

reviewer2 = User.find_or_create_by!(email: 'revisor2@zencrowd.com') do |u|
  u.name = 'Carlos Ferreira'
  u.role = :reviewer
  u.password = 'password123'
  u.password_confirmation = 'password123'
end
puts "  - Reviewer 2 created: #{reviewer2.email} (password: password123)"

puts "\nCreating images..."

# Available images
5.times do |i|
  image = Image.create!(
    original_filename: "multidao_#{i + 1}.jpg",
    storage_path: "/uploads/images/multidao_#{i + 1}.jpg",
    status: :available,
    task_value: rand(5.0..20.0).round(2),
    uploader: admin
  )
  puts "  - Image #{i + 1} created (available): #{image.original_filename}"
end

# Reserved image
reserved_image = Image.create!(
  original_filename: "multidao_reservada.jpg",
  storage_path: "/uploads/images/multidao_reservada.jpg",
  status: :reserved,
  task_value: 10.0,
  uploader: admin,
  reserver: annotator1,
  reserved_at: 2.hours.ago
)
puts "  - Reserved image created: #{reserved_image.original_filename}"

# Submitted image with annotation
submitted_image = Image.create!(
  original_filename: "multidao_submetida.jpg",
  storage_path: "/uploads/images/multidao_submetida.jpg",
  status: :submitted,
  task_value: 12.0,
  uploader: admin,
  reserver: annotator2,
  reserved_at: 5.hours.ago
)
puts "  - Submitted image created: #{submitted_image.original_filename}"

# Create annotation for submitted image
annotation1 = Annotation.create!(
  image: submitted_image,
  user: annotator2,
  submitted_at: 1.hour.ago
)
puts "    - Annotation created for submitted image"

# Create some annotation points
10.times do
  AnnotationPoint.create!(
    annotation: annotation1,
    x: rand(100..1920),
    y: rand(100..1080)
  )
end
puts "    - 10 annotation points created"

# Image in review
review_image = Image.create!(
  original_filename: "multidao_revisao.jpg",
  storage_path: "/uploads/images/multidao_revisao.jpg",
  status: :in_review,
  task_value: 15.0,
  uploader: admin
)
puts "  - Review image created: #{review_image.original_filename}"

# Create annotation for review image
annotation2 = Annotation.create!(
  image: review_image,
  user: annotator3,
  submitted_at: 3.hours.ago
)
puts "    - Annotation created for review image"

# Create annotation points
15.times do
  AnnotationPoint.create!(
    annotation: annotation2,
    x: rand(100..1920),
    y: rand(100..1080)
  )
end
puts "    - 15 annotation points created"

# Approved image
approved_image = Image.create!(
  original_filename: "multidao_aprovada.jpg",
  storage_path: "/uploads/images/multidao_aprovada.jpg",
  status: :approved,
  task_value: 18.0,
  uploader: admin
)
puts "  - Approved image created: #{approved_image.original_filename}"

# Create annotation for approved image
annotation3 = Annotation.create!(
  image: approved_image,
  user: annotator1,
  submitted_at: 1.day.ago
)
puts "    - Annotation created for approved image"

# Create annotation points
20.times do
  AnnotationPoint.create!(
    annotation: annotation3,
    x: rand(100..1920),
    y: rand(100..1080)
  )
end
puts "    - 20 annotation points created"

# Create review (approved)
Review.create!(
  annotation: annotation3,
  reviewer: reviewer1,
  status: :approved,
  comment: 'Excelente trabalho! Todas as pessoas foram marcadas corretamente.',
  reviewed_at: 12.hours.ago
)
puts "    - Review created (approved)"

# Rejected image
rejected_image = Image.create!(
  original_filename: "multidao_rejeitada.jpg",
  storage_path: "/uploads/images/multidao_rejeitada.jpg",
  status: :rejected,
  task_value: 10.0,
  uploader: admin
)
puts "  - Rejected image created: #{rejected_image.original_filename}"

# Create annotation for rejected image
annotation4 = Annotation.create!(
  image: rejected_image,
  user: annotator2,
  submitted_at: 2.days.ago
)
puts "    - Annotation created for rejected image"

# Create annotation points
8.times do
  AnnotationPoint.create!(
    annotation: annotation4,
    x: rand(100..1920),
    y: rand(100..1080)
  )
end
puts "    - 8 annotation points created"

# Create review (rejected)
Review.create!(
  annotation: annotation4,
  reviewer: reviewer2,
  status: :rejected,
  comment: 'Várias pessoas não foram marcadas. Por favor, revise a imagem com mais atenção.',
  reviewed_at: 1.day.ago
)
puts "    - Review created (rejected)"

puts "\n" + "="*50
puts "Seed completed successfully!"
puts "="*50
puts "\nSummary:"
puts "  Users: #{User.count} (#{User.admin.count} admin, #{User.annotator.count} annotators, #{User.reviewer.count} reviewers)"
puts "  Images: #{Image.count}"
puts "    - Available: #{Image.available.count}"
puts "    - Reserved: #{Image.reserved.count}"
puts "    - Submitted: #{Image.submitted.count}"
puts "    - In Review: #{Image.in_review.count}"
puts "    - Approved: #{Image.approved.count}"
puts "    - Rejected: #{Image.rejected.count}"
puts "  Annotations: #{Annotation.count}"
puts "  Annotation Points: #{AnnotationPoint.count}"
puts "  Reviews: #{Review.count}"
puts "="*50
