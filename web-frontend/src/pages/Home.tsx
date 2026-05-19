import { Link } from 'react-router-dom'
import { useAuth } from '../contexts/AuthContext'

const primaryTiles = [
  {
    to: '/journal',
    title: 'Электронный журнал',
    desc: 'Задания и замечания по адресам',
  },
  {
    to: '/contacts',
    title: 'Контакты потребителей',
    desc: 'УК, ГСПО, ФЛ, ЮЛ, Иглаково, встроенные помещения',
  },
]

const serviceTiles = [
  {
    to: '/arshin',
    title: 'АРШИН',
    desc: 'Поверка приборов, PDF и отправка в Я.Диск',
  },
  {
    to: '/metering',
    title: 'Приборы учета',
    desc: 'Карточки УУТЭ, поверки и связи с контактами',
  },
  {
    to: '/summer-water',
    title: 'Вода на лето ГСПО',
    desc: 'Реестр заявлений, оплата, подключение и подача воды',
    waterAllowed: true,
  },
  {
    to: '/billing',
    title: 'Биллинг ГВС',
    desc: 'Потребители, показания и даты ввода',
    billingOnly: true,
  },
  {
    to: '/calculations',
    title: 'Расчёты',
    desc: 'Тепловая нагрузка и дроссельная диафрагма',
  },
  {
    to: '/algorithms',
    title: 'Алгоритмы',
    desc: 'Порядки работы и справочная информация',
  },
  {
    to: '/admin',
    title: 'Админка',
    desc: 'Пользователи, роли и уведомления MAX',
    adminOnly: true,
  },
]

type Tile = typeof serviceTiles[number]

function TileLink({ tile }: { tile: Tile }) {
  return (
    <Link
      to={tile.to}
      className="block rounded-lg border border-transparent bg-white p-4 shadow transition hover:border-blue-300 hover:shadow-md"
    >
      <div className="font-semibold text-base">{tile.title}</div>
      <div className="mt-1 text-sm text-gray-500">{tile.desc}</div>
    </Link>
  )
}

export default function Home() {
  const { user } = useAuth()
  const waterOnly = user?.role === 'water_payment'

  const visiblePrimaryTiles = waterOnly ? [] : primaryTiles
  const visibleServiceTiles = serviceTiles.filter((tile) => {
    if (waterOnly) return tile.waterAllowed === true
    if (tile.adminOnly && user?.role !== 'admin') return false
    if (tile.billingOnly && user?.role === 'limited') return false
    return true
  })

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold">Главная</h1>
        <p className="mt-1 text-sm text-gray-600">Основные разделы и сервисы ОКЭ.</p>
      </div>

      {visiblePrimaryTiles.length > 0 && (
        <section>
          <h2 className="mb-3 text-lg font-semibold">Разделы</h2>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {visiblePrimaryTiles.map((tile) => (
              <TileLink key={tile.to} tile={tile} />
            ))}
          </div>
        </section>
      )}

      {visibleServiceTiles.length > 0 && (
        <section>
          <h2 className="mb-3 text-lg font-semibold">Сервисы</h2>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {visibleServiceTiles.map((tile) => (
              <TileLink key={tile.to} tile={tile} />
            ))}
          </div>
        </section>
      )}
    </div>
  )
}
