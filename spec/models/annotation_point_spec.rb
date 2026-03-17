require 'rails_helper'

RSpec.describe AnnotationPoint, type: :model do
  describe 'validations' do
    it 'requires annotation' do
      point = AnnotationPoint.new(x: 100, y: 200)
      expect(point).not_to be_valid
      expect(point.errors[:annotation]).to include("can't be blank")
    end

    it 'requires x coordinate' do
      annotation = create(:annotation)
      point = AnnotationPoint.new(annotation: annotation, y: 200)
      expect(point).not_to be_valid
      expect(point.errors[:x]).to include("can't be blank")
    end

    it 'requires y coordinate' do
      annotation = create(:annotation)
      point = AnnotationPoint.new(annotation: annotation, x: 100)
      expect(point).not_to be_valid
      expect(point.errors[:y]).to include("can't be blank")
    end

    it 'validates x is an integer' do
      annotation = create(:annotation)
      point = AnnotationPoint.new(annotation: annotation, x: 100.5, y: 200)
      expect(point).not_to be_valid
      expect(point.errors[:x]).to be_present
    end

    it 'validates y is an integer' do
      annotation = create(:annotation)
      point = AnnotationPoint.new(annotation: annotation, x: 100, y: 200.5)
      expect(point).not_to be_valid
      expect(point.errors[:y]).to be_present
    end

    it 'validates x is non-negative' do
      annotation = create(:annotation)
      point = AnnotationPoint.new(annotation: annotation, x: -10, y: 200)
      expect(point).not_to be_valid
      expect(point.errors[:x]).to be_present
    end

    it 'validates y is non-negative' do
      annotation = create(:annotation)
      point = AnnotationPoint.new(annotation: annotation, x: 100, y: -10)
      expect(point).not_to be_valid
      expect(point.errors[:y]).to be_present
    end

    it 'is valid with valid attributes' do
      annotation = create(:annotation)
      point = AnnotationPoint.new(annotation: annotation, x: 100, y: 200)
      expect(point).to be_valid
    end

    it 'allows zero coordinates' do
      annotation = create(:annotation)
      point = AnnotationPoint.new(annotation: annotation, x: 0, y: 0)
      expect(point).to be_valid
    end
  end

  describe 'associations' do
    let(:point) { create(:annotation_point) }

    it 'belongs to annotation' do
      expect(point.annotation).to be_a(Annotation)
    end
  end
end
