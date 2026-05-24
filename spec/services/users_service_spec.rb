# frozen_string_literal: true

require_relative '../../services/users_service'

RSpec.describe UsersService do
  describe 'switch act authors' do
    it 'includes users with position' do
      authors = described_class.switch_act_authors
      expect(authors.map { |a| a[:login] }).to include('rspec_author')
    end

    it 'resolves author by login' do
      author = described_class.resolve_switch_act_author('rspec_author')
      expect(author[:position]).to eq('Инженер')
    end
  end
end
