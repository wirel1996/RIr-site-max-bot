export const homeRu = {
  title: 'Главная',
  subtitle: 'Основные разделы и сервисы ОКЭ.',
  sectionsTitle: 'Разделы',
  servicesTitle: 'Сервисы',
  primaryTiles: [
    { to: '/journal', title: 'Электронный журнал', desc: 'Задачи и примечания по адресам' },
    { to: '/contacts', title: 'Контакты потребителей', desc: 'ТСЖ, ГСПО, ФЛ, ЮЛ, Иглаково, встроенные' },
  ],
  serviceTiles: [
    { to: '/arshin', title: 'АРШИН', desc: 'Поверка приборов и проверки по АРШИН' },
    { to: '/metering', title: 'Приборы учета', desc: 'Карточки УУТЭ, поверки и связи с контактами' },
    { to: '/summer-water', title: 'Вода на лето ГСПО', desc: 'Реестр заявок, оплата, подключение и водоснабжение', waterAllowed: true },
    { to: '/billing', title: 'ГВС биллинг', desc: 'Потребители, показания и даты ввода', billingOnly: true },
    { to: '/calculations', title: 'Расчеты', desc: 'Тепловая нагрузка и дроссельная диафрагма' },
    { to: '/algorithms', title: 'Алгоритмы', desc: 'Рабочие процедуры и справочная информация' },
    { to: '/admin', title: 'Админка', desc: 'Пользователи, роли и уведомления MAX', adminOnly: true },
  ],
} as const
