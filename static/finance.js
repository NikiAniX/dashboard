const PALETTE = ['#3b82f6', '#22c55e', '#f59e0b', '#ef4444', '#a855f7', '#14b8a6', '#ec4899', '#64748b'];
const DAY_NAMES = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MONTH_NAMES = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const DEBIT = 'Dr';
const TOP_CATEGORY_COUNT = 10;

let allData = { cards: [], transactions: [] };
const charts = {};

const $ = (id) => document.getElementById(id);
const inr = (n) => '₹' + Number(n).toLocaleString('en-IN', { maximumFractionDigits: 2 });
const isDark = () => document.documentElement.classList.contains('dark');
const sumBy = (rows, keyFn, valFn) => {
    const out = new Map();
    rows.forEach((r) => out.set(keyFn(r), (out.get(keyFn(r)) || 0) + valFn(r)));
    return out;
};
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const monthLabel = (ym) => { const [y, m] = ym.split('-'); return `${MONTH_NAMES[+m - 1]} ${y}`; };

function draw(id, config) {
    const textColor = isDark() ? '#94a3b8' : '#64748b';
    const gridColor = isDark() ? '#1e293b' : '#e2e8f0';
    Chart.defaults.color = textColor;
    Chart.defaults.font.family = 'Inter, sans-serif';
    if (config.options?.scales) {
        Object.values(config.options.scales).forEach((s) => { s.grid = { color: gridColor }; });
    }
    charts[id]?.destroy();
    charts[id] = new Chart($(id), config);
}

const baseOptions = (extra = {}) => ({
    responsive: true,
    maintainAspectRatio: false,
    plugins: { legend: { display: false } },
    ...extra,
});

function barChart(id, labels, datasets, stacked = false) {
    draw(id, {
        type: 'bar',
        data: { labels, datasets },
        options: baseOptions({
            plugins: { legend: { display: datasets.length > 1 } },
            scales: { x: { stacked }, y: { stacked, beginAtZero: true } },
        }),
    });
}

function doughnut(id, labels, values) {
    draw(id, {
        type: 'doughnut',
        data: { labels, datasets: [{ data: values, backgroundColor: PALETTE, borderWidth: 0 }] },
        options: baseOptions({ plugins: { legend: { display: true, position: 'right' } }, cutout: '62%' }),
    });
}

const dateRange = () => ({ from: $('dateFrom').value, to: $('dateTo').value });
// ISO yyyy-mm-dd strings compare correctly as plain strings; empty bound = open-ended.
const inRange = (iso, { from, to }) => (!from || iso >= from) && (!to || iso <= to);

function selectedTransactions() {
    const card = $('cardFilter').value;
    const range = dateRange();
    return allData.transactions.filter((t) => (card === 'all' || t.card === card) && inRange(t.date, range));
}

function selectedStatements() {
    const card = $('cardFilter').value;
    const range = dateRange();
    const filtering = range.from || range.to;
    return allData.cards.filter((c) => (card === 'all' || c.card === card)
        && (!filtering || (c.statement_iso && inRange(c.statement_iso, range))));
}

function renderStats(txns) {
    const spend = txns.filter((t) => t.type === DEBIT);
    const credits = txns.filter((t) => t.type !== DEBIT);
    const total = (rows) => rows.reduce((a, t) => a + t.amount, 0);
    const txnPoints = txns.reduce((a, t) => a + t.reward_points, 0);
    const cashback = txns.reduce((a, t) => a + t.cashback, 0);
    const stmtPoints = selectedStatements()
        .reduce((a, c) => a + c.statement_points, 0);

    $('statSpend').textContent = inr(total(spend));
    $('statSpendSub').textContent = `${spend.length} debit transactions`;
    $('statPaid').textContent = inr(total(credits));
    $('statPaidSub').textContent = `${credits.length} credit entries`;
    $('statPoints').textContent = Math.round(txnPoints + stmtPoints).toLocaleString('en-IN');
    $('statPointsSub').textContent = `${Math.round(txnPoints)} per-transaction + ${Math.round(stmtPoints)} statement`;
    $('statCashback').textContent = inr(cashback);
    $('statCashbackSub').textContent = 'Credited by issuer';
}

