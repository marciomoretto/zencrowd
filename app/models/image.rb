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
      .where('reserved_at < ?', RESERVATION_EXPIRATION_HOURS.hours.ago)
  }

  # State transitions
  # available -> reserved
  def reserve!(user)
    raise StateMachineError, 'Image is not available' unless available?
    raise StateMachineError, 'User must be an annotator' unless user.annotator?
    
    # Check if user already has a reserved image
    if Image.where(reserver: user, status: :reserved).exists?
      raise StateMachineError, 'User already has a reserved image'
    end

    transaction do
      update!(
        status: :reserved,
        reserver: user,
        reserved_at: Time.current
      )
    end
  end

  # reserved -> submitted
  def submit!(user, projeto_tar, dados_csv, config_json = nil)
    raise StateMachineError, 'Image is not reserved' unless reserved?
    raise StateMachineError, 'Only the reserver can submit' unless reserver == user
    raise StateMachineError, 'Arquivos projeto_tar e dados_csv são obrigatórios' if projeto_tar.blank? || dados_csv.blank?

    transaction do
      # Cria a anotação e anexa os arquivos
      annotation = annotations.build(user: user, submitted_at: Time.current)
      annotation.projeto_tar.attach(projeto_tar)
      annotation.dados_csv.attach(dados_csv)
      annotation.config_json.attach(config_json) if config_json.present?

      unless annotation.save
        raise StateMachineError, "Erro ao salvar anotação: #{annotation.errors.full_messages.join(', ')}"
      end

      # Atualiza o status da imagem
      update!(status: :submitted)
    end
  end

  # submitted -> in_review
  def start_review!(reviewer)
    raise StateMachineError, 'Image is not submitted' unless submitted?
    raise StateMachineError, 'User must be a reviewer' unless reviewer.reviewer?
    
    update!(status: :in_review)
  end

 # in_review -> approved
  def approve!(reviewer)
    raise StateMachineError, 'Image is not in review' unless in_review?
    raise StateMachineError, 'User must be a reviewer' unless reviewer.reviewer?
    
    transaction do
      # Encontra a última anotação feita (a que está sendo revisada)
      annotation = annotations.order(created_at: :desc).first
      raise StateMachineError, 'Nenhuma anotação encontrada para aprovar' unless annotation

      # Cria o registro de revisão como Aprovado (usando o enum 0)
      Review.create!(
        annotation: annotation,
        reviewer: reviewer,
        status: :approved
      )
      
      # Sela a imagem
      update!(status: :approved)
    end
  end

  # in_review -> rejected
  def reject!(reviewer)
      puts "DEBUG: Entrou no método reject! do model para imagem ##{id} (status: #{status})"
    raise StateMachineError, 'Image is not in review' unless in_review?
    raise StateMachineError, 'User must be a reviewer' unless reviewer.reviewer?
    
    transaction do
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
        reserved_at: Time.current
      )
    end
  end

  # approved -> paid
  def mark_as_paid!(admin)
    raise StateMachineError, 'Image is not approved' unless approved?
    raise StateMachineError, 'Only admins can mark as paid' unless admin.admin?
    
    update!(status: :paid)
  end

  # reserved -> available (expiration)
  def expire_reservation!
    raise StateMachineError, 'Image is not reserved' unless reserved?
    
    transaction do
      update!(
        status: :available,
        reserver: nil,
        reserved_at: nil
      )
    end
  end

  # Check if reservation is expired
  def reservation_expired?
    reserved? && reserved_at.present? && reserved_at < RESERVATION_EXPIRATION_HOURS.hours.ago
  end

  # Class method to expire all expired reservations
  def self.expire_all_reservations!
    expired_reservations.find_each do |image|
      image.expire_reservation!
    end
  end

  private

  def user_can_reserve_only_one_image
    return if reserver.nil?
    
    other_reserved = Image.where(reserver_id: reserver_id, status: :reserved)
                          .where.not(id: id)
                          .exists?
    
    if other_reserved
      errors.add(:base, 'User already has a reserved image')
    end
  end

  # Custom error class for state machine
  class StateMachineError < StandardError; end
end
