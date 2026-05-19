const STORAGE_KEY = 'arshin_meter_type_prefs'

export function getPreferredMitNotation(serialKey: string): string | undefined {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (!raw) return undefined
    const prefs: Record<string, string> = JSON.parse(raw)
    return prefs[serialKey] || undefined
  } catch {
    return undefined
  }
}

export function savePreferredMitNotation(serialKey: string, mitNotation: string) {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    const prefs: Record<string, string> = raw ? JSON.parse(raw) : {}
    prefs[serialKey] = mitNotation
    localStorage.setItem(STORAGE_KEY, JSON.stringify(prefs))
  } catch {
    // ignore
  }
}

export function clearPreferredMitNotation(serialKey: string) {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (!raw) return
    const prefs: Record<string, string> = JSON.parse(raw)
    delete prefs[serialKey]
    localStorage.setItem(STORAGE_KEY, JSON.stringify(prefs))
  } catch {
    // ignore
  }
}
