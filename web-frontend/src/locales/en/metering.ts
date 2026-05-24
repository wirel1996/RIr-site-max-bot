import type { MeteringRecord } from '../../api/metering'

export const meteringEn = {
  home: {
    title: 'Metering',
    subtitle: 'UUTE, acts, verifications, seals, and readings.',
    gspoTitle: 'GSPO',
    gspoDesc: 'Garages, UUTE, devices, and latest data.',
  },
  gspo: {
    back: '← Metering',
    title: 'GSPO',
    total: (n: number) => `Total objects: ${n}`,
    fallbackTotal: 'UUTE objects',
    refreshing: ' · refreshing...',
    searchPlaceholder: 'Search by name, address, contract, meter...',
    export: 'Export objects',
    upload: 'Upload Excel',
    uploading: 'Uploading...',
    importMessage: (a: number, u: number, un: number, s: number) => `Import: added ${a}, updated ${u}, unchanged ${un}, skipped ${s}.`,
    importFailed: 'Failed to import file.',
    viewChanges: 'View changes',
    changesTitle: 'What changed',
    close: 'Close',
    row: 'Row',
    object: 'Object',
    changes: 'Changes',
    loading: 'Loading...',
    loadFailed: 'Loading failed.',
    nothingFound: 'Nothing found.',
    table: { name: 'Name', address: 'Address', calculator: 'Calculator', nearest: 'Nearest verification' },
    prev: '← Prev',
    next: 'Next →',
    page: (p: number, c: number) => `Page ${p} of ${c}`,
  },
  detail: {
    groups: [] as Array<[string, Array<[keyof MeteringRecord, string]>]>,
  },
} as const
