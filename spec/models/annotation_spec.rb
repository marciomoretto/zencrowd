require 'rails_helper'

RSpec.describe Annotation, type: :model do
  describe 'validations' do
    it 'requires image' do
      user = create(:user, role: :annotator)
      annotation = Annotation.new(user: user)
      expect(annotation).not_to be_valid
      expect(annotation.errors[:image]).to include("can't be blank")
    end

    it 'requires user' do
      image = create(:image)
      annotation = Annotation.new(image: image)
      expect(annotation).not_to be_valid
      expect(annotation.errors[:user]).to include("can't be blank")
    end

    it 'is valid with image and user' do
      image = create(:image)
      user = create(:user, role: :annotator)
      annotation = Annotation.new(image: image, user: user)
      expect(annotation).to be_valid
    end
  end

  describe 'associations' do
    let(:annotation) { create(:annotation) }

    it 'belongs to image' do
      expect(annotation.image).to be_a(Image)
    end

    it 'belongs to user' do
      expect(annotation.user).to be_a(User)
    end

    it 'has many annotation_points' do
      expect(annotation).to respond_to(:annotation_points)
    end

    it 'has one review' do
      expect(annotation).to respond_to(:review)
    end

    it 'destroys associated annotation_points when deleted' do
      annotation = create(:annotation)
      point = create(:annotation_point, annotation: annotation)
      
      expect { annotation.destroy }.to change { AnnotationPoint.count }.by(-1)
    end
  end

  describe 'nested attributes' do
    it 'accepts nested attributes for annotation_points' do
      image = create(:image)
      user = create(:user, role: :annotator)
      
      annotation = Annotation.create!(
        image: image,
        user: user,
        annotation_points_attributes: [
          { x: 100, y: 200 },
          { x: 150, y: 250 }
        ]
      )
      
      expect(annotation.annotation_points.count).to eq(2)
    end

    it 'allows destroying annotation_points through nested attributes' do
      annotation = create(:annotation)
      point = create(:annotation_point, annotation: annotation)
      
      annotation.update(
        annotation_points_attributes: [
          { id: point.id, _destroy: true }
        ]
      )
      
      expect(annotation.annotation_points.count).to eq(0)
    end
  end
end
