import type { ArshinForm } from '../../api/arshin'

export const arshinEn = {
  title: 'ARSHIN — meter verification',
  fields: [
    { key: 'org_title', label: 'Verifier (organization)' },
    { key: 'year', label: 'Verification year' },
    { key: 'mi_number', label: 'Meter serial' },
    { key: 'mit_notation', label: 'Type/notation' },
  ] as Array<{ key: keyof ArshinForm; label: string }>,
  anyOrg: '— any —',
  find: 'Find meter',
  searching: 'Searching...',
  clear: 'Clear',
  downloadPrefix: 'Verification',
  pdfError: 'Failed to download PDF',
  verification: 'Verification',
  until: 'until',
} as const
