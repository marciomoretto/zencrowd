require 'rails_helper'
require 'rake'

RSpec.describe 'images:expire_reservations rake task', type: :task do
  before :all do
    Rake.application.rake_require 'tasks/images'
    Rake::Task.define_task(:environment)
  end

  def clean_image_related_records
    Review.delete_all
    AnnotationPoint.delete_all
    Annotation.delete_all
    Assignment.delete_all
    Image.delete_all
  end

  let(:task) { Rake::Task['images:expire_reservations'] }
  let(:admin) { create(:user, :admin) }
  let(:annotator1) { create(:user, :annotator) }
  let(:annotator2) { create(:user, :annotator) }

  before do
    task.reenable
    clean_image_related_records
  end

  after do
    clean_image_related_records
  end

  it 'expires old reservations' do
    # Criar imagens com reservas antigas (expiradas)
    old_reservation1 = create(:image,
      uploader: admin,
      status: :reserved,
      reserver: annotator1,
      reserved_at: (Image::RESERVATION_EXPIRATION_HOURS + 1).hours.ago
    )

    old_reservation2 = create(:image,
      uploader: admin,
      status: :reserved,
      reserver: annotator2,
      reserved_at: (Image::RESERVATION_EXPIRATION_HOURS + 5).hours.ago
    )

    # Criar imagem com reserva recente (não expirada)
    recent_reservation = create(:image,
      uploader: admin,
      status: :reserved,
      reserver: create(:user, :annotator),
      reserved_at: 1.hour.ago
    )

    # Criar imagem disponível (não deve ser afetada)
    available_image = create(:image,
      uploader: admin,
      status: :available
    )

    # Executar a rake task
    expect {
      task.invoke
    }.to output(/Starting reservation expiration task.*Finished! Expired 2 reservation\(s\)/m).to_stdout

    # Verificar que as reservas antigas foram expiradas
    expect(old_reservation1.reload.status).to eq('available')
    expect(old_reservation1.reserver).to be_nil
    expect(old_reservation1.reserved_at).to be_nil

    expect(old_reservation2.reload.status).to eq('available')
    expect(old_reservation2.reserver).to be_nil
    expect(old_reservation2.reserved_at).to be_nil

    # Verificar que a reserva recente não foi afetada
    expect(recent_reservation.reload.status).to eq('reserved')
    expect(recent_reservation.reserver).to be_present
    expect(recent_reservation.reserved_at).to be_present

    # Verificar que a imagem disponível não foi afetada
    expect(available_image.reload.status).to eq('available')
  end

  it 'handles when there are no expired reservations' do
    # Criar apenas imagens que não devem ser expiradas
    create(:image, uploader: admin, status: :available)
    create(:image,
      uploader: admin,
      status: :reserved,
      reserver: annotator1,
      reserved_at: 1.hour.ago
    )

    expect {
      task.invoke
    }.to output(/Starting reservation expiration task.*Finished! Expired 0 reservation\(s\)/m).to_stdout
  end

  it 'counts expired reservations correctly' do
    # Criar 3 reservas expiradas
    3.times do |i|
      create(:image,
        uploader: admin,
        status: :reserved,
        reserver: create(:user, :annotator),
        reserved_at: (Image::RESERVATION_EXPIRATION_HOURS + i + 1).hours.ago
      )
    end

    expect {
      task.invoke
    }.to output(/Starting reservation expiration task.*Finished! Expired 3 reservation\(s\)/m).to_stdout

    # Verificar que todas foram expiradas
    expect(Image.where(status: :reserved).count).to eq(0)
    expect(Image.where(status: :available).count).to eq(3)
  end

  it 'handles errors gracefully' do
    # Criar uma reserva expirada
    old_reservation = create(:image,
      uploader: admin,
      status: :reserved,
      reserver: annotator1,
      reserved_at: (Image::RESERVATION_EXPIRATION_HOURS + 1).hours.ago
    )

    # Simular um erro ao expirar
    allow_any_instance_of(Image).to receive(:expire_reservation!).and_raise(StandardError.new('Test error'))

    expect {
      task.invoke
    }.to output(/Starting reservation expiration task.*Error expiring reservation for image #{old_reservation.id}: Test error.*Finished! Expired 0 reservation\(s\)/m).to_stdout

    # Verificar que a imagem ainda está reservada (erro impediu a expiração)
    expect(old_reservation.reload.status).to eq('reserved')
  end
end
