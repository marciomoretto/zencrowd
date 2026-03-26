require 'rails_helper'
require 'securerandom'

RSpec.describe User, type: :model do
  def unique_email(prefix = 'user')
    "#{prefix}_#{SecureRandom.hex(4)}@example.com"
  end

  describe 'validations' do
    it 'requires email' do
      user = User.new(name: 'Test', role: :annotator, password: 'password123')
      expect(user).not_to be_valid
      expect(user.errors[:email]).to include("E-mail não pode ficar em branco")
    end

    it 'requires unique email' do
      email = unique_email('duplicate')
      User.create!(email: email, name: 'Test', role: :annotator, password: 'password123')
      user = User.new(email: email, name: 'Test 2', role: :annotator, password: 'password123')
      expect(user).not_to be_valid
      expect(user.errors[:email]).to include('já está em uso')
    end

    it 'requires name' do
      user = User.new(email: unique_email('missing_name'), role: :annotator, password: 'password123')
      expect(user).not_to be_valid
      expect(user.errors[:name]).to include("Nome não pode ficar em branco")
    end

    it 'requires role' do
      user = User.new(email: unique_email('missing_role'), name: 'Test', password: 'password123')
      user.role = nil
      expect(user).not_to be_valid
    end

    it 'validates email format' do
      user = User.new(name: 'Test', role: :annotator, password: 'password123')
      
      user.email = 'invalid-email'
      expect(user).not_to be_valid
      
      user.email = unique_email('valid')
      expect(user).to be_valid
    end
  end

  describe 'authentication' do
    it 'has secure password' do
      user = User.new(
        email: unique_email('auth'),
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
        email: unique_email('auth_mismatch'),
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
        email: unique_email('admin'),
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
        email: unique_email('annotator'),
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
        email: unique_email('reviewer'),
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
    let(:user) { User.create!(email: unique_email('association'), name: 'Test', role: :admin, password: 'password123') }

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
