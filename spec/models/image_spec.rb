require 'rails_helper'

RSpec.describe Image, type: :model do
  let(:uploader) { create(:user, role: :admin) }

  describe 'validations' do
    it 'requires original_filename' do
      image = Image.new(storage_path: '/path/to/image.jpg', uploader: uploader, status: :available)
      expect(image).not_to be_valid
      expect(image.errors[:original_filename]).to include("can't be blank")
    end

    it 'requires storage_path' do
      image = Image.new(original_filename: 'image.jpg', uploader: uploader, status: :available)
      expect(image).not_to be_valid
      expect(image.errors[:storage_path]).to include("can't be blank")
    end

    it 'requires status' do
      image = Image.new(original_filename: 'image.jpg', storage_path: '/path/to/image.jpg', uploader: uploader)
      image.status = nil
      expect(image).not_to be_valid
    end

    it 'validates task_value is non-negative' do
      image = Image.new(
        original_filename: 'image.jpg',
        storage_path: '/path/to/image.jpg',
        uploader: uploader,
        status: :available,
        task_value: -10
      )
      expect(image).not_to be_valid
      expect(image.errors[:task_value]).to be_present
    end

    it 'allows nil task_value' do
      image = Image.new(
        original_filename: 'image.jpg',
        storage_path: '/path/to/image.jpg',
        uploader: uploader,
        status: :available,
        task_value: nil
      )
      expect(image).to be_valid
    end

    it 'prevents user from reserving multiple images' do
      reserver = create(:user, role: :annotator)
      create(:image, reserver: reserver, status: :reserved)
      
      image = Image.new(
        original_filename: 'image2.jpg',
        storage_path: '/path/to/image2.jpg',
        uploader: uploader,
        reserver: reserver,
        status: :reserved
      )
      
      expect(image).not_to be_valid
      expect(image.errors[:base]).to include('User already has a reserved image')
    end
  end

  describe 'associations' do
    let(:image) { create(:image) }

    it 'belongs to uploader' do
      expect(image.uploader).to be_a(User)
    end

    it 'can belong to reserver' do
      expect(image).to respond_to(:reserver)
    end

    it 'has many annotations' do
      expect(image).to respond_to(:annotations)
    end
  end

  describe 'enums' do
    let(:image) { create(:image) }

    it 'defines available status' do
      image.status = :available
      expect(image.available?).to be true
    end

    it 'defines reserved status' do
      image.status = :reserved
      expect(image.reserved?).to be true
    end

    it 'defines submitted status' do
      image.status = :submitted
      expect(image.submitted?).to be true
    end

    it 'defines in_review status' do
      image.status = :in_review
      expect(image.in_review?).to be true
    end

    it 'defines approved status' do
      image.status = :approved
      expect(image.approved?).to be true
    end

    it 'defines rejected status' do
      image.status = :rejected
      expect(image.rejected?).to be true
    end

    it 'defines paid status' do
      image.status = :paid
      expect(image.paid?).to be true
    end
  end
end
