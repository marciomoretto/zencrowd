# Produção: cria apenas o admin principal.
if Rails.env.production?
  admin = User.find_or_create_by!(email: "admin@admin.br") do |user|
    user.name = "Admin"
    user.password = "senha123"
    user.password_confirmation = "senha123"
    user.role = :admin
  end

  puts "Production seed concluído: admin criado/atualizado (#{admin.email})"
elsif !Rails.env.development?
  puts "Skipping seeds in #{Rails.env}: no data configured for this environment"
else

# Admin para desenvolvimento rápido
User.find_or_create_by!(email: "admin@admin.com") do |user|
  user.name = "Admin"
  user.password = "password123"
  user.password_confirmation = "password123"
  user.role = :admin
end
# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Clear existing data in development
if Rails.env.development?
  puts "Cleaning database..."
  TilePointSet.destroy_all
  ImagemTile.destroy_all
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

# Uploader user
uploader = User.find_or_create_by!(email: 'uploader@example.com') do |u|
  u.name = 'Uploader User'
  u.role = :uploader
  u.password = 'password123'
  u.password_confirmation = 'password123'
end
puts "  - Uploader created: #{uploader.email} (password: password123)"

# Reviewer user
reviewer = User.find_or_create_by!(email: 'reviewer@example.com') do |u|
  u.name = 'Revisor Teste'
  u.role = :reviewer
  u.password = 'password123'
  u.password_confirmation = 'password123'
end
puts "  - Reviewer created: #{reviewer.email} (password: password123)"

# Annotators
annotator1 = User.find_or_create_by!(email: 'annotator1@example.com') do |u|
  u.name = 'João Silva'
  u.role = :annotator
  u.password = 'password123'
  u.password_confirmation = 'password123'
end
annotator2 = User.find_or_create_by!(email: 'annotator2@example.com') do |u|
  u.name = 'Maria Souza'
  u.role = :annotator
  u.password = 'password123'
  u.password_confirmation = 'password123'
end
puts "  - Annotator 1 created: #{annotator1.email} (password: password123)"
puts "  - Annotator 2 created: #{annotator2.email} (password: password123)"

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

puts "\nCreating drones..."

[
  { modelo: 'air3s', lente: 'wide', fov_diag_deg: 84.0, aspect_ratio: '4:3' },
  { modelo: 'mavic3pro', lente: 'wide', fov_diag_deg: 84.0, aspect_ratio: '4:3' },
  { modelo: 'mavic3pro', lente: 'medium tele', fov_diag_deg: 35.0, aspect_ratio: '4:3' }
].each do |attrs|
  drone = Drone.find_or_create_by!(modelo: attrs[:modelo], lente: attrs[:lente]) do |d|
    d.fov_diag_deg = attrs[:fov_diag_deg]
    d.aspect_ratio = attrs[:aspect_ratio]
  end

  puts "  - Drone created: #{drone.modelo} + #{drone.lente} (fov_diag_deg: #{drone.fov_diag_deg}, aspect_ratio: #{drone.aspect_ratio})"
end

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

# Available NEW tasks (sem anotacoes/pontos)
3.times do |i|
  tile = Image.create!(
    original_filename: "multidao_nova_#{i + 1}.jpg",
    storage_path: "/uploads/images/multidao_nova_#{i + 1}.jpg",
    status: :available,
    task_value: (8.0 + i * 1.5).round(2),
    uploader: admin,
    head_count: [20, 35, 50][i]
  )
  puts "  - New available task created: #{tile.original_filename}"
end

# Abandoned tasks with different marked-point counts
[
  { filename: 'multidao_abandonada_1.jpg', head_count: 30, points: 4, user: annotator1 },
  { filename: 'multidao_abandonada_2.jpg', head_count: 40, points: 11, user: annotator2 },
  { filename: 'multidao_abandonada_3.jpg', head_count: 25, points: 18, user: annotator3 }
].each_with_index do |item, index|
  abandoned_tile = Image.create!(
    original_filename: item[:filename],
    storage_path: "/uploads/images/#{item[:filename]}",
    status: :abandoned,
    task_value: (9.5 + index * 2.25).round(2),
    uploader: admin,
    head_count: item[:head_count],
    reserved_at: nil,
    reservation_expires_at: nil,
    reserver: nil
  )

  annotation = Annotation.create!(
    image: abandoned_tile,
    user: item[:user],
    submitted_at: (index + 2).hours.ago
  )

  item[:points].times do
    AnnotationPoint.create!(
      annotation: annotation,
      x: rand(100..1920),
      y: rand(100..1080)
    )
  end

  puts "  - Abandoned task created: #{abandoned_tile.original_filename} (#{item[:points]} pontos)"
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

