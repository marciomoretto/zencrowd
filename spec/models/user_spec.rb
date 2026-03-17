require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'validations' do
    it 'requires email' do
      user = User.new(name: 'Test', role: :annotator, password: 'password123')
      expect(user).not_to be_valid
      expect(user.errors[:email]).to include("can't be blank")
    end

    it 'requires unique email' do
      User.create!(email: 'test@example.com', name: 'Test', role: :annotator, password: 'password123')
      user = User.new(email: 'test@example.com', name: 'Test 2', role: :annotator, password: 'password123')
      expect(user).not_to be_valid
      expect(user.errors[:email]).to include('has already been taken')
    end

    it 'requires name' do
      user = User.new(email: 'test@example.com', role: :annotator, password: 'password123')
      expect(user).not_to be_valid
      expect(user.errors[:name]).to include("can't be blank")
    end

    it 'requires role' do
      user = User.new(email: 'test@example.com', name: 'Test', password: 'password123')
      user.role = nil
      expect(user).not_to be_valid
    end

    it 'validates email format' do
      user = User.new(name: 'Test', role: :annotator, password: 'password123')
      
      user.email = 'invalid-email'
      expect(user).not_to be_valid
      
      user.email = 'valid@example.com'
      expect(user).to be_valid
    end
  end

  describe 'authentication' do
    it 'has secure password' do
      user = User.new(
        email: 'test@example.com', 
        name: 'Test User', 
        role: :annotator,
        password: 'password123',
        password_confirmation: 'password123'
      )
      
      expect(user.save).to be true
      expect(user.authenticate('password123')).to eq(user)
      expect(user.authenticate('wrongpassword')).to be false
    end

    it 'requires password confirmation to match' do
      user = User.new(
        email: 'test@example.com',
        name: 'Test User',
        role: :annotator,
        password: 'password123',
        password_confirmation: 'different'
      )
      
      expect(user).not_to be_valid
    end
  end

  describe 'roles' do
    it 'defines admin role' do
      user = User.create!(
        email: 'admin@example.com',
        name: 'Admin',
        role: :admin,
        password: 'password123'
      )
      
      expect(user.admin?).to be true
      expect(user.annotator?).to be false
      expect(user.reviewer?).to be false
    end

    it 'defines annotator role' do
      user = User.create!(
        email: 'annotator@example.com',
        name: 'Annotator',
        role: :annotator,
        password: 'password123'
      )
      
      expect(user.annotator?).to be true
      expect(user.admin?).to be false
      expect(user.reviewer?).to be false
    end

    it 'defines reviewer role' do
      user = User.create!(
        email: 'reviewer@example.com',
        name: 'Reviewer',
        role: :reviewer,
        password: 'password123'
      )
      
      expect(user.reviewer?).to be true
      expect(user.admin?).to be false
      expect(user.annotator?).to be false
    end
  end

  describe 'associations' do
    let(:user) { User.create!(email: 'test@example.com', name: 'Test', role: :admin, password: 'password123') }

    it 'has uploaded_images association' do
      expect(user).to respond_to(:uploaded_images)
    end

    it 'has reserved_images association' do
      expect(user).to respond_to(:reserved_images)
    end

    it 'has annotations association' do
      expect(user).to respond_to(:annotations)
    end

    it 'has reviews association' do
      expect(user).to respond_to(:reviews)
    end
  end
end
