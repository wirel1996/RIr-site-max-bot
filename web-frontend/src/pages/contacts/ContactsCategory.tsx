import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useState, type FormEvent } from 'react'
import { Link, useNavigate, useParams, useSearchParams } from 'react-router-dom'
import { contactsApi, type ContactUpdatePayload } from '../../api/contacts'
import { categoryLabel, contactAddress, contactPhone, contactTitle, editableFieldsForCategory } from './contactDisplay'

export default function ContactsCategory() {
  const { category } = useParams<{ category: string }>()
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const [searchParams, setSearchParams] = useSearchParams()
  const [filter, setFilter] = useState('')
  const [isAdding, setIsAdding] = useState(false)
  const [form, setForm] = useState<ContactUpdatePayload>({})
  const page = Number(searchParams.get('page') ?? 0)

  const { data, isLoading, error } = useQuery({
    queryKey: ['contacts', 'list', category, page, filter.trim()],
    queryFn: () => contactsApi.list(category!, page, filter),
    enabled: !!category,
    placeholderData: (previousData) => previousData,
  })

  const createMutation = useMutation({
    mutationFn: (payload: ContactUpdatePayload) => contactsApi.create(category!, payload),
    onSuccess: (record) => {
      queryClient.invalidateQueries({ queryKey: ['contacts'] })
      setForm({})
      setIsAdding(false)
      navigate(`/contacts/${record.id}`, {
        state: { from: `/contacts/category/${category}?page=${page}` },
      })
    },
  })

  if (!category) {
    return (
      <div>
        Категория не указана. <Link to="/contacts" className="text-blue-600">К списку</Link>
      </div>
    )
  }

  if (isLoading) return <div className="text-gray-500">Загрузка...</div>
  if (error || !data) return <div className="text-red-700">Ошибка загрузки</div>

  const pageCount = Math.max(Math.ceil(data.total / data.page_size), 1)
  const startIdx = page * data.page_size
  const normalizedFilter = filter.trim().toLowerCase()
  const records = data.records
  const editableFields = editableFieldsForCategory(category)
  const showManager = category === 'phys' || category === 'legal' || category === 'bu2'
  const showResponsible = category === 'phys' || category === 'legal' || category === 'bu2'

  const onCreate = (e: FormEvent) => {
    e.preventDefault()
    createMutation.mutate(form)
  }

  return (
    <div className="space-y-4">
      <nav className="text-sm">
        <Link to="/contacts" className="text-blue-600 hover:underline">
          ← Все категории
        </Link>
      </nav>

      <div className="flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h1 className="text-2xl font-bold">
            {data.label || categoryLabel(category)}
          </h1>
          <p className="text-sm text-gray-600">
            {normalizedFilter ? `Найдено: ${data.total}` : `Всего записей: ${data.total}`}
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          <button
            type="button"
            onClick={() => setIsAdding((value) => !value)}
            className="inline-flex items-center justify-center rounded bg-blue-600 px-3 py-1.5 text-sm text-white hover:bg-blue-700"
          >
            {isAdding ? 'Отменить добавление' : 'Добавить контакт'}
          </button>
          <a
            href={`/api/contacts/category/${category}/export`}
            className="inline-flex items-center justify-center rounded border bg-white px-3 py-1.5 text-sm text-gray-700 hover:bg-gray-100"
          >
            Скачать Excel
          </a>
        </div>
      </div>

      {isAdding && (
        <form onSubmit={onCreate} className="space-y-4 rounded-lg bg-white p-4 shadow">
          <h2 className="font-semibold">Новый контакт</h2>
          {editableFields.map(([key, label, control]) => (
            <label key={key} className="block">
              <span className="mb-1 block text-sm font-medium text-gray-600">{label}</span>
              {control === 'textarea' ? (
                <textarea
                  value={(form[key] ?? '') as string}
                  onChange={(e) => setForm((current) => ({ ...current, [key]: e.target.value }))}
                  rows={4}
                  className="w-full rounded border px-3 py-2"
                />
              ) : control === 'yes_no' ? (
                <select
                  value={(form[key] ?? '') as string}
                  onChange={(e) => setForm((current) => ({ ...current, [key]: e.target.value }))}
                  className="w-full rounded border px-3 py-2"
                >
                  <option value="">Выберите...</option>
                  <option value="Да">Да</option>
                  <option value="Нет">Нет</option>
                </select>
              ) : (
                <input
                  value={(form[key] ?? '') as string}
                  onChange={(e) => setForm((current) => ({ ...current, [key]: e.target.value }))}
                  className="w-full rounded border px-3 py-2"
                />
              )}
            </label>
          ))}

          {createMutation.error && (
            <div className="rounded border border-red-200 bg-red-50 p-3 text-sm text-red-800">
              Не удалось добавить контакт.
            </div>
          )}

          <div className="flex gap-2">
            <button
              type="submit"
              disabled={createMutation.isPending}
              className="rounded bg-blue-600 px-4 py-2 text-sm text-white hover:bg-blue-700 disabled:opacity-50"
            >
              {createMutation.isPending ? 'Сохранение...' : 'Сохранить'}
            </button>
            <button
              type="button"
              onClick={() => {
                setForm({})
                setIsAdding(false)
              }}
              className="rounded border bg-white px-4 py-2 text-sm text-gray-700 hover:bg-gray-100"
            >
              Отмена
            </button>
          </div>
        </form>
      )}

      <input
        type="search"
        value={filter}
        onChange={(e) => {
          setFilter(e.target.value)
          if (page !== 0) setSearchParams({ page: '0' })
        }}
        placeholder="Поиск внутри категории..."
        className="w-full rounded border bg-white px-3 py-2 text-sm"
      />

      {data.records.length === 0 ? (
        <p className="bg-white rounded shadow p-4">В этой категории нет записей.</p>
      ) : records.length === 0 ? (
        <p className="bg-white rounded shadow p-4">По фильтру ничего не найдено.</p>
      ) : (
        <div className="bg-white rounded-lg shadow overflow-x-auto">
          <table className="min-w-full text-sm">
            <thead className="bg-gray-100">
              <tr>
                <th className="px-3 py-2 text-left w-12">#</th>
                <th className="px-3 py-2 text-left w-64">Название</th>
                <th className="px-3 py-2 text-left">Адрес</th>
                {showManager && <th className="px-3 py-2 text-left">ФИО руководителя</th>}
                {showResponsible && <th className="px-3 py-2 text-left">Ответственные лица</th>}
                <th className="px-3 py-2 text-left">Телефон</th>
                <th className="px-3 py-2 w-12"></th>
              </tr>
            </thead>
            <tbody>
              {records.map((r, i) => (
                <tr key={r.id} className="border-t hover:bg-gray-50">
                  <td className="px-3 py-2 text-gray-500">{startIdx + i + 1}</td>
                  <td className="px-3 py-2 max-w-64">
                    <Link
                      to={`/contacts/${r.id}`}
                      state={{ from: `/contacts/category/${category}?page=${page}` }}
                      className={`block break-words hover:underline ${r.sync_status === 'not_matched' ? 'text-red-700' : 'text-blue-700'}`}
                    >
                      {contactTitle(r)}
                    </Link>
                    {r.sync_status === 'not_matched' && (
                      <div className="mt-1 text-xs text-red-700">Синхронизация не прошла</div>
                    )}
                  </td>
                  <td className="px-3 py-2 text-gray-700">
                    {contactAddress(r) || <span className="text-gray-400">—</span>}
                  </td>
                  {showManager && (
                    <td className="max-w-64 whitespace-pre-wrap px-3 py-2 text-gray-700">
                      {r.manager || <span className="text-gray-400">—</span>}
                    </td>
                  )}
                  {showResponsible && (
                    <td className="max-w-80 whitespace-pre-wrap px-3 py-2 text-gray-700">
                      {r.notes || <span className="text-gray-400">—</span>}
                    </td>
                  )}
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
      )}

      {pageCount > 1 && (
        <div className="flex justify-between items-center">
          <button
            disabled={page === 0}
            onClick={() => setSearchParams({ page: String(page - 1) })}
            className="px-3 py-1.5 bg-white border rounded disabled:opacity-40 hover:bg-gray-100"
          >
            ← Пред.
          </button>
          <span className="text-sm text-gray-600">
            Страница {page + 1} из {pageCount}
          </span>
          <button
            disabled={page >= pageCount - 1}
            onClick={() => setSearchParams({ page: String(page + 1) })}
            className="px-3 py-1.5 bg-white border rounded disabled:opacity-40 hover:bg-gray-100"
          >
            След. →
          </button>
        </div>
      )}
    </div>
  )
}
