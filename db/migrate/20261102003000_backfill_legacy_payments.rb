class BackfillLegacyPayments < ActiveRecord::Migration[7.1]
  PAID_STATUS = 6
  ANNOTATOR_ROLE = 1
  FINANCE_ROLE = 4

  class UserRecord < ActiveRecord::Base
    self.table_name = 'users'
  end

  class ImageRecord < ActiveRecord::Base
    self.table_name = 'images'
  end

  class AnnotationRecord < ActiveRecord::Base
    self.table_name = 'annotations'
  end

  class PaymentRecord < ActiveRecord::Base
    self.table_name = 'payments'
  end

  class PaymentItemRecord < ActiveRecord::Base
    self.table_name = 'payment_items'
  end

  def up
    paid_tiles = ImageRecord.where(status: PAID_STATUS).order(:id).lock.to_a
    return if paid_tiles.empty?

    raise 'Legacy payment data already exists in payments tables' if PaymentRecord.exists? || PaymentItemRecord.exists?

    finance_ids = UserRecord.where(role: FINANCE_ROLE).pluck(:id)
    raise "Expected exactly one finance user, found #{finance_ids.size}" unless finance_ids.one?

    annotations_by_tile = AnnotationRecord.where(image_id: paid_tiles.map(&:id))
                                          .pluck(:image_id, :user_id)
                                          .group_by(&:first)
    candidate_user_ids = paid_tiles.flat_map do |tile|
      (annotations_by_tile[tile.id] || []).map(&:last) + [tile.reserver_id]
    end.compact.uniq
    annotator_ids = UserRecord.where(role: ANNOTATOR_ROLE, id: candidate_user_ids).pluck(:id)

    annotator_ids_by_tile = paid_tiles.map do |tile|
      candidates = ((annotations_by_tile[tile.id] || []).map(&:last) + [tile.reserver_id])
      candidates &= annotator_ids
      raise "Expected exactly one annotator for paid tile #{tile.id}" unless candidates.uniq.one?

      candidates.first
    end
    raise 'Legacy paid tiles do not belong to one annotator' unless annotator_ids_by_tile.uniq.one?

    paid_at_values = paid_tiles.map(&:updated_at).uniq
    raise "Expected one legacy payment timestamp, found #{paid_at_values.size}" unless paid_at_values.one?

    amount = paid_tiles.sum { |tile| tile.task_value.to_d }
    raise 'Legacy payment total must be greater than zero' unless amount.positive?

    PaymentRecord.transaction do
      payment = PaymentRecord.create!(
        annotator_id: annotator_ids_by_tile.first,
        processed_by_id: finance_ids.first,
        amount: amount,
        paid_at: paid_at_values.first
      )
      paid_tiles.each do |tile|
        PaymentItemRecord.create!(payment_id: payment.id, tile_id: tile.id, amount: tile.task_value.to_d)
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Payment audit records must be retained'
  end
end
