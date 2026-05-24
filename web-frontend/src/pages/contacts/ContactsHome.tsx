import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Link, useNavigate } from 'react-router-dom'
import { useState, type FormEvent } from 'react'
import { contactsApi, type CategoryInfo } from '../../api/contacts'
import { useAuth } from '../../contexts/AuthContext'

export default function ContactsHome() {
  const { canDelete } = useAuth()
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const [query, setQuery] = useState('')
  const [isCreatingCategory, setIsCreatingCategory] = useState(false)
  const [categoryForm, setCategoryForm] = useState({ label: '', key: '' })
  const [editingCategory, setEditingCategory] = useState<CategoryInfo | null>(null)
  const [editForm, setEditForm] = useState({ label: '', sort_order: '' })

  const { data, isLoading, error } = useQuery({
    queryKey: ['contacts', 'overview'],
    queryFn: () => contactsApi.overview(),
  })

  const onSearch = (e: FormEvent) => {
    e.preventDefault()
    const q = query.trim()
    if (q.length >= 2) navigate(`/contacts/search?q=${encodeURIComponent(q)}`)
  }

  const createCategory = useMutation({
    mutationFn: () => contactsApi.createCategory({
      label: categoryForm.label.trim(),
      key: categoryForm.key.trim() || undefined,
    }),
    onSuccess: (category) => {
      queryClient.invalidateQueries({ queryKey: ['contacts'] })
      setCategoryForm({ label: '', key: '' })
      setIsCreatingCategory(false)
      navigate(`/contacts/category/${category.key}`)
    },
  })

  const updateCategory = useMutation({
    mutationFn: () => contactsApi.updateCategory(editingCategory!.key, {
      label: editForm.label.trim(),
      sort_order: editForm.sort_order.trim() ? Number(editForm.sort_order) : undefined,
    }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['contacts'] })
      setEditingCategory(null)
      setEditForm({ label: '', sort_order: '' })
    },
  })

  const deleteCategory = useMutation({
    mutationFn: (category: CategoryInfo) => contactsApi.deleteCategory(category.key),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['contacts'] }),
  })

  return (
    <div className="space-y-4">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <h1 className="text-2xl font-bold">Контакты потребителей</h1>
        <div className="flex flex-col gap-2 sm:flex-row">
          <button
            type="button"
            onClick={() => setIsCreatingCategory((value) => !value)}
            className="rounded bg-blue-600 px-3 py-1.5 text-sm text-white hover:bg-blue-700"
          >
            Создать категорию
          </button>
          <form onSubmit={onSearch} className="flex gap-2">
            <input
              type="text"
              placeholder="Поиск..."
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              className="w-full rounded border px-3 py-1.5 sm:w-64"
            />
            <button
              type="submit"
              className="rounded bg-blue-600 px-3 text-white hover:bg-blue-700"
            >
              Найти
            </button>
          </form>
        </div>
      </div>

      {isCreatingCategory && (
        <form
          onSubmit={(e) => {
            e.preventDefault()
            if (categoryForm.label.trim()) createCategory.mutate()
          }}
          className="grid gap-3 rounded-lg bg-white p-4 shadow sm:grid-cols-[1fr_auto]"
        >
          <input
            value={categoryForm.label}
            onChange={(e) => setCategoryForm((current) => ({ ...current, label: e.target.value }))}
            placeholder="Название категории"
            className="rounded border px-3 py-2"
          />
          <button
            type="submit"
            disabled={createCategory.isPending || !categoryForm.label.trim()}
            className="rounded bg-blue-600 px-4 py-2 text-white hover:bg-blue-700 disabled:opacity-50"
          >
            Создать
          </button>
        </form>
      )}

      {editingCategory && (
        <form
          onSubmit={(e) => {
            e.preventDefault()
            if (editForm.label.trim()) updateCategory.mutate()
          }}
          className="grid gap-3 rounded-lg bg-white p-4 shadow sm:grid-cols-[1fr_120px_auto_auto]"
        >
          <input
            value={editForm.label}
            onChange={(e) => setEditForm((current) => ({ ...current, label: e.target.value }))}
            className="rounded border px-3 py-2"
          />
          <input
            value={editForm.sort_order}
            onChange={(e) => setEditForm((current) => ({ ...current, sort_order: e.target.value }))}
            placeholder="Порядок"
            className="rounded border px-3 py-2"
          />
          <button
            type="submit"
            disabled={updateCategory.isPending || !editForm.label.trim()}
            className="rounded bg-blue-600 px-4 py-2 text-white hover:bg-blue-700 disabled:opacity-50"
          >
            Сохранить
          </button>
          <button
            type="button"
            onClick={() => setEditingCategory(null)}
            className="rounded border bg-white px-4 py-2 text-gray-700 hover:bg-gray-100"
          >
            Отмена
          </button>
        </form>
      )}

      {isLoading && <div className="text-gray-500">Загрузка...</div>}
      {error && (
        <div className="rounded border border-red-200 bg-red-50 p-3 text-red-800">
          Ошибка загрузки. Проверьте API.
        </div>
      )}

      {data && (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {data.categories.map((cat) => (
            <div
              key={cat.key}
              className="rounded-lg border border-transparent bg-white p-5 shadow transition hover:border-blue-300"
            >
              <Link to={`/contacts/category/${cat.key}`} className="block">
                <h2 className="text-base font-semibold">{cat.label}</h2>
                <p className="mt-2 text-3xl font-bold text-blue-600">{cat.count}</p>
                <p className="text-xs text-gray-500">записей</p>
              </Link>
              <div className="mt-4 flex gap-2 border-t pt-3">
                <button
                  type="button"
                  onClick={() => {
                    setEditingCategory(cat)
                    setEditForm({ label: cat.label, sort_order: String(cat.sort_order ?? '') })
                  }}
                  className="rounded border bg-white px-2 py-1 text-xs text-gray-700 hover:bg-gray-100"
                >
                  Редактировать
                </button>
                {!cat.system && cat.count === 0 && canDelete && (
                  <button
                    type="button"
                    disabled={deleteCategory.isPending}
                    onClick={() => {
                      if (window.confirm(`Delete category "${cat.label}"?`)) deleteCategory.mutate(cat)
                    }}
                    className="rounded border border-red-200 bg-white px-2 py-1 text-xs text-red-700 hover:bg-red-50 disabled:opacity-40"
                  >
                    Удалить
                  </button>
                )}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
