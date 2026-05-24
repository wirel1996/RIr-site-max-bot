# frozen_string_literal: true

RSpec.describe 'Journal week-status API', type: :request do
  before { login_as }

  describe 'GET /api/journal/week-status' do
    it 'returns revision fields for a week' do
      skip 'journal not configured' unless JournalService.api_available?

      monday = Date.today - ((Date.today.wday - 1) % 7)
      start = monday.iso8601
      now = Time.now.to_i
      JournalDB.with_db do |db|
        JournalDB.upsert_cell(
          db,
          week_start: start,
          date_iso: start,
          weekday: 'Пн',
          time_slot: '8:00-9:00',
          person: 'Test User',
          value: 'x',
          sheet: '',
          color: ''
        )
      end

      get "/api/journal/week-status?start=#{start}"
      expect(last_response.status).to eq(200)
      expect(json_body['week_start']).to eq(start)
      expect(json_body['cells_revision']).to be >= now
      expect(json_body['latest_event_id']).to be_a(Integer)
    end

    it 'requires start param' do
      skip 'journal not configured' unless JournalService.api_available?

      get '/api/journal/week-status'
      expect(last_response.status).to eq(400)
    end
  end
end
