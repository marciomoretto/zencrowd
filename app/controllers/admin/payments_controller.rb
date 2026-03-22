class Admin::PaymentsController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!

  def index
    @sort = sort_param
    @direction = direction_param
    @users_payment_rows = build_users_payment_rows
  end

  def pay_requested
    annotator = User.find(params[:id])
    result = Image.pay_requested_for!(annotator, current_user)

    redirect_to admin_payments_path, notice: "Pagamento processado para #{annotator.name}: #{result[:updated_count]} tarefa(s), total #{view_context.number_to_currency(result[:paid_total], unit: 'R$', separator: ',', delimiter: '.', format: '%u%n')}."
  rescue ActiveRecord::RecordNotFound
    redirect_to admin_payments_path, alert: 'Usuário não encontrado.'
  rescue Image::StateMachineError => e
    redirect_to admin_payments_path, alert: e.message
  end

  private

  def sort_param
    sort = params[:sort].to_s
    %w[name to_receive requested paid].include?(sort) ? sort : 'to_receive'
  end

  def direction_param
    params[:direction].to_s == 'asc' ? 'asc' : 'desc'
  end

  def build_users_payment_rows
    users = User.order(:name).to_a
    status_totals_by_user = build_status_totals_by_user(users.map(&:id))

    rows = users.map do |user|
      totals = status_totals_by_user[user.id] || {}
      to_receive = totals.fetch('approved', 0.to_d)
      requested = totals.fetch('payment_requested', 0.to_d)
      paid = totals.fetch('paid', 0.to_d)

      {
        user: user,
        to_receive: to_receive,
        requested: requested,
        paid: paid
      }
    end

    sort_users_payment_rows(rows)
  end

  def build_status_totals_by_user(user_ids)
    totals = Hash.new { |hash, key| hash[key] = Hash.new(0.to_d) }
    return totals if user_ids.empty?

    user_ids_lookup = user_ids.each_with_object({}) { |id, hash| hash[id] = true }
    annotation_tile_ids = Annotation.where(user_id: user_ids).select(:image_id)

    Tile
      .includes(:annotations)
      .where(status: %i[approved payment_requested paid])
      .where('reserver_id IN (:user_ids) OR id IN (:annotation_tile_ids)', user_ids: user_ids, annotation_tile_ids: annotation_tile_ids)
      .find_each do |tile|
        associated_user_ids = tile.annotations.filter_map do |annotation|
          annotation.user_id if user_ids_lookup[annotation.user_id]
        end

        if tile.reserver_id.present? && user_ids_lookup[tile.reserver_id]
          associated_user_ids << tile.reserver_id
        end

        associated_user_ids.uniq.each do |user_id|
          totals[user_id][tile.status] += tile.task_value.to_d
        end
      end

    totals
  end

  def sort_users_payment_rows(rows)
    sorted = rows.sort_by do |row|
      value = case @sort
              when 'name'
                row[:user].name.to_s.downcase
              when 'requested'
                row[:requested]
              when 'paid'
                row[:paid]
              else
                row[:to_receive]
              end

      [value, row[:user].id]
    end

    @direction == 'asc' ? sorted : sorted.reverse
  end
end
