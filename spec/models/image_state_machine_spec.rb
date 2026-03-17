require 'rails_helper'

RSpec.describe 'Image State Transitions', type: :model do
  let(:admin) { create(:user, :admin) }
  let(:annotator) { create(:user, :annotator) }
  let(:reviewer) { create(:user, :reviewer) }
  let(:image) { create(:image, uploader: admin, status: :available) }
  let(:fake_tar) do
    file = Tempfile.new(['projeto', '.tar'])
    file.write('conteudo tar')
    file.rewind
    Rack::Test::UploadedFile.new(file.path, 'application/x-tar', original_filename: 'projeto.tar')
  end
  let(:fake_csv) do
    file = Tempfile.new(['dados', '.csv'])
    file.write('coluna1,coluna2\nvalor1,valor2')
    file.rewind
    Rack::Test::UploadedFile.new(file.path, 'text/csv', original_filename: 'dados.csv')
  end

  describe '#reserve!' do
    context 'with valid transition' do
      it 'transitions from available to reserved' do
        expect {
          image.reserve!(annotator)
        }.to change { image.status }.from('available').to('reserved')
      end

      it 'sets reserver and reserved_at' do
        image.reserve!(annotator)
        expect(image.reserver).to eq(annotator)
        expect(image.reserved_at).to be_present
      end
    end

    context 'with invalid transition' do
      it 'raises error when image is not available' do
        image.update!(status: :reserved)
        expect {
          image.reserve!(annotator)
        }.to raise_error(Image::StateMachineError, 'Image is not available')
      end

      it 'raises error when user is not an annotator' do
        expect {
          image.reserve!(reviewer)
        }.to raise_error(Image::StateMachineError, 'User must be an annotator')
      end

      it 'raises error when user already has a reserved image' do
        other_image = create(:image, uploader: admin, status: :available)
        image.reserve!(annotator)
        
        expect {
          other_image.reserve!(annotator)
        }.to raise_error(Image::StateMachineError, 'User already has a reserved image')
      end
    end
  end

  describe '#submit!' do
    let(:fake_tar) { Rack::Test::UploadedFile.new(StringIO.new('tar'), 'application/x-tar', original_filename: 'projeto.tar') }
    let(:fake_csv) { Rack::Test::UploadedFile.new(StringIO.new('csv'), 'text/csv', original_filename: 'dados.csv') }
    before do
      image.update!(status: :reserved, reserver: annotator, reserved_at: Time.current)
    end

    context 'with valid transition' do
      it 'transitions from reserved to submitted' do
        expect {
          image.submit!(annotator, fake_tar, fake_csv)
        }.to change { image.status }.from('reserved').to('submitted')
      end
    end

    context 'with invalid transition' do
      it 'raises error when image is not reserved' do
        image.update!(status: :available)
        expect {
          image.submit!(annotator, fake_tar, fake_csv)
        }.to raise_error(Image::StateMachineError, 'Image is not reserved')
      end

      it 'raises error when user is not the reserver' do
        other_annotator = create(:user, :annotator)
        expect {
          image.submit!(other_annotator, fake_tar, fake_csv)
        }.to raise_error(Image::StateMachineError, 'Only the reserver can submit')
      end
    end
  end

  describe '#start_review!' do
    before do
      image.update!(status: :submitted)
    end

    context 'with valid transition' do
      it 'transitions from submitted to in_review' do
        expect {
          image.start_review!(reviewer)
        }.to change { image.status }.from('submitted').to('in_review')
      end
    end

    context 'with invalid transition' do
      it 'raises error when image is not submitted' do
        image.update!(status: :available)
        expect {
          image.start_review!(reviewer)
        }.to raise_error(Image::StateMachineError, 'Image is not submitted')
      end

      it 'raises error when user is not a reviewer' do
        expect {
          image.start_review!(annotator)
        }.to raise_error(Image::StateMachineError, 'User must be a reviewer')
      end
    end
  end

  describe '#approve!' do
    before do
      image.update!(status: :in_review)
    end

    context 'with valid transition' do
      it 'transitions from in_review to approved' do
        create(:annotation, image: image, user: annotator)
        expect {
          image.approve!(reviewer)
        }.to change { image.status }.from('in_review').to('approved')
      end
    end

    context 'with invalid transition' do
      it 'raises error when image is not in review' do
        image.update!(status: :submitted)
        expect {
          image.approve!(reviewer)
        }.to raise_error(Image::StateMachineError, 'Image is not in review')
      end

      it 'raises error when user is not a reviewer' do
        expect {
          image.approve!(annotator)
        }.to raise_error(Image::StateMachineError, 'User must be a reviewer')
      end
    end
  end

  describe '#reject!' do
    before do
      image.update!(status: :in_review, reserver: annotator, reserved_at: 1.hour.ago)
    end

    context 'with valid transition' do
      it 'transitions from in_review back to reserved' do
        create(:annotation, image: image, user: annotator)
        expect {
          image.reject!(reviewer)
        }.to change { image.status }.from('in_review').to('reserved')
      end

      it 'updates reserved_at timestamp' do
        create(:annotation, image: image, user: annotator)
        old_time = image.reserved_at
        image.reject!(reviewer)
        expect(image.reserved_at).to be > old_time
      end

      it 'keeps the same reserver' do
        create(:annotation, image: image, user: annotator)
        expect {
          image.reject!(reviewer)
        }.not_to change { image.reserver }
      end
    end

    context 'with invalid transition' do
      it 'raises error when image is not in review' do
        image.update!(status: :submitted)
        expect {
          image.reject!(reviewer)
        }.to raise_error(Image::StateMachineError, 'Image is not in review')
      end

      it 'raises error when user is not a reviewer' do
        expect {
          image.reject!(annotator)
        }.to raise_error(Image::StateMachineError, 'User must be a reviewer')
      end
    end
  end

  describe '#mark_as_paid!' do
    before do
      image.update!(status: :approved)
    end

    context 'with valid transition' do
      it 'transitions from approved to paid' do
        expect {
          image.mark_as_paid!(admin)
        }.to change { image.status }.from('approved').to('paid')
      end
    end

    context 'with invalid transition' do
      it 'raises error when image is not approved' do
        image.update!(status: :in_review)
        expect {
          image.mark_as_paid!(admin)
        }.to raise_error(Image::StateMachineError, 'Image is not approved')
      end

      it 'raises error when user is not an admin' do
        expect {
          image.mark_as_paid!(annotator)
        }.to raise_error(Image::StateMachineError, 'Only admins can mark as paid')
      end
    end
  end

  describe '#expire_reservation!' do
    before do
      image.update!(status: :reserved, reserver: annotator, reserved_at: Time.current)
    end

    context 'with valid transition' do
      it 'transitions from reserved to available' do
        expect {
          image.expire_reservation!
        }.to change { image.status }.from('reserved').to('available')
      end

      it 'clears reserver and reserved_at' do
        image.expire_reservation!
        expect(image.reserver).to be_nil
        expect(image.reserved_at).to be_nil
      end
    end

    context 'with invalid transition' do
      it 'raises error when image is not reserved' do
        image.update!(status: :available)
        expect {
          image.expire_reservation!
        }.to raise_error(Image::StateMachineError, 'Image is not reserved')
      end
    end
  end

  describe '#reservation_expired?' do
    it 'returns true when reservation is older than expiration time' do
      image.update!(
        status: :reserved,
        reserver: annotator,
        reserved_at: (Image::RESERVATION_EXPIRATION_HOURS + 1).hours.ago
      )
      expect(image.reservation_expired?).to be true
    end

    it 'returns false when reservation is recent' do
      image.update!(
        status: :reserved,
        reserver: annotator,
        reserved_at: 1.hour.ago
      )
      expect(image.reservation_expired?).to be false
    end

    it 'returns false when image is not reserved' do
      expect(image.reservation_expired?).to be false
    end
  end

  describe '.expire_all_reservations!' do
    it 'expires all old reservations' do
      old_reservation = create(:image, 
        uploader: admin,
        status: :reserved, 
        reserver: annotator,
        reserved_at: (Image::RESERVATION_EXPIRATION_HOURS + 1).hours.ago
      )
      
      recent_reservation = create(:image,
        uploader: admin,
        status: :reserved,
        reserver: create(:user, :annotator),
        reserved_at: 1.hour.ago
      )

      Image.expire_all_reservations!

      expect(old_reservation.reload.status).to eq('available')
      expect(recent_reservation.reload.status).to eq('reserved')
    end
  end

  describe 'complete workflow' do
    it 'follows the complete happy path' do
      # available -> reserved
      image.reserve!(annotator)
      expect(image.status).to eq('reserved')

      # reserved -> submitted
      image.submit!(annotator, fake_tar, fake_csv)
      expect(image.status).to eq('submitted')

      # submitted -> in_review
      image.start_review!(reviewer)
      expect(image.status).to eq('in_review')

      # in_review -> approved
      image.approve!(reviewer)
      expect(image.status).to eq('approved')

      # approved -> paid
      image.mark_as_paid!(admin)
      expect(image.status).to eq('paid')
    end

    it 'handles rejection and resubmission' do
      # available -> reserved -> submitted -> in_review
      image.reserve!(annotator)
      image.submit!(annotator, fake_tar, fake_csv)
      image.start_review!(reviewer)

      # in_review -> reserved (rejection)
      image.reject!(reviewer)
      expect(image.status).to eq('reserved')
      expect(image.reserver).to eq(annotator)

      # reserved -> submitted -> in_review -> approved
      image.submit!(annotator, fake_tar, fake_csv)
      image.start_review!(reviewer)
      image.approve!(reviewer)
      expect(image.status).to eq('approved')
    end
  end
end
