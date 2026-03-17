require 'rails_helper'

RSpec.describe Review, type: :model do
  describe 'validations' do
    it 'requires annotation' do
      reviewer = create(:user, role: :reviewer)
      review = Review.new(reviewer: reviewer, status: :approved)
      expect(review).not_to be_valid
      expect(review.errors[:annotation]).to include("Anotação não pode ficar em branco")
    end

    it 'requires reviewer' do
      annotation = create(:annotation)
      review = Review.new(annotation: annotation, status: :approved)
      expect(review).not_to be_valid
      expect(review.errors[:reviewer]).to include("Revisor não pode ficar em branco")
    end

    it 'requires status' do
      annotation = create(:annotation)
      reviewer = create(:user, role: :reviewer)
      review = Review.new(annotation: annotation, reviewer: reviewer)
      review.status = nil
      expect(review).not_to be_valid
    end

    it 'validates reviewer has reviewer role' do
      annotation = create(:annotation)
      non_reviewer = create(:user, role: :annotator)
      review = Review.new(annotation: annotation, reviewer: non_reviewer, status: :approved)
      
      expect(review).not_to be_valid
      expect(review.errors[:reviewer]).to include('must have reviewer role')
    end

    it 'is valid with reviewer role' do
      annotation = create(:annotation)
      reviewer = create(:user, role: :reviewer)
      review = Review.new(annotation: annotation, reviewer: reviewer, status: :approved)
      
      expect(review).to be_valid
    end
  end

  describe 'associations' do
    let(:review) { create(:review) }

    it 'belongs to annotation' do
      expect(review.annotation).to be_a(Annotation)
    end

    it 'belongs to reviewer' do
      expect(review.reviewer).to be_a(User)
    end
  end

  describe 'enums' do
    let(:annotation) { create(:annotation) }
    let(:reviewer) { create(:user, role: :reviewer) }

    it 'defines approved status' do
      review = Review.create!(annotation: annotation, reviewer: reviewer, status: :approved)
      expect(review.approved?).to be true
      expect(review.rejected?).to be false
    end

    it 'defines rejected status' do
      review = Review.create!(annotation: annotation, reviewer: reviewer, status: :rejected)
      expect(review.rejected?).to be true
      expect(review.approved?).to be false
    end
  end
end
