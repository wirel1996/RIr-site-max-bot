import type { ArshinForm } from '../../api/arshin'

export const arshinRu = {
  title: 'АРШИН — поверка приборов',
  fields: [
    { key: 'org_title', label: 'Поверитель (организация)' },
    { key: 'year', label: 'Год поверки' },
    { key: 'mi_number', label: 'Номер прибора' },
    { key: 'mit_notation', label: 'Тип/обозн. прибора' },
  ] as Array<{ key: keyof ArshinForm; label: string }>,
  anyOrg: '— любая —',
  find: 'Найти прибор',
  searching: 'Ищу...',
  clear: 'Очистить',
  downloadPrefix: 'Поверка',
  pdfError: 'Не удалось получить PDF',
  verification: 'Поверка',
  until: 'до',
} as const
