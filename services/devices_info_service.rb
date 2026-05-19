# frozen_string_literal: true

module DevicesInfoService
  module_function

  TREE = {
    title: 'Приборы учёта',
    children: [
      {
        title: 'Установка дМ',
        children: [
          {
            title: 'ВКТ-7,9',
            children: [
              {
                title: 'ВКТ-7',
                text: 'БД → Настр. ТВ1 (КМ=3; БМ=1)'
              },
              {
                title: 'ВКТ-9',
                text: <<~TEXT
                  1) Настройки → Общие → Коэф. небаланса = 1.000
                     (принимает значение от 1.000 до 1.100, где каждая сотая «0.010» = 1%)

                  2) Настройки → ТС1 → Контроль НС → Схема зимняя → НС ТС → Небал. ≤ Кнеб
                     (листая стрелками влево-вправо найти формулу (М1 + М2) / 2)
                TEXT
              }
            ]
          },
          {
            title: 'Взлёт',
            text: 'Настройки в разработке.'
          },
          {
            title: 'СПТ',
            text: 'ТВ1 → БД (АМ=2; НМ=0,00; Мк=0)'
          },
          {
            title: 'ТВ7',
            text: 'ТВ1 → контр. dM → С подст.=1; dMmax=1'
          }
        ]
      }
    ]
  }.freeze

  def node_by_path(path)
    node = TREE
    path.each do |idx|
      children = node[:children] || []
      return nil unless idx.is_a?(Integer) && idx >= 0 && idx < children.size

      node = children[idx]
    end
    node
  end

  def root_title
    TREE[:title]
  end
end