function renderCharts(txns) {
    const spend = txns.filter((t) => t.type === DEBIT);
    const amount = (t) => t.amount;
    const blue = PALETTE[0];

    const byDate = [...sumBy(spend, (t) => t.date, amount)].sort();
    draw('chartDate', {
        type: 'line',
        data: {
            labels: byDate.map(([d]) => d),
            datasets: [{ data: byDate.map(([, v]) => v), borderColor: blue, backgroundColor: blue + '22', fill: true, tension: 0.3, pointRadius: 3 }],
        },
        options: baseOptions({ scales: { y: { beginAtZero: true } } }),
    });

    const byDay = sumBy(spend, (t) => new Date(t.date + 'T00:00:00').getDay(), amount);
    barChart('chartDay', DAY_NAMES, [{ data: DAY_NAMES.map((_, i) => byDay.get(i) || 0), backgroundColor: PALETTE[2], borderRadius: 6 }]);

    const months = [...new Set(txns.map((t) => t.date.slice(0, 7)))].sort();
    const spendByMonth = sumBy(spend, (t) => t.date.slice(0, 7), amount);
    const paidByMonth = sumBy(txns.filter((t) => t.type !== DEBIT), (t) => t.date.slice(0, 7), amount);
    barChart('chartMonth', months.map(monthLabel), [
        { label: 'Spend', data: months.map((m) => spendByMonth.get(m) || 0), backgroundColor: blue, borderRadius: 6 },
        { label: 'Payments / credits', data: months.map((m) => paidByMonth.get(m) || 0), backgroundColor: PALETTE[1], borderRadius: 6 },
    ]);

    const byCard = [...sumBy(spend, (t) => t.card, amount)];
    doughnut('chartCard', byCard.map(([k]) => k), byCard.map(([, v]) => v));

    const byCategory = [...sumBy(spend, (t) => t.category, amount)].sort((a, b) => b[1] - a[1]).slice(0, TOP_CATEGORY_COUNT);
    draw('chartCategory', {
        type: 'bar',
        data: { labels: byCategory.map(([k]) => k), datasets: [{ data: byCategory.map(([, v]) => v), backgroundColor: PALETTE[4], borderRadius: 6 }] },
        options: baseOptions({ indexAxis: 'y', scales: { x: { beginAtZero: true } } }),
    });

    const points = [...sumBy(txns, (t) => t.card, (t) => t.reward_points)];
    const statementPoints = new Map(selectedStatements().map((c) => [c.card, c.statement_points]));
    const pointRows = points.map(([card, v]) => [card, v + (statementPoints.get(card) || 0)]);
    barChart('chartPoints', pointRows.map(([k]) => k), [{ data: pointRows.map(([, v]) => v), backgroundColor: PALETTE[2], borderRadius: 6 }]);

    const cashbackByMonth = sumBy(txns, (t) => t.date.slice(0, 7), (t) => t.cashback);
    barChart('chartCashback', months.map(monthLabel), [{ data: months.map((m) => cashbackByMonth.get(m) || 0), backgroundColor: PALETTE[3], borderRadius: 6 }]);
}

function renderCards() {
    $('cardsBody').innerHTML = selectedStatements().map((c) => {
        const used = c.credit_limit ? Math.round((1 - c.available_credit / c.credit_limit) * 100) + '%' : '–';
        return `<tr><td class="py-3 px-6 font-medium">${esc(c.card)}</td>
            <td class="py-3 px-6 text-slate-500">${esc(c.statement_date || '–')}</td>
            <td class="py-3 px-6 text-slate-500">${esc(c.due_date || '–')}</td>
            <td class="py-3 px-6 text-right">${inr(c.total_due)}</td>
            <td class="py-3 px-6 text-right">${used}</td></tr>`;
    }).join('');
}

function renderTable(txns) {
    const q = $('searchInput').value.trim().toLowerCase();
    const rows = txns.filter((t) => !q || `${t.details} ${t.card} ${t.category}`.toLowerCase().includes(q)).reverse();
    $('txnCount').textContent = `(${rows.length})`;
    $('txnBody').innerHTML = rows.map((t) => {
        const credit = t.type !== DEBIT;
        return `<tr><td class="py-3 px-6 whitespace-nowrap">${t.date}</td>
            <td class="py-3 px-6">${esc(t.details)}</td>
            <td class="py-3 px-6 whitespace-nowrap">${esc(t.card)}</td>
            <td class="py-3 px-6"><span class="px-2 py-1 text-xs rounded-lg bg-slate-100 dark:bg-slate-800">${esc(t.category)}</span></td>
            <td class="py-3 px-6 text-right font-medium whitespace-nowrap ${credit ? 'text-emerald-500' : ''}">${credit ? '+' : ''}${inr(t.amount)}</td>
            <td class="py-3 px-6 text-right">${t.reward_points || '–'}</td>
            <td class="py-3 px-6 text-right">${t.cashback ? inr(t.cashback) : '–'}</td></tr>`;
    }).join('');
}

function render() {
    $('clearDates').classList.toggle('hidden', !($('dateFrom').value || $('dateTo').value));
    const txns = selectedTransactions();
    renderStats(txns);
    renderCharts(txns);
    renderCards();
    renderTable(txns);
}

async function loadData() {
    $('errorBox').classList.add('hidden');
    try {
        const res = await fetch('/api/finance');
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        allData = await res.json();
    } catch (err) {
        $('errorBox').textContent = `Could not load financial data: ${err.message}`;
        $('errorBox').classList.remove('hidden');
        return;
    }
    const selected = $('cardFilter').value;
    const cards = [...new Set(allData.cards.map((c) => c.card))];
    $('cardFilter').innerHTML = '<option value="all">All cards</option>' +
        cards.map((c) => `<option value="${esc(c)}">${esc(c)}</option>`).join('');
    $('cardFilter').value = cards.includes(selected) ? selected : 'all';
    $('sourceInfo').textContent = `${allData.cards.length} statements · ${allData.transactions.length} transactions · ${allData.data_dir}`;
    render();
}

$('cardFilter').addEventListener('change', render);
['dateFrom', 'dateTo'].forEach((id) => $(id).addEventListener('change', render));
$('clearDates').addEventListener('click', () => { $('dateFrom').value = ''; $('dateTo').value = ''; render(); });
$('searchInput').addEventListener('input', () => renderTable(selectedTransactions()));
$('refreshBtn').addEventListener('click', loadData);
$('themeToggle').addEventListener('click', () => { document.documentElement.classList.toggle('dark'); render(); });
$('sidebarToggle').addEventListener('click', () => $('sidebar').classList.toggle('-translate-x-full'));

loadData();
