// Тонкая обёртка над fetch. Авторизация — серверная сессия (cookie 'oke_session').
// На любой 401 (кроме самого /auth/login) шлём событие 'auth:expired',
// AuthProvider слушает и сбрасывает текущего пользователя.

export type ApiError = {
  status: number
  message: string
}

const PUBLIC_PATHS = ['/auth/login']

function clientPageHeader(): Record<string, string> {
  if (typeof window === 'undefined') return {}
  const page = `${window.location.pathname}${window.location.search}${window.location.hash}`
  return page ? { 'X-Client-Page': page } : {}
}

async function request<T>(
  path: string,
  init?: RequestInit,
): Promise<T> {
  const isFormData = init?.body instanceof FormData
  const res = await fetch(`/api${path}`, {
    ...init,
    headers: {
      ...(isFormData ? {} : { 'Content-Type': 'application/json' }),
      Accept: 'application/json',
      ...clientPageHeader(),
      ...(init?.headers ?? {}),
    },
    credentials: 'same-origin',
  })

  if (!res.ok) {
    let body: string
    try {
      body = await res.text()
    } catch {
      body = res.statusText
    }
    let message = body || res.statusText
    try {
      const parsed = JSON.parse(body) as { error?: string }
      if (parsed?.error) message = parsed.error
    } catch {
      // body не JSON — оставляем текст как есть
    }

    if (res.status === 401 && !PUBLIC_PATHS.includes(path)) {
      window.dispatchEvent(new CustomEvent('auth:expired'))
    }

    const error: ApiError = { status: res.status, message }
    throw error
  }

  if (res.status === 204) return undefined as T

  return (await res.json()) as T
}

export const api = {
  get: <T>(path: string) => request<T>(path),
  post: <T>(path: string, data?: unknown) =>
    request<T>(path, { method: 'POST', body: JSON.stringify(data ?? {}) }),
  patch: <T>(path: string, data?: unknown) =>
    request<T>(path, { method: 'PATCH', body: JSON.stringify(data ?? {}) }),
  delete: <T>(path: string) =>
    request<T>(path, { method: 'DELETE' }),
  deleteData: <T>(path: string, data?: unknown) =>
    request<T>(path, { method: 'DELETE', body: JSON.stringify(data ?? {}) }),
  upload: <T>(path: string, formData: FormData) =>
    request<T>(path, { method: 'POST', body: formData, headers: {} }),
}
