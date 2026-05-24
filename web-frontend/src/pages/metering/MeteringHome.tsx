import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Link, useNavigate } from 'react-router-dom'
import { useState } from 'react'
import { meteringApi, type MeteringCategoryInfo } from '../../api/metering'
import { useAuth } from '../../contexts/AuthContext'
import { meteringRu as t } from '../../locales/ru/metering'

export default function MeteringHome() {
  const { canDelete } = useAuth()
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const [settingsOpen, setSettingsOpen] = useState(false)

  const { data, isLoading, error } = useQuery({
    queryKey: ['metering', 'overview'],
    queryFn: () => meteringApi.overview(),
  })

  const categories = data?.categories ?? []

  return (
    <div className="space-y-4">
      <nav className="text-sm text-gray-600">
        <Link to="/objects" className="text-blue-600 hover:underline">Объекты</Link>
        <span className="mx-1">→</span>
        <span className="text-gray-900">Приборы учета</span>
      </nav>

      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <h1 className="text-2xl font-bold">{t.home.title}</h1>
          <p className="text-sm text-gray-600">{t.home.subtitle}</p>
        </div>
        <button
          type="button"
          onClick={() => setSettingsOpen(true)}
          className="inline-flex items-center justify-center rounded border bg-white px-3 py-2 text-sm text-gray-700 hover:bg-gray-100"
        >
          Настройки
        </button>
      </div>

      {isLoading && <div className="text-gray-500">Загрузка...</div>}
      {error && (
        <div className="rounded border border-red-200 bg-red-50 p-3 text-red-800">
          Не удалось загрузить группы приборов учета.
        </div>
      )}

      {categories.length > 0 && (
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {categories.map((cat) => (
            <Link
              key={cat.key}
              to={`/metering/${cat.key}`}
              className="rounded-lg border border-transparent bg-white p-5 shadow transition hover:border-blue-300"
            >
              <h2 className="font-semibold">{cat.label}</h2>
              <p className="mt-2 text-3xl font-bold text-blue-600">{cat.count}</p>
              <p className="text-xs text-gray-500">приборов учета</p>
            </Link>
          ))}
        </div>
      )}

      {settingsOpen && (
        <MeteringSettingsModal
          categories={categories}
          canDelete={canDelete}
          onClose={() => setSettingsOpen(false)}
          onCreated={(key) => {
            queryClient.invalidateQueries({ queryKey: ['metering'] })
            setSettingsOpen(false)
            navigate(`/metering/${key}`)
          }}
          onChanged={() => queryClient.invalidateQueries({ queryKey: ['metering'] })}
        />
      )}
    </div>
  )
}

