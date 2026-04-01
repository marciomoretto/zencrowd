# Seeds por ambiente.
# Objetivo em desenvolvimento: manter apenas um usuario, sempre admin.

if Rails.env.production?
  admin = User.find_or_initialize_by(email: "admin@admin.br")
  admin.name = "Admin"
  admin.password = "senha123"
  admin.password_confirmation = "senha123"
  admin.role = :admin
  admin.save!

  puts "Production seed concluido: admin criado/atualizado (#{admin.email})"
elsif Rails.env.development?
  puts "Limpando usuarios de desenvolvimento..."
  User.destroy_all

  email = ENV.fetch("DEV_ADMIN_EMAIL", "admin@admin.com")
  name = ENV.fetch("DEV_ADMIN_NAME", "Admin")
  password = ENV.fetch("DEV_ADMIN_PASSWORD", "password123")

  admin = User.new(
    email: email,
    name: name,
    role: :admin,
    password: password,
    password_confirmation: password
  )
  admin.save!

  puts "Development seed concluido: usuario unico criado como admin"
  puts "- email: #{admin.email}"
  puts "- role: #{admin.role}"
else
  puts "Skipping seeds in #{Rails.env}: no data configured for this environment"
end
