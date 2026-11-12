require 'rails_helper'

RSpec.describe UserTaskStatusCounts do
  it 'counts each associated tile once per user in its current category' do
    user = create(:user, :annotator)
    other = create(:user, :annotator)
    third = create(:user, :annotator)
    reviewer = create(:user, :reviewer)
    %i[submitted in_review approved rejected payment_requested paid].each do |status|
      tile = create(:tile, status: status, reserver: user)
      create_list(:annotation, 2, image: tile, user: user)
    end
    returned = create(:tile, status: :reserved, reserver: user)
    annotation = create(:annotation, image: returned, user: user)
    create(:review, :rejected, annotation: annotation, reviewer: reviewer)
    ordinary = create(:tile, status: :reserved, reserver: other)
    create(:annotation, image: ordinary, user: other)
    obsolete = create(:tile, status: :reserved, reserver: third)
    old = create(:annotation, image: obsolete, user: third, created_at: 1.day.ago)
    create(:review, :rejected, annotation: old, reviewer: reviewer)
    create(:annotation, image: obsolete, user: third)
    create(:tile, status: :available, reserver: user)

    counts = described_class.for_users([user.id, other.id, third.id])
    expect(counts[user.id]).to include(in_review: 2, approved: 1, returned: 2, payment_requested: 1, paid: 1)
    expect(counts[other.id]).to be_empty
    expect(counts[third.id]).to be_empty
  end

  it 'includes legacy reservations and recorded payments without annotations' do
    user = create(:user, :annotator)
    finance = create(:user, :finance)
    create(:tile, status: :approved, reserver: user)
    tile = create(:tile, status: :paid)
    payment = Payment.create!(annotator: user, processed_by: finance, amount: 10, paid_at: Time.current)
    payment.payment_items.create!(tile: tile, amount: 10)

    expect(described_class.for_users([user.id])[user.id]).to include(approved: 1, paid: 1)
    expect(described_class.for_users([])).to eq({})
  end
end
