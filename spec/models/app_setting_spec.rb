require 'rails_helper'

RSpec.describe AppSetting, type: :model do
  before do
    described_class.delete_all
  end

  describe '.task_value_per_head_cents' do
    it 'returns default when record does not exist' do
      expect(described_class.task_value_per_head_cents).to eq(0)
    end

    it 'returns stored value when record exists' do
      described_class.create!(key: described_class::KEY_TASK_VALUE_PER_HEAD_CENTS, value: '35')

      expect(described_class.task_value_per_head_cents).to eq(35)
    end
  end

  describe '.task_expiration_hours' do
    it 'returns default when record does not exist' do
      expect(described_class.task_expiration_hours).to eq(48)
    end

    it 'returns stored value when record exists' do
      described_class.create!(key: described_class::KEY_TASK_EXPIRATION_HOURS, value: '12')

      expect(described_class.task_expiration_hours).to eq(12)
    end
  end

  describe '.budget_limit_reais' do
    it 'returns default when record does not exist' do
      expect(described_class.budget_limit_reais).to eq(0)
    end

    it 'falls back to legacy cents key converting to reais' do
      described_class.new(key: 'budget_limit_cents', value: '150050').save!(validate: false)

      expect(described_class.budget_limit_reais).to eq(1501)
    end

    it 'returns stored value when record exists' do
      described_class.create!(key: described_class::KEY_BUDGET_LIMIT_REAIS, value: '5000')

      expect(described_class.budget_limit_reais).to eq(5000)
    end
  end

  describe '.update_operational_settings!' do
    it 'creates or updates all settings' do
      described_class.update_operational_settings!(task_value_per_head_cents: 55, task_expiration_hours: 10, budget_limit_reais: 7500)

      expect(described_class.task_value_per_head_cents).to eq(55)
      expect(described_class.task_expiration_hours).to eq(10)
      expect(described_class.budget_limit_reais).to eq(7500)
    end

    it 'keeps existing budget limit when not provided' do
      described_class.create!(key: described_class::KEY_BUDGET_LIMIT_REAIS, value: '1234')

      described_class.update_operational_settings!(task_value_per_head_cents: 55, task_expiration_hours: 10)

      expect(described_class.budget_limit_reais).to eq(1234)
    end
  end

  describe '.task_value_for_estimated_heads' do
    before do
      described_class.create!(key: described_class::KEY_TASK_VALUE_PER_HEAD_CENTS, value: '35')
    end

    it 'returns the nearest multiple of R$5 for the computed value' do
      # 12 * R$0,35 = R$4,20 -> R$5,00
      expect(described_class.task_value_for_estimated_heads(12)).to eq(5.to_d)

      # 100 * R$0,35 = R$35,00 -> R$35,00
      expect(described_class.task_value_for_estimated_heads(100)).to eq(35.to_d)
    end

    it 'uses half-up rule on midpoint values' do
      # 50 * R$0,05 = R$2,50 -> R$5,00
      described_class.find_by(key: described_class::KEY_TASK_VALUE_PER_HEAD_CENTS).update!(value: '5')

      expect(described_class.task_value_for_estimated_heads(50)).to eq(5.to_d)
    end
  end
end
