import { useQuery } from '@tanstack/react-query'
import { Link, useSearchParams } from 'react-router-dom'
import { contactsApi } from '../../api/contacts'
import { categoryLabel, contactAddress, contactPhone, contactTitle } from './contactDisplay'

export default function ContactsSearch() {
  const [searchParams] = useSearchParams()
  const query = searchParams.get('q')?.trim() ?? ''

  const { data, isLoading } = useQuery({
    queryKey: ['contacts', 'search', query],
    queryFn: () => contactsApi.search(query),
    enabled: query.length >= 2,
  })

  return (
    <div className="space-y-4">
      <nav className="text-sm">
        <Link to="/contacts" className="text-blue-600 hover:underline">
          ← Все категории
        </Link>
      </nav>

      <h1 className="text-2xl font-bold">Поиск: "{query}"</h1>

      {query.length < 2 && <p>Введите минимум 2 символа для поиска.</p>}
      {isLoading && <div className="text-gray-500">Поиск...</div>}

      {data && data.records.length === 0 && <p>Ничего не найдено.</p>}

      {data && data.records.length > 0 && (
        <>
          <p className="text-sm text-gray-600">Найдено: {data.records.length}</p>
          <div className="bg-white rounded-lg shadow overflow-x-auto">
            <table className="min-w-full text-sm">
              <thead className="bg-gray-100">
                <tr>
                  <th className="px-3 py-2 text-left w-12">#</th>
                  <th className="px-3 py-2 text-left">Категория</th>
                  <th className="px-3 py-2 text-left">Наименование</th>
                  <th className="px-3 py-2 text-left">Адрес</th>
                  <th className="px-3 py-2 text-left">Телефон</th>
                  <th className="px-3 py-2 w-12"></th>
                </tr>
              </thead>
              <tbody>
                {data.records.map((r, i) => (
                  <tr key={r.id} className="border-t hover:bg-gray-50">
                    <td className="px-3 py-2 text-gray-500">{i + 1}</td>
                    <td className="px-3 py-2 text-xs">
                      <span className="bg-gray-200 rounded px-1.5 py-0.5">{categoryLabel(r.category)}</span>
                    </td>
                    <td className="px-3 py-2">
                      <Link
                        to={`/contacts/${r.id}`}
                        state={{ from: `/contacts/search?q=${encodeURIComponent(query)}` }}
                        className="text-blue-700 hover:underline"
                      >
                        {contactTitle(r)}
                      </Link>
                    </td>
                    <td className="px-3 py-2 text-gray-700">{contactAddress(r) || <span className="text-gray-400">—</span>}</td>
                    <td className="px-3 py-2">
                      {contactPhone(r) ? (
                        <a href={`tel:${contactPhone(r)}`} className="text-blue-600 hover:underline">
                          {contactPhone(r)}
                        </a>
                      ) : (
                        <span className="text-gray-400">—</span>
                      )}
                    </td>
                    <td className="px-3 py-2 text-right">
                      <Link to={`/contacts/${r.id}`} className="text-blue-600">
                        →
                      </Link>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}
    </div>
  )
}
