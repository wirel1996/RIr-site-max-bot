# frozen_string_literal: true

require_relative '../algorithms/ipu_algorithm'
require_relative '../algorithms/disable_algorithm'
require_relative '../algorithms/uute_algorithm'

module AlgorithmsService
  module_function

  ALGORITHMS = [
    AlgorithmsData::IPU,
    AlgorithmsData::DISABLE,
    AlgorithmsData::UUTE
  ].each_with_object({}) do |item, acc|
    acc[item.fetch(:key)] = {
      text: item.fetch(:text),
      steps: item.fetch(:steps)
    }
  end.freeze

  ALGORITHMS_LIST = ALGORITHMS.map do |key, data|
    { text: data.fetch(:text), payload: "algo:#{key}" }
  end.freeze

  def algorithms_menu_keyboard
    rows = ALGORITHMS_LIST.map { |item| [item] }
    rows << [{ text: '📚 Приборы учёта', payload: 'devices:root' }]
    rows << [{ text: '📞 Контакты потребителей', payload: 'contacts:menu' }]
    rows << [{ text: 'Назад', payload: 'Назад' }, { text: '🏠 Главное меню', payload: 'Главное меню' }]
    ArshinService.max_inline_keyboard(rows)
  end

  def algorithm_steps(key)
    ALGORITHMS.dig(key.to_s, :steps) || []
  end

  def algorithm_exists?(key)
    ALGORITHMS.key?(key.to_s)
  end

  def algorithm_step_keyboard(key, step_index)
    steps = algorithm_steps(key)
    if steps.empty?
      return ArshinService.max_inline_keyboard([
        [{ text: '📑 К списку алгоритмов', payload: 'algo:menu' }],
        [{ text: '🏠 Главное меню', payload: 'Главное меню' }]
      ])
    end

    buttons = []
    buttons << { text: '← Назад', payload: "algo:#{key}:prev" } if step_index > 0
    buttons << { text: 'Далее →', payload: "algo:#{key}:next" } if step_index < steps.size - 1
    ArshinService.max_inline_keyboard([
      buttons,
      [{ text: '📑 К списку алгоритмов', payload: 'algo:menu' }],
      [{ text: '🏠 Главное меню', payload: 'Главное меню' }]
    ].reject(&:empty?))
  end

  def algorithm_step_text(key, step_index)
    steps = algorithm_steps(key)
    return 'Алгоритм не найден.' if steps.empty?

    idx = [[step_index.to_i, 0].max, steps.size - 1].min
    step = steps[idx]
    "#{step[:title]}\n\n#{step[:text].strip}"
  end
end
