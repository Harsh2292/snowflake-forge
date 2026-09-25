/* Shared helpers for the HTML views. Each view defines render(state) and calls mount().
   DATA is injected by ui/view.py as JSON; no network calls, no external scripts. */

const DATA = JSON.parse(document.getElementById('forge-data').textContent);

function esc(value) {
  return String(value ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

const ICONS = {
  on_time_delivery_rate: '<path d="M2 6h11v9H2zM13 9h4l3 3v3h-7z" stroke-linejoin="round"/><circle cx="6" cy="17.5" r="1.8"/><circle cx="16.5" cy="17.5" r="1.8"/>',
  fill_rate: '<path d="M3.5 7.5 12 3l8.5 4.5v9L12 21l-8.5-4.5z M3.5 7.5 12 12l8.5-4.5 M12 12v9" stroke-linejoin="round"/>',
  days_of_inventory: '<path d="M2.5 20V9L12 4l9.5 5v11 M6.5 20v-7h11v7 M6.5 16.5h11" stroke-linejoin="round"/>',
  avg_landed_cost: '<circle cx="12" cy="12" r="8.5"/><path d="M14.8 9.2c-.5-1-1.6-1.6-2.8-1.6-1.6 0-2.8.9-2.8 2.1 0 2.9 5.8 1.4 5.8 4.4 0 1.2-1.3 2.2-3 2.2-1.3 0-2.5-.6-3-1.7 M12 6v1.6 M12 16.4V18" stroke-linecap="round"/>',
  check: '<circle cx="12" cy="12" r="10"/><path d="M7.5 12.3 10.6 15.3 16.6 8.9" stroke-linecap="round" stroke-linejoin="round"/>',
  cross: '<circle cx="12" cy="12" r="10"/><path d="M8.5 8.5l7 7M15.5 8.5l-7 7" stroke-linecap="round"/>',
  tick: '<path d="M4 12.5 9 17 20 6" stroke-linecap="round" stroke-linejoin="round"/>',
  lock: '<rect x="4.5" y="10.5" width="15" height="10" rx="2"/><path d="M8 10.5V7.5a4 4 0 0 1 8 0v3"/>',
  info: '<circle cx="12" cy="12" r="10"/><path d="M12 11v6 M12 7.5v.3" stroke-linecap="round"/>',
  up: '<path d="M12 19V5 M6 11l6-6 6 6" stroke-linecap="round" stroke-linejoin="round"/>',
  down: '<path d="M12 5v14 M6 13l6 6 6-6" stroke-linecap="round" stroke-linejoin="round"/>',
  close: '<path d="M6 6l12 12M18 6 6 18" stroke-linecap="round"/>',
  table: '<rect x="3.5" y="4.5" width="17" height="15" rx="2"/><path d="M3.5 9.5h17 M9.5 9.5v10"/>',
  arrow: '<path d="M5 12h14 M13 6l6 6-6 6" stroke-linecap="round" stroke-linejoin="round"/>',
  layers: '<path d="M12 3 2.5 8 12 13l9.5-5z M2.5 12 12 17l9.5-5 M2.5 16 12 21l9.5-5" stroke-linejoin="round"/>',
};

function icon(name, size = 22, color = 'currentColor', width = 1.8) {
  return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="${color}" stroke-width="${width}" aria-hidden="true">${ICONS[name] || ''}</svg>`;
}

function fmt(kind, v) {
  if (v === null || v === undefined || Number.isNaN(v)) return '';
  if (kind === 'percent') return (v * 100).toFixed(1) + '%';
  if (kind === 'currency') return '$' + v.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  return v.toFixed(1);
}

function deltaText(kind, d, unit) {
  const a = Math.abs(d);
  if (a < 1e-9) return 'Same as overall';
  const size = kind === 'percent' ? (a * 100).toFixed(1) + ' points' : kind === 'currency' ? '$' + a.toFixed(2) : a.toFixed(1) + (unit ? ' ' + unit : '');
  return size + (d > 0 ? ' above overall' : ' below overall');
}

/* Minimal state container: setState() re-renders the view. */
let STATE = {};
let RENDER = () => '';
function mount(render, initial) {
  RENDER = render;
  STATE = initial;
  paint();
}
function setState(patch) {
  STATE = Object.assign({}, STATE, patch);
  paint();
}
function paint() {
  const focusId = document.activeElement && document.activeElement.id;
  document.getElementById('app').innerHTML = RENDER(STATE);
  const open = !!STATE.drawer;
  if (!open) {
    document.body.classList.remove('drawer-open');
  } else if (!document.body.classList.contains('drawer-open')) {
    // two frames so the drawer is painted off-screen first, then slides in
    requestAnimationFrame(() => requestAnimationFrame(() => {
      document.body.classList.add('drawer-open');
      const close = document.getElementById('drawer-close');
      if (close) close.focus({ preventScroll: true });
    }));
  }
  if (focusId) {
    const el = document.getElementById(focusId);
    if (el) el.focus({ preventScroll: true });
  }
}

/* Event delegation: any element with data-act="name" calls ACTIONS[name](arg). */
const ACTIONS = {};
document.addEventListener('click', (e) => {
  const el = e.target.closest('[data-act]');
  if (!el || el.disabled) return;
  const fn = ACTIONS[el.dataset.act];
  if (fn) fn(el.dataset.arg);
});
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape' && STATE.drawer) setState({ drawer: null });
});

function drawer(title, subtitle, contentHtml) {
  return `<div class="scrim" data-act="closeDrawer"></div>
    <aside class="drawer" role="dialog" aria-modal="true" aria-label="${esc(title)}">
      <header><div class="stack gap8"><span class="h2">${esc(title)}</span>${subtitle ? `<span class="small ink2">${esc(subtitle)}</span>` : ''}</div>
      <button class="iconbtn" id="drawer-close" data-act="closeDrawer" aria-label="Close">${icon('close', 18)}</button></header>
      <div class="content">${contentHtml}</div>
    </aside>`;
}
ACTIONS.closeDrawer = () => setState({ drawer: null });
