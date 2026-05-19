import type { Contact, ContactCategory, ContactUpdatePayload } from '../../api/contacts'

export type EditableContactField = [keyof ContactUpdatePayload, string, 'input' | 'textarea' | 'yes_no']

const clean = (value: string | null | undefined) => value?.trim() || ''

export const CATEGORY_LABEL: Record<ContactCategory, string> = {
  uk_tsj: 'УК и ТСЖ',
  gspo: 'ГСПО',
  phys: 'Прочие ФЛ',
  legal: 'Прочие ЮЛ',
  budget: 'Бюджет',
  iglakovo: 'Иглаково',
  embedded: 'Встроенные помещения',
  bu2: 'БУ-2',
}

export function categoryLabel(category: ContactCategory): string {
  return CATEGORY_LABEL[category] || category
}

export function contactTitle(record: Contact): string {
  if (record.category === 'phys') return clean(record.consumer) || `#${record.id}`
  return clean(record.name) || clean(record.consumer) || `#${record.id}`
}

export function contactAddress(record: Contact): string {
  return clean(record.address)
}

export function contactPhone(record: Contact): string {
  return clean(record.phone)
}

export function editableFieldsForCategory(category: ContactCategory): EditableContactField[] {
  switch (category) {
    case 'uk_tsj':
      return [
        ['name', 'Наименование', 'input'],
        ['address', 'Адрес', 'input'],
        ['manager', 'Руководитель', 'input'],
        ['phone', 'Телефон', 'input'],
        ['email', 'Email', 'input'],
        ['postal_address', 'Почтовый адрес', 'input'],
        ['identifier', 'Идентификатор', 'input'],
      ]
    case 'gspo':
      return [
        ['connection_point', 'Точка присоединения', 'input'],
        ['name', 'Наименование', 'input'],
        ['address', 'Адрес', 'input'],
        ['consumer', 'Потребитель', 'input'],
        ['phone', 'Телефон', 'input'],
        ['email', 'Email', 'input'],
        ['postal_address', 'Почтовый адрес', 'input'],
        ['metering_presence', 'Наличие ПУ', 'yes_no'],
        ['disconnected', 'Отключено', 'yes_no'],
        ['identifier', 'Идентификатор', 'input'],
      ]
    case 'phys':
      return [
        ['consumer', 'Потребитель', 'input'],
        ['address', 'Адрес', 'input'],
        ['manager', 'Ф.И.О. руководителя', 'input'],
        ['phone', 'Телефон', 'input'],
        ['phone_alt', 'Доп. телефон', 'input'],
        ['email', 'Email', 'input'],
        ['postal_address', 'Почтовый адрес', 'input'],
        ['metering_presence', 'Наличие ПУ', 'yes_no'],
        ['identifier', 'Идентификатор', 'input'],
        ['notes', 'Ответственные лица', 'textarea'],
      ]
    case 'legal':
      return [
        ['name', 'Наименование', 'input'],
        ['address', 'Место нахождения', 'input'],
        ['manager', 'Ф.И.О. руководителя', 'input'],
        ['phone', 'Телефон', 'input'],
        ['email', 'Email', 'input'],
        ['postal_address', 'Почтовый адрес', 'input'],
        ['metering_presence', 'Наличие ПУ', 'yes_no'],
        ['identifier', 'Идентификатор', 'input'],
        ['notes', 'Ответственные лица', 'textarea'],
      ]
    case 'budget':
      return [
        ['name', 'Наименование', 'input'],
        ['address', 'Адрес', 'input'],
        ['manager', 'Руководитель', 'input'],
        ['phone', 'Телефон', 'input'],
        ['email', 'Email', 'input'],
        ['postal_address', 'Почтовый адрес', 'input'],
        ['metering_presence', 'Наличие ПУ', 'yes_no'],
        ['identifier', 'Идентификатор', 'input'],
        ['notes', 'Ответственные лица', 'textarea'],
      ]
    case 'iglakovo':
      return [
        ['name', 'Название', 'input'],
        ['manager', 'Ф.И.О. руководителя', 'input'],
        ['address', 'Адрес', 'input'],
        ['phone', 'Телефон для уведомлений', 'input'],
        ['email', 'Email', 'input'],
        ['postal_address', 'Почтовый адрес', 'input'],
        ['metering_presence', 'Наличие ПУ', 'yes_no'],
        ['identifier', 'Идентификатор', 'input'],
        ['notes', 'Ответственные лица', 'textarea'],
      ]
    case 'embedded':
      return [
        ['name', 'Наименование', 'input'],
        ['manager', 'Ф.И.О. руководителя', 'input'],
        ['address', 'Адрес помещения', 'input'],
        ['phone', 'Телефон', 'input'],
        ['email', 'Email', 'input'],
        ['postal_address', 'Почтовый адрес', 'input'],
        ['identifier', 'Идентификатор', 'input'],
        ['notes', 'Ответственные лица', 'textarea'],
      ]
    case 'bu2':
      return [
        ['name', 'Наименование', 'input'],
        ['manager', 'Ф.И.О. руководителя', 'input'],
        ['address', 'Адрес', 'input'],
        ['notes', 'Ответственные лица', 'textarea'],
        ['metering_presence', 'Наличие ПУ', 'yes_no'],
        ['postal_address', 'Почтовый адрес', 'input'],
        ['identifier', 'Идентификатор', 'input'],
      ]
    default:
      return [
        ['name', 'Наименование', 'input'],
        ['consumer', 'Потребитель', 'input'],
        ['manager', 'Руководитель', 'input'],
        ['address', 'Адрес', 'input'],
        ['phone', 'Телефон', 'input'],
        ['phone_alt', 'Доп. телефон', 'input'],
        ['email', 'Email', 'input'],
        ['postal_address', 'Почтовый адрес', 'input'],
        ['identifier', 'Идентификатор', 'input'],
        ['notes', 'Примечание', 'textarea'],
      ]
  }
}