# In review image with annotation
submitted_image = Image.create!(
  original_filename: "multidao_em_revisao_entrada.jpg",
  storage_path: "/uploads/images/multidao_submetida.jpg",
  status: :in_review,
  task_value: 12.0,
  uploader: admin,
  reserver: annotator2,
  reserved_at: 5.hours.ago
)
puts "  - In review image created: #{submitted_image.original_filename}"

# Create annotation for in review image
annotation1 = Annotation.create!(
  image: submitted_image,
  user: annotator2,
  submitted_at: 1.hour.ago
)
puts "    - Annotation created for in review image"

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

# Paid image
paid_image = Image.create!(
  original_filename: "multidao_paga.jpg",
  storage_path: "/uploads/images/multidao_paga.jpg",
  status: :paid,
  task_value: 22.0,
  uploader: admin
)
puts "  - Paid image created: #{paid_image.original_filename}"

# Create annotation for paid image
annotation_paid = Annotation.create!(
  image: paid_image,
  user: annotator1,
  submitted_at: 2.days.ago
)
puts "    - Annotation created for paid image"

# Create annotation points
18.times do
  AnnotationPoint.create!(
    annotation: annotation_paid,
    x: rand(100..1920),
    y: rand(100..1080)
  )
end
puts "    - 18 annotation points created"

# Create review (approved) for paid image
Review.create!(
  annotation: annotation_paid,
  reviewer: reviewer1,
  status: :approved,
  comment: 'Anotação aprovada e tarefa paga.',
  reviewed_at: 1.day.ago
)
puts "    - Review created (approved for paid image)"

puts "\nCreating bulk payment dashboard data..."

annotators_for_payments = [annotator1, annotator2, annotator3]
reviewers_for_payments = [reviewer1, reviewer2]

# Payment requested batch
12.times do |i|
  annotator = annotators_for_payments[i % annotators_for_payments.size]
  reviewer = reviewers_for_payments[i % reviewers_for_payments.size]

  tile = Image.create!(
    original_filename: "multidao_pagamento_solicitado_#{i + 1}.jpg",
    storage_path: "/uploads/images/multidao_pagamento_solicitado_#{i + 1}.jpg",
    status: :payment_requested,
    task_value: (10 + (i % 7) * 2.5).round(2),
    uploader: admin,
    reserver: annotator
  )

  annotation = Annotation.create!(
    image: tile,
    user: annotator,
    submitted_at: (i + 3).hours.ago
  )

  rand(8..18).times do
    AnnotationPoint.create!(
      annotation: annotation,
      x: rand(100..1920),
      y: rand(100..1080)
    )
  end

  Review.create!(
    annotation: annotation,
    reviewer: reviewer,
    status: :approved,
    comment: 'Solicitação de pagamento aguardando processamento.',
    reviewed_at: (i + 2).hours.ago
  )
end
puts "  - 12 tasks created with status payment_requested"

# Paid batch
15.times do |i|
  annotator = annotators_for_payments[i % annotators_for_payments.size]
  reviewer = reviewers_for_payments[i % reviewers_for_payments.size]

  tile = Image.create!(
    original_filename: "multidao_pagamento_concluido_#{i + 1}.jpg",
    storage_path: "/uploads/images/multidao_pagamento_concluido_#{i + 1}.jpg",
    status: :paid,
    task_value: (12 + (i % 6) * 3.0).round(2),
    uploader: admin,
    reserver: annotator
  )

  annotation = Annotation.create!(
    image: tile,
    user: annotator,
    submitted_at: (i + 1).days.ago
  )

  rand(10..22).times do
    AnnotationPoint.create!(
      annotation: annotation,
      x: rand(100..1920),
      y: rand(100..1080)
    )
  end

  Review.create!(
    annotation: annotation,
    reviewer: reviewer,
    status: :approved,
    comment: 'Pagamento processado com sucesso.',
    reviewed_at: i.hours.ago
  )
end
puts "  - 15 tasks created with status paid"

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
puts "    - Abandoned: #{Image.abandoned.count}"
puts "    - Reserved: #{Image.reserved.count}"
puts "    - In Review: #{Image.in_review.count}"
puts "    - Approved: #{Image.approved.count}"
puts "    - Payment Requested: #{Image.payment_requested.count}"
puts "    - Paid: #{Image.paid.count}"
puts "    - Rejected: #{Image.rejected.count}"
puts "  Annotations: #{Annotation.count}"
puts "  Annotation Points: #{AnnotationPoint.count}"
puts "  Reviews: #{Review.count}"
puts "="*50
end