function MeteringSettingsModal({
  categories,
  canDelete,
  onClose,
  onCreated,
  onChanged,
}: {
  categories: MeteringCategoryInfo[]
  canDelete: boolean
  onClose: () => void
  onCreated: (key: string) => void
  onChanged: () => void
}) {
  const [categoryForm, setCategoryForm] = useState({ label: '', key: '' })
  const [editingCategory, setEditingCategory] = useState<MeteringCategoryInfo | null>(null)
  const [editForm, setEditForm] = useState({ label: '', sort_order: '' })

  const createCategory = useMutation({
    mutationFn: () => meteringApi.createCategory({
      label: categoryForm.label.trim(),
      key: categoryForm.key.trim() || undefined,
    }),
    onSuccess: (category) => {
      onChanged()
      setCategoryForm({ label: '', key: '' })
      onCreated(category.key)
    },
  })

  const updateCategory = useMutation({
    mutationFn: () => meteringApi.updateCategory(editingCategory!.key, {
      label: editForm.label.trim(),
      sort_order: editForm.sort_order.trim() ? Number(editForm.sort_order) : undefined,
    }),
    onSuccess: () => {
      onChanged()
      setEditingCategory(null)
      setEditForm({ label: '', sort_order: '' })
    },
  })

  const deleteCategory = useMutation({
    mutationFn: (category: MeteringCategoryInfo) => meteringApi.deleteCategory(category.key),
    onSuccess: () => onChanged(),
  })

  return (
    <div className="fixed inset-0 z-40 flex items-start justify-center bg-black/40 p-4 pt-12 overflow-y-auto">
      <div className="w-full max-w-2xl rounded-lg bg-white p-5 shadow-xl">
        <div className="mb-4 flex items-center justify-between">
          <h2 className="text-lg font-semibold">Группы приборов учета</h2>
          <button type="button" onClick={onClose} className="rounded border bg-white px-3 py-1.5 text-sm text-gray-700 hover:bg-gray-100">
            Закрыть
          </button>
        </div>

        <form
          onSubmit={(e) => {
            e.preventDefault()
            if (categoryForm.label.trim()) createCategory.mutate()
          }}
          className="mb-4 grid gap-3 rounded border bg-gray-50 p-4 sm:grid-cols-[1fr_1fr_auto]"
        >
          <input
            value={categoryForm.label}
            onChange={(e) => setCategoryForm((current) => ({ ...current, label: e.target.value }))}
            placeholder="Название группы"
            className="rounded border px-3 py-2 text-sm"
          />
          <input
            value={categoryForm.key}
            onChange={(e) => setCategoryForm((current) => ({ ...current, key: e.target.value }))}
            placeholder="Ключ (необязательно)"
            className="rounded border px-3 py-2 text-sm"
          />
          <button
            type="submit"
            disabled={createCategory.isPending || !categoryForm.label.trim()}
            className="rounded bg-blue-600 px-4 py-2 text-sm text-white hover:bg-blue-700 disabled:opacity-50"
          >
            Создать группу
          </button>
        </form>

        {editingCategory && (
          <form
            onSubmit={(e) => {
              e.preventDefault()
              if (editForm.label.trim()) updateCategory.mutate()
            }}
            className="mb-4 grid gap-3 rounded border border-blue-200 bg-blue-50 p-4 sm:grid-cols-[1fr_100px_auto_auto]"
          >
            <input
              value={editForm.label}
              onChange={(e) => setEditForm((current) => ({ ...current, label: e.target.value }))}
              className="rounded border px-3 py-2 text-sm"
            />
            <input
              value={editForm.sort_order}
              onChange={(e) => setEditForm((current) => ({ ...current, sort_order: e.target.value }))}
              placeholder="Порядок"
              className="rounded border px-3 py-2 text-sm"
            />
            <button
              type="submit"
              disabled={updateCategory.isPending || !editForm.label.trim()}
              className="rounded bg-blue-600 px-4 py-2 text-sm text-white hover:bg-blue-700 disabled:opacity-50"
            >
              Сохранить
            </button>
            <button
              type="button"
              onClick={() => setEditingCategory(null)}
              className="rounded border bg-white px-4 py-2 text-sm text-gray-700 hover:bg-gray-100"
            >
              Отмена
            </button>
          </form>
        )}

        <div className="space-y-2">
          {categories.map((cat) => (
            <div key={cat.key} className="flex flex-col gap-2 rounded border p-3 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <div className="font-medium">{cat.label}</div>
                <div className="text-xs text-gray-500">{cat.key} · {cat.count} записей</div>
              </div>
              <div className="flex gap-2">
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
                      if (window.confirm(`Удалить группу «${cat.label}»?`)) deleteCategory.mutate(cat)
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

        {(createCategory.error || updateCategory.error || deleteCategory.error) && (
          <div className="mt-4 rounded border border-red-200 bg-red-50 p-3 text-sm text-red-800">
            {(createCategory.error as { message?: string })?.message
              || (updateCategory.error as { message?: string })?.message
              || (deleteCategory.error as { message?: string })?.message
              || 'Ошибка сохранения.'}
          </div>
        )}
      </div>
    </div>
  )
}
