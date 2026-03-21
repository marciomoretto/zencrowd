require 'rails_helper'

RSpec.describe AppSetting, type: :model do
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

  describe '.update_operational_settings!' do
    it 'creates or updates both settings' do
      described_class.update_operational_settings!(task_value_per_head_cents: 55, task_expiration_hours: 10)

      expect(described_class.task_value_per_head_cents).to eq(55)
      expect(described_class.task_expiration_hours).to eq(10)
    end
  end
end
