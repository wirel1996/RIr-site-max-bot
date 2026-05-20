export const homeEn = {
  title: 'Home',
  subtitle: 'Main OKE sections and services.',
  sectionsTitle: 'Sections',
  servicesTitle: 'Services',
  primaryTiles: [
    { to: '/journal', title: 'Electronic Journal', desc: 'Tasks and notes by addresses' },
    { to: '/contacts', title: 'Consumer Contacts', desc: 'HOA, GSPO, Individuals, Legal entities, Iglakovo, embedded premises' },
  ],
  serviceTiles: [
    { to: '/arshin', title: 'ARSHIN', desc: 'Device verification and ARSHIN checks' },
    { to: '/metering', title: 'Metering', desc: 'UUTE cards, verifications, and contact links' },
    { to: '/summer-water', title: 'Summer Water GSPO', desc: 'Applications registry, payment, connection, and water supply', waterAllowed: true },
    { to: '/billing', title: 'DHW Billing', desc: 'Consumers, readings, and commissioning dates', billingOnly: true },
    { to: '/calculations', title: 'Calculations', desc: 'Heat load and throttle diaphragm' },
    { to: '/algorithms', title: 'Algorithms', desc: 'Work procedures and reference information' },
    { to: '/admin', title: 'Admin', desc: 'Users, roles, and MAX notifications', adminOnly: true },
  ],
} as const
