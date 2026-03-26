class Image < ApplicationRecord
  # Associations
  belongs_to :uploader, class_name: 'User', foreign_key: 'uploader_id'
  belongs_to :reserver, class_name: 'User', foreign_key: 'reserver_id', optional: true
  has_many :annotations, dependent: :restrict_with_error

  # Enums
  enum status: {
    available: 0,
    reserved: 1,
    submitted: 2,
    in_review: 3,
    approved: 4,
    rejected: 5,
    paid: 6,
    abandoned: 7,
    payment_requested: 8
  }

  # Constants
  RESERVATION_EXPIRATION_HOURS = 48

  # Validations
  validates :original_filename, presence: true
  validates :storage_path, presence: true
  validates :status, presence: true
  validates :task_value, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # Custom validations
  validate :user_can_reserve_only_one_image, if: :reserved?
  before_validation :map_returned_available_to_abandoned, on: :update

  # Scopes
  scope :expired_reservations, -> {
    where(status: :reserved)
      .where(
        'reservation_expires_at < ? OR (reservation_expires_at IS NULL AND reserved_at < ?)',
        Time.current,
        reservation_expiration_hours.hours.ago
      )
  }
  scope :to_pay, -> { where(status: %i[reserved submitted in_review approved payment_requested]) }

  def self.reservation_expiration_hours
    AppSetting.task_expiration_hours
  rescue StandardError
    RESERVATION_EXPIRATION_HOURS
  end

  # State transitions
  # available|abandoned -> reserved
  def reserve!(user)
    raise StateMachineError, 'Tile is not available' unless available? || abandoned?
    raise StateMachineError, 'User must be an annotator' unless user.annotator?
    
    # Check if user already has a reserved tile
    if Tile.where(reserver: user, status: :reserved).exists?
      raise StateMachineError, 'User already has a reserved tile'
    end

    if Tile.where(reserver: user, status: :rejected).exists?
      raise StateMachineError, 'User has rejected tasks pending'
    end

    if exceeds_budget_after_reservation?
      raise StateMachineError, 'Project is out of budget for new reservations'
    end

    transaction do
      reservation_started_at = Time.current
      update!(
        status: :reserved,
        reserver: user,
        reserved_at: reservation_started_at,
        reservation_expires_at: reservation_started_at + self.class.reservation_expiration_hours.hours
      )
    end
  end

  # reserved -> abandoned (annotator gives up task)
  def give_up!(user)
    raise StateMachineError, 'Tile is not reserved' unless reserved?
    raise StateMachineError, 'Only the reserver can give up this tile' unless reserver == user

    transaction do
      update!(
        status: :abandoned,
        reserver: nil,
        reserved_at: nil,
        reservation_expires_at: nil
      )
    end
  end

  # reserved -> in_review
  def submit!(user, projeto_tar, dados_csv, config_json = nil, zen_plot_points_json = nil)
    raise StateMachineError, 'Tile is not reserved' unless reserved?
    raise StateMachineError, 'Only the reserver can submit' unless reserver == user
    raise StateMachineError, 'Arquivos projeto_tar e dados_csv são obrigatórios' if projeto_tar.blank? || dados_csv.blank?

    transaction do
      # Cria a anotação e anexa os arquivos
      annotation = annotations.build(user: user, submitted_at: Time.current)
      annotation.projeto_tar.attach(projeto_tar)
      annotation.dados_csv.attach(dados_csv)
      annotation.config_json.attach(config_json) if config_json.present?
      build_annotation_points(annotation, zen_plot_points_json)

      unless annotation.save
        raise StateMachineError, "Erro ao salvar anotação: #{annotation.errors.full_messages.join(', ')}"
      end

      # Ao finalizar a anotacao, a tarefa entra direto em revisao.
      update!(status: :in_review)

      self.class.reserve_next_rejected_for!(user)
    end
  end

  # reserved -> in_review
  # New equivalent flow for ZenPlot finalization: submits without legacy files,
  # persisting only annotation points already captured in the UI.
  def submit_with_zen_plot_points!(user, zen_plot_points_json = nil)
    raise StateMachineError, 'Tile is not reserved' unless reserved?
    raise StateMachineError, 'Only the reserver can submit' unless reserver == user

    transaction do
      annotation = annotations.build(user: user, submitted_at: Time.current)
      build_annotation_points(annotation, zen_plot_points_json)

      unless annotation.save
        raise StateMachineError, "Erro ao salvar anotação: #{annotation.errors.full_messages.join(', ')}"
      end

      update!(status: :in_review)

      self.class.reserve_next_rejected_for!(user)
    end
  end

  # submitted -> in_review
  def start_review!(reviewer)
    raise StateMachineError, 'User must be a reviewer' unless reviewer.reviewer?

    return true if in_review?
    raise StateMachineError, 'Tile is not submitted' unless submitted?

    update!(status: :in_review)
  end

 # in_review -> approved
  def approve!(reviewer)
    raise StateMachineError, 'User must be a reviewer' unless reviewer.reviewer?

    raise StateMachineError, 'Tile is not in review' unless in_review? || submitted?

    transaction do
      # Compatibilidade: itens antigos em submitted entram em revisao implicitamente.
      update!(status: :in_review) if submitted?

      # Encontra a última anotação feita (a que está sendo revisada)
      annotation = annotations.order(created_at: :desc).first
      raise StateMachineError, 'Nenhuma anotação encontrada para aprovar' unless annotation

      # Cria o registro de revisão como Aprovado (usando o enum 0)
      Review.create!(
        annotation: annotation,
        reviewer: reviewer,
        status: :approved
      )
      
      # Sela o tile
      update!(status: :approved)
    end
  end

  # in_review -> rejected
  def reject!(reviewer)
      puts "DEBUG: Entrou no método reject! do model para tile ##{id} (status: #{status})"
    raise StateMachineError, 'User must be a reviewer' unless reviewer.reviewer?

    raise StateMachineError, 'Tile is not in review' unless in_review? || submitted?

    transaction do
      # Compatibilidade: itens antigos em submitted entram em revisao implicitamente.
      update!(status: :in_review) if submitted?

      # Encontra a última anotação feita (a que está sendo rejeitada)
      annotation = annotations.order(created_at: :desc).first
      raise StateMachineError, 'Nenhuma anotação encontrada para rejeitar' unless annotation

      # Cria o registro de revisão como Rejeitado (usando o enum 1)
      Review.create!( 
        annotation: annotation,
        reviewer: reviewer,
        status: :rejected
      )

      # Permite novo envio quando a tarefa volta para o anotador.
      tile_point_set&.update!(finalized_at: nil) if respond_to?(:tile_point_set)

      # Entra na pilha de rejeitadas do anotador para retrabalho futuro.
      update!( 
        status: :rejected,
        reserved_at: nil,
        reservation_expires_at: nil
      )
    end
  end

  def self.reserve_next_rejected_for!(user)
    return nil unless user&.annotator?

    transaction do
      current_reserved = Tile.lock.where(reserver: user, status: :reserved).first
      return current_reserved if current_reserved

      next_rejected = Tile.lock
                          .where(reserver: user, status: :rejected)
                          .order(updated_at: :desc, id: :desc)
                          .first
      return nil unless next_rejected

      reservation_started_at = Time.current
      next_rejected.update!(
        status: :reserved,
        reserved_at: reservation_started_at,
        reservation_expires_at: reservation_started_at + reservation_expiration_hours.hours
      )

      next_rejected
    end
  end

  # approved -> payment_requested (annotator payment request)
  def self.request_payment_for!(annotator, min_payment_reais:)
    raise StateMachineError, 'User must be an annotator' unless annotator&.annotator?

    approved_tiles = approved_tiles_for_annotator(annotator)
    requested_total = approved_tiles.unscope(:lock).sum(:task_value).to_d
    min_payment = min_payment_reais.to_d

    if requested_total < min_payment || requested_total.zero?
      raise StateMachineError, 'Saldo a receber abaixo do valor mínimo para solicitação.'
    end

    transaction do
      updated_count = approved_tiles.update_all(status: statuses[:payment_requested], updated_at: Time.current)
      { updated_count: updated_count, requested_total: requested_total }
    end
  end

  # payment_requested -> paid (admin batch payment by annotator)
  def self.pay_requested_for!(annotator, admin)
    raise StateMachineError, 'Only admins can process payments' unless admin&.admin?
    raise StateMachineError, 'User must be an annotator' unless annotator&.annotator?

    requested_tiles = requested_tiles_for_annotator(annotator)
    requested_total = requested_tiles.unscope(:lock).sum(:task_value).to_d

    if requested_total.zero?
      raise StateMachineError, 'Nenhum valor solicitado para este annotator.'
    end

    transaction do
      updated_count = requested_tiles.update_all(status: statuses[:paid], updated_at: Time.current)
      { updated_count: updated_count, paid_total: requested_total }
    end
  end

  # approved -> paid
  def mark_as_paid!(admin)
    raise StateMachineError, 'Tile is not approved' unless approved? || payment_requested?
    raise StateMachineError, 'Only admins can mark as paid' unless admin.admin?

    min_payment = AppSetting.min_payment_reais.to_d
    tile_value = task_value.to_d
    if tile_value < min_payment
      raise StateMachineError, "Valor do tile (R$#{format('%.2f', tile_value).tr('.', ',')}) está abaixo do mínimo para pagamento (R$#{format('%.2f', min_payment).tr('.', ',')})"
    end
    
    update!(status: :paid)
  end

  # reserved -> abandoned (expiration)
  def expire_reservation!
    raise StateMachineError, 'Tile is not reserved' unless reserved?
    
    transaction do
      update!(
        status: :abandoned,
        reserver: nil,
        reserved_at: nil,
        reservation_expires_at: nil
      )
    end
  end

  # Check if reservation is expired
  def reservation_expired?
    return false unless reserved?

    if reservation_expires_at.present?
      reservation_expires_at < Time.current
    else
      reserved_at.present? && reserved_at < self.class.reservation_expiration_hours.hours.ago
    end
  end

  # Renova o vencimento da reserva com base no horário atual.
  def refresh_reservation_expiration!(user)
    raise StateMachineError, 'Tile is not reserved' unless reserved?
    raise StateMachineError, 'Only the reserver can refresh expiration' unless reserver == user

    update!(reservation_expires_at: Time.current + self.class.reservation_expiration_hours.hours)
  end

  # Class method to expire all expired tile reservations
  def self.expire_all_reservations!
    expired_reservations.find_each do |tile|
      tile.expire_reservation!
    end
  end

  private

  def exceeds_budget_after_reservation?
    budget_limit = AppSetting.budget_limit_reais.to_d
    return false unless budget_limit.positive?

    paid_total = Tile.paid.sum(:task_value).to_d
    to_pay_total = Tile.to_pay.sum(:task_value).to_d
    projected_total = paid_total + to_pay_total + task_value.to_d

    projected_total > budget_limit
  end

  def map_returned_available_to_abandoned
    return unless will_save_change_to_status?

    from_status, to_status = status_change_to_be_saved
    return unless to_status == 'available'
    return unless %w[reserved rejected].include?(from_status)

    self.status = :abandoned
  end

  def build_annotation_points(annotation, raw_points_payload)
    points = parse_zen_plot_points(raw_points_payload)

    points.each do |point|
      annotation.annotation_points.build(x: point[:x], y: point[:y])
    end
  rescue StateMachineError => e
    Rails.logger.warn("Ignorando pontos inválidos do ZenPlot para tile ##{id}: #{e.message}")
  end

  def parse_zen_plot_points(raw_points_payload)
    return [] if raw_points_payload.blank?

    payload = if raw_points_payload.is_a?(Array) || raw_points_payload.is_a?(Hash)
                raw_points_payload
              else
                JSON.parse(raw_points_payload)
              end

    raw_points = payload.is_a?(Hash) ? (payload['points'] || payload[:points]) : payload
    raise StateMachineError, 'Formato de pontos do ZenPlot inválido' unless raw_points.is_a?(Array)

    raw_points.each_with_index.map do |point, index|
      parse_zen_plot_point(point, index)
    end
  rescue JSON::ParserError
    raise StateMachineError, 'JSON de pontos do ZenPlot inválido'
  end

  def parse_zen_plot_point(point, index)
    raise StateMachineError, "Ponto ##{index + 1} do ZenPlot é inválido" unless point.is_a?(Hash)

    x = parse_coordinate(point['x'] || point[:x])
    y = parse_coordinate(point['y'] || point[:y])

    if x.nil? || y.nil?
      raise StateMachineError, "Ponto ##{index + 1} do ZenPlot precisa ter coordenadas numéricas válidas"
    end

    { x: x, y: y }
  end

  def parse_coordinate(value)
    float_value = Float(value)
    return nil unless float_value.finite?

    rounded = float_value.round
    return nil if rounded.negative?

    rounded
  rescue ArgumentError, TypeError
    nil
  end

  def user_can_reserve_only_one_image
    return if reserver.nil?
    
    other_reserved = Tile.where(reserver_id: reserver_id, status: :reserved)
                          .where.not(id: id)
                          .exists?
    
    if other_reserved
      errors.add(:base, 'User already has a reserved tile')
    end
  end

  def self.approved_tiles_for_annotator(annotator)
    Tile.lock.where(id: associated_tile_ids_for_annotator(annotator), status: :approved)
  end

  def self.requested_tiles_for_annotator(annotator)
    Tile.lock.where(id: associated_tile_ids_for_annotator(annotator), status: :payment_requested)
  end

  def self.associated_tile_ids_for_annotator(annotator)
    annotation_tile_ids = Annotation.where(user_id: annotator.id).select(:image_id)

    Tile
      .where(reserver_id: annotator.id)
      .or(Tile.where(id: annotation_tile_ids))
      .distinct
      .select(:id)
  end

  private_class_method :approved_tiles_for_annotator
  private_class_method :requested_tiles_for_annotator
  private_class_method :associated_tile_ids_for_annotator

  # Custom error class for state machine
  class StateMachineError < StandardError; end
end
