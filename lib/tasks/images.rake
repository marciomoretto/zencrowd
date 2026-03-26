namespace :images do
  desc 'Expire old image reservations'
  task expire_reservations: :environment do
    puts "Starting reservation expiration task..."
    
    expired_count = 0
    Image.expired_reservations.find_each do |image|
      begin
        image.expire_reservation!
        expired_count += 1
        puts "Expired reservation for image #{image.id} (#{image.original_filename})"
      rescue StandardError => e
        puts "Error expiring reservation for image #{image.id}: #{e.message}"
      end
    end
    
    puts "Finished! Expired #{expired_count} reservation(s)"
  end
end
