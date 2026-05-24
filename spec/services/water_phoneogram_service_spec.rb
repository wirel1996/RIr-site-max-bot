# frozen_string_literal: true

require_relative '../../services/water_phoneogram_service'

RSpec.describe WaterPhoneogramService do
  describe 'export history' do
    it 'records and reads last export' do
      described_class.record_export!(
        payment_from: '2026-04-01',
        payment_to: '2026-05-15',
        phoneogram_number: '7',
        document_date: '2026-05-20'
      )
      last = described_class.last_export
      expect(last[:phoneogram_number]).to eq('7')
      expect(last[:payment_to]).to eq('2026-05-15')
    end
  end
end
