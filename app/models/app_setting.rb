class AppSetting < ApplicationRecord
  KEY_TASK_VALUE_PER_HEAD_CENTS = 'task_value_per_head_cents'.freeze
  KEY_TASK_EXPIRATION_HOURS = 'task_expiration_hours'.freeze
  KEY_BUDGET_LIMIT_REAIS = 'budget_limit_reais'.freeze
  KEY_MIN_PAYMENT_REAIS = 'min_payment_reais'.freeze
  KEY_ZENITH_TOLERANCE_DEGREES = 'zenith_tolerance_degrees'.freeze
  LEGACY_KEY_BUDGET_LIMIT_CENTS = 'budget_limit_cents'.freeze

  DEFAULTS = {
    KEY_TASK_VALUE_PER_HEAD_CENTS => 0,
    KEY_TASK_EXPIRATION_HOURS => 48,
    KEY_BUDGET_LIMIT_REAIS => 0,
    KEY_MIN_PAYMENT_REAIS => 0,
    KEY_ZENITH_TOLERANCE_DEGREES => 10
  }.freeze

  validates :key, presence: true, uniqueness: true
  validates :value, presence: true
  validate :validate_value_format, if: :operational_key?
  # Chaves para OAuth
  KEY_OAUTH_CONSUMER_KEY = 'oauth_consumer_key'.freeze
  KEY_OAUTH_CONSUMER_SECRET = 'oauth_consumer_secret'.freeze
  KEY_OAUTH_CALLBACK_ID = 'oauth_callback_id'.freeze

  def self.oauth_consumer_key
    read_string(KEY_OAUTH_CONSUMER_KEY)
  end

  def self.oauth_consumer_secret
    read_string(KEY_OAUTH_CONSUMER_SECRET)
  end

  def self.oauth_callback_id
    read_string(KEY_OAUTH_CALLBACK_ID)
  end

  def self.update_oauth_settings!(consumer_key:, consumer_secret:, callback_id:)
    upsert_string!(KEY_OAUTH_CONSUMER_KEY, consumer_key)
    upsert_string!(KEY_OAUTH_CONSUMER_SECRET, consumer_secret)
    upsert_string!(KEY_OAUTH_CALLBACK_ID, callback_id)
  end
  def self.read_string(key)
    find_by(key: key)&.value.to_s
  end

  def self.upsert_string!(key, value)
    record = find_or_initialize_by(key: key)
    record.value = value.to_s
    record.save!
    value
  end
  def operational_key?
    DEFAULTS.keys.include?(key)
  end

  class << self
    def task_value_per_head_cents
      read_integer(KEY_TASK_VALUE_PER_HEAD_CENTS)
    end

    def task_expiration_hours
      read_integer(KEY_TASK_EXPIRATION_HOURS)
    end

    def budget_limit_reais
      explicit_reais = read_integer_or_nil(KEY_BUDGET_LIMIT_REAIS)
      return explicit_reais unless explicit_reais.nil?

      legacy_cents = read_integer_or_nil(LEGACY_KEY_BUDGET_LIMIT_CENTS)
      return DEFAULTS.fetch(KEY_BUDGET_LIMIT_REAIS) if legacy_cents.nil?

      (legacy_cents.to_d / 100).round(0, BigDecimal::ROUND_HALF_UP).to_i
    end

    def min_payment_reais
      read_integer(KEY_MIN_PAYMENT_REAIS)
    end

    def zenith_tolerance_degrees
      read_integer(KEY_ZENITH_TOLERANCE_DEGREES)
    end

    def update_operational_settings!(task_value_per_head_cents:, task_expiration_hours:, budget_limit_reais: nil, min_payment_reais: nil, zenith_tolerance_degrees: nil)
      upsert_integer!(KEY_TASK_VALUE_PER_HEAD_CENTS, task_value_per_head_cents)
      upsert_integer!(KEY_TASK_EXPIRATION_HOURS, task_expiration_hours)
      upsert_integer!(KEY_BUDGET_LIMIT_REAIS, budget_limit_reais.nil? ? self.budget_limit_reais : budget_limit_reais)
      upsert_integer!(KEY_MIN_PAYMENT_REAIS, min_payment_reais.nil? ? self.min_payment_reais : min_payment_reais)
      upsert_integer!(KEY_ZENITH_TOLERANCE_DEGREES, zenith_tolerance_degrees.nil? ? self.zenith_tolerance_degrees : zenith_tolerance_degrees)
    end

    # Calcula o valor final do tile em reais e arredonda para o múltiplo de R$ 5 mais próximo.
    def task_value_for_estimated_heads(head_count)
      raw_value = (head_count.to_i * task_value_per_head_cents).to_d / 100
      rounded_steps = (raw_value / 5).round(0, BigDecimal::ROUND_HALF_UP)

      (rounded_steps * 5).to_d.round(2)
    end

    def ensure_defaults!
      DEFAULTS.each do |key, default_value|
        next if exists?(key: key)

        create!(key: key, value: default_value.to_s)
      end
    end

    private

    def read_integer(key)
      default_value = DEFAULTS.fetch(key)
      value = find_by(key: key)&.value
      parsed = Integer(value.to_s, exception: false)
      parsed.nil? ? default_value : parsed
    end

    def read_integer_or_nil(key)
      value = find_by(key: key)&.value
      Integer(value.to_s, exception: false)
    end

    def upsert_integer!(key, raw_value)
      integer_value = Integer(raw_value)
      record = find_or_initialize_by(key: key)
      record.value = integer_value.to_s
      record.save!
      integer_value
    end
  end

  private

  def validate_value_format
    integer_value = Integer(value.to_s, exception: false)
    if integer_value.nil?
      errors.add(:value, 'deve ser um número inteiro')
      return
    end

    if key == KEY_TASK_VALUE_PER_HEAD_CENTS && integer_value.negative?
      errors.add(:value, 'deve ser maior ou igual a zero')
    end

    if key == KEY_TASK_EXPIRATION_HOURS && integer_value <= 0
      errors.add(:value, 'deve ser maior que zero')
    end

    if key == KEY_BUDGET_LIMIT_REAIS && integer_value.negative?
      errors.add(:value, 'deve ser maior ou igual a zero')
    end

    if key == KEY_MIN_PAYMENT_REAIS && integer_value.negative?
      errors.add(:value, 'deve ser maior ou igual a zero')
    end

    if key == KEY_ZENITH_TOLERANCE_DEGREES && !integer_value.between?(0, 90)
      errors.add(:value, 'deve estar entre 0 e 90 graus')
    end
  end
end