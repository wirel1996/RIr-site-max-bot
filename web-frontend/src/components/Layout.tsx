import { Link, NavLink, Outlet, useLocation, useNavigate } from 'react-router-dom'
import { useAuth } from '../contexts/AuthContext'

const navItems = [
  { to: '/', label: 'Главная', exact: true },
  { to: '/journal', label: 'Журнал' },
  { to: '/contacts', label: 'Контакты' },
]

const serviceItems = [
  { to: '/arshin', label: 'АРШИН' },
  { to: '/metering', label: 'Приборы учета' },
  { to: '/summer-water', label: 'Вода на лето ГСПО', waterAllowed: true },
  { to: '/billing', label: 'Биллинг ГВС', billingOnly: true },
  { to: '/calculations', label: 'Расчёты' },
  { to: '/algorithms', label: 'Алгоритмы' },
  { to: '/admin', label: 'Админка', adminOnly: true },
]

const wideRoutes = ['/journal', '/summer-water']

export default function Layout() {
  const location = useLocation()
  const navigate = useNavigate()
  const { user, logout } = useAuth()
  const wide = wideRoutes.some((r) => location.pathname === r || location.pathname.startsWith(r + '/'))
  const containerClass = wide ? 'w-full' : 'max-w-6xl mx-auto'

  const visibleNavItems = navItems.filter(() => {
    if (user?.role === 'water_payment') return false
    return true
  })

  const visibleServiceItems = serviceItems.filter((item) => {
    if (user?.role === 'water_payment') return item.waterAllowed === true
    if (item.adminOnly && user?.role !== 'admin') return false
    if (item.billingOnly && user?.role === 'limited') return false
    return true
  })

  const servicesActive = visibleServiceItems.some((item) => (
    location.pathname === item.to || location.pathname.startsWith(item.to + '/')
  ))

  async function onLogout() {
    await logout()
    navigate('/login', { replace: true })
  }

  return (
    <div className="min-h-screen flex flex-col bg-gray-50 text-gray-900">
      <header className="bg-white border-b sticky top-0 z-50">
        <div className="max-w-6xl mx-auto px-4 py-3 flex items-center gap-6 flex-wrap">
          <Link reloadDocument to="/" className="font-bold text-lg whitespace-nowrap">
            🛠 Сервис ОКЭ
          </Link>
          <nav className="flex flex-wrap items-center gap-x-4 gap-y-1 text-sm">
            {visibleNavItems.map((item) => (
              <NavLink
                key={item.to}
                to={item.to}
                reloadDocument
                end={item.exact}
                className={({ isActive }) =>
                  isActive
                    ? 'text-blue-700 font-medium'
                    : 'text-gray-600 hover:text-gray-900'
                }
              >
                {item.label}
              </NavLink>
            ))}
            {visibleServiceItems.length > 0 && (
              <div className="group relative">
                <button
                  type="button"
                  className={servicesActive ? 'font-medium text-blue-700' : 'text-gray-600 hover:text-gray-900'}
                >
                  Сервисы
                </button>
                <div className="invisible absolute left-0 top-full z-[60] min-w-56 rounded border bg-white py-1 shadow-lg opacity-0 transition group-hover:visible group-hover:opacity-100 group-focus-within:visible group-focus-within:opacity-100">
                  {visibleServiceItems.map((item) => (
                    <NavLink
                      key={item.to}
                      to={item.to}
                      reloadDocument
                      className={({ isActive }) =>
                        `block px-3 py-2 text-sm ${isActive ? 'bg-blue-50 font-medium text-blue-700' : 'text-gray-700 hover:bg-gray-50'}`
                      }
                    >
                      {item.label}
                    </NavLink>
                  ))}
                </div>
              </div>
            )}
          </nav>
          {user && (
            <div className="ml-auto flex items-center gap-3 text-sm">
              <Link reloadDocument to="/profile" className="text-gray-700 hover:text-gray-900 underline-offset-2 hover:underline">{user.name}</Link>
              <button
                type="button"
                onClick={onLogout}
                className="text-gray-500 hover:text-gray-900 underline-offset-2 hover:underline"
              >
                Выйти
              </button>
            </div>
          )}
        </div>
      </header>

      <main className={`flex-1 w-full ${containerClass} px-3 sm:px-4 py-4 sm:py-6`}>
        <Outlet />
      </main>

      {!wide && (
        <footer className="max-w-6xl mx-auto px-4 py-4 text-xs text-gray-400 text-center">
          .
        </footer>
      )}
    </div>
  )
}
