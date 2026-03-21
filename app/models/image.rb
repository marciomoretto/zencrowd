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
    paid: 6
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

  # Scopes
  scope :expired_reservations, -> {
    where(status: :reserved)
      .where(
        'reservation_expires_at < ? OR (reservation_expires_at IS NULL AND reserved_at < ?)',
        Time.current,
        reservation_expiration_hours.hours.ago
      )
  }

  def self.reservation_expiration_hours
    AppSetting.task_expiration_hours
  rescue StandardError
    RESERVATION_EXPIRATION_HOURS
  end

  # State transitions
  # available -> reserved
  def reserve!(user)
    raise StateMachineError, 'Tile is not available' unless available?
    raise StateMachineError, 'User must be an annotator' unless user.annotator?
    
    # Check if user already has a reserved tile
    if Tile.where(reserver: user, status: :reserved).exists?
      raise StateMachineError, 'User already has a reserved tile'
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

  # reserved -> available (annotator gives up task)
  def give_up!(user)
    raise StateMachineError, 'Tile is not reserved' unless reserved?
    raise StateMachineError, 'Only the reserver can give up this tile' unless reserver == user

    transaction do
      update!(
        status: :available,
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

      # Volta para reservado, mantendo o reserver e atualizando reserved_at
      update!( 
        status: :reserved,
        reserved_at: Time.current,
        reservation_expires_at: Time.current + self.class.reservation_expiration_hours.hours
      )
    end
  end

  # approved -> paid
  def mark_as_paid!(admin)
    raise StateMachineError, 'Tile is not approved' unless approved?
    raise StateMachineError, 'Only admins can mark as paid' unless admin.admin?
    
    update!(status: :paid)
  end

  # reserved -> available (expiration)
  def expire_reservation!
    raise StateMachineError, 'Tile is not reserved' unless reserved?
    
    transaction do
      update!(
        status: :available,
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

  # Custom error class for state machine
  class StateMachineError < StandardError; end
end
