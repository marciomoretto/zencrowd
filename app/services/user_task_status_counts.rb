class UserTaskStatusCounts
  STATUSES = %w[submitted in_review approved rejected payment_requested paid].freeze

  def self.returned_condition(user_id_sql)
    <<~SQL.squish
      images.status = #{Image.statuses.fetch('reserved')}
      AND images.reserver_id = #{user_id_sql}
      AND EXISTS (
        SELECT 1 FROM annotations a
        INNER JOIN reviews r ON r.annotation_id = a.id
        WHERE a.image_id = images.id AND a.user_id = #{user_id_sql}
          AND r.status = #{Review.statuses.fetch('rejected')}
          AND a.id = (
            SELECT latest.id FROM annotations latest WHERE latest.image_id = images.id
            ORDER BY latest.created_at DESC, latest.id DESC LIMIT 1
          )
      )
    SQL
  end

  def self.for_users(user_ids)
    return {} if user_ids.empty?

    annotations = Annotation.where(user_id: user_ids).select(:user_id, :image_id)
    reservations = Tile.where(reserver_id: user_ids).select('reserver_id AS user_id, id AS image_id')
    payments = PaymentItem.joins(:payment).where(payments: { annotator_id: user_ids })
                          .select('payments.annotator_id AS user_id, payment_items.tile_id AS image_id')
    owners = [annotations, reservations, payments].map(&:to_sql).join(' UNION ')

    grouped = Tile.joins("INNER JOIN (#{owners}) task_owners ON task_owners.image_id = images.id")
                  .where('images.status IN (?) OR (' + returned_condition('task_owners.user_id') + ')',
                         STATUSES.map { |status| Image.statuses.fetch(status) })
                  .group('task_owners.user_id', 'images.status').count
    counts = Hash.new { |hash, user_id| hash[user_id] = Hash.new(0) }
    grouped.each do |(user_id, status), count|
      category = case status
                 when 'submitted', 'in_review' then :in_review
                 when 'reserved', 'rejected' then :returned
                 else status.to_sym
                 end
      counts[user_id][category] += count
    end
    counts
  end
end
