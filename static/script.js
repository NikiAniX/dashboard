// Registered jobs (added by register_module.sh from each module's swagger.json)
let jobsData = [
    {
        id: "gdDownloader-post-gdDownloader",
        name: "Download (and optionally delete) Google Drive items",
        description: "Download files/folders from Google Drive, optionally deleting them from Drive afterwards.",
        status: 'completed',
        progress: 0,
        lastRun: 'Never',
        method: "POST",
        endpoint: "/gdDownloader",
        contentType: "multipart/form-data",
        formModalId: "runModal-gdDownloader-post-gdDownloader",
        logs: ["Registered POST /gdDownloader from swagger.json."]
    },
    {
        id: "pdfDecryptor-post-pdfDecryptor",
        name: "Decrypt an uploaded PDF",
        description: "Flask API service that decrypts password-protected PDF files via a file upload endpoint.",
        status: 'completed',
        progress: 0,
        lastRun: 'Never',
        method: "POST",
        endpoint: "/pdfDecryptor",
        contentType: "multipart/form-data",
        formModalId: "runModal-pdfDecryptor-post-pdfDecryptor",
        logs: ["Registered POST /pdfDecryptor from swagger.json."]
    },
];

let currentFilter = 'all';

// DOM Loaded Init
document.addEventListener('DOMContentLoaded', () => {
    renderJobs();
    updateStats();

    // Theme Toggle Logic
    const themeToggleBtn = document.getElementById('themeToggle');
    themeToggleBtn.addEventListener('click', () => {
        document.documentElement.classList.toggle('dark');
    });

    // Sidebar Toggle for Mobile
    const sidebarToggle = document.getElementById('sidebarToggle');
    const sidebar = document.getElementById('sidebar');
    sidebarToggle.addEventListener('click', () => {
        sidebar.classList.toggle('-translate-x-full');
    });

    // Search Filter
    const searchInput = document.getElementById('searchInput');
    searchInput.addEventListener('input', (e) => {
        renderJobs(e.target.value);
    });
});

// Escape text that originates from swagger.json before it goes into innerHTML
function escapeHtml(text) {
    const el = document.createElement('div');
    el.textContent = text ?? '';
    return el.innerHTML;
}

// Render Jobs Table
function renderJobs(searchQuery = '') {
    const tbody = document.getElementById('jobsTableBody');
    const emptyState = document.getElementById('emptyState');
    tbody.innerHTML = '';

    let filtered = jobsData.filter(job => {
        const matchesFilter = currentFilter === 'all' || job.status === currentFilter;
        const matchesSearch = job.name.toLowerCase().includes(searchQuery.toLowerCase()) || 
                              job.description.toLowerCase().includes(searchQuery.toLowerCase());
        return matchesFilter && matchesSearch;
    });

    if (filtered.length === 0) {
        emptyState.classList.remove('hidden');
        return;
    } else {
        emptyState.classList.add('hidden');
    }

    filtered.forEach(job => {
        let statusBadge = '';
        if (job.status === 'running') {
            statusBadge = `<span class="inline-flex items-center px-2.5 py-1 text-xs font-semibold rounded-lg bg-amber-500/10 text-amber-500"><i class="fa-solid fa-spinner fa-spin mr-1.5 text-[10px]"></i> Running</span>`;
        } else if (job.status === 'completed') {
            statusBadge = `<span class="inline-flex items-center px-2.5 py-1 text-xs font-semibold rounded-lg bg-emerald-500/10 text-emerald-500"><i class="fa-solid fa-circle-check mr-1.5 text-[10px]"></i> Completed</span>`;
        } else if (job.status === 'failed') {
            statusBadge = `<span class="inline-flex items-center px-2.5 py-1 text-xs font-semibold rounded-lg bg-rose-500/10 text-rose-500"><i class="fa-solid fa-circle-xmark mr-1.5 text-[10px]"></i> Failed</span>`;
        }

        const tr = document.createElement('tr');
        tr.className = 'hover:bg-slate-50/80 dark:hover:bg-slate-800/40 transition-colors';
        tr.innerHTML = `
            <td class="py-4 px-6">
                <div class="font-semibold text-slate-900 dark:text-slate-100">${escapeHtml(job.name)}</div>
                <div class="text-xs text-slate-500 dark:text-slate-400 mt-0.5">${escapeHtml(job.description)}</div>
            </td>
            <td class="py-4 px-6">${statusBadge}</td>
            <td class="py-4 px-6 w-48">
                <div class="flex items-center justify-between text-xs font-medium mb-1">
                    <span class="text-slate-500">${job.progress}%</span>
                </div>
                <div class="w-full bg-slate-100 dark:bg-slate-800 h-2 rounded-full overflow-hidden">
                    <div class="h-full rounded-full ${job.status === 'failed' ? 'bg-rose-500' : job.status === 'completed' ? 'bg-emerald-500' : 'bg-amber-500'}" style="width: ${job.progress}%"></div>
                </div>
            </td>
            <td class="py-4 px-6 text-xs text-slate-500 dark:text-slate-400">${job.lastRun}</td>
            <td class="py-4 px-6 text-right space-x-2">
                <button onclick="openRunParamsModal('${job.id}')" title="${job.status === 'running' ? 'Stop Job' : 'Configure & Run Job'}" class="w-8 h-8 rounded-lg bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-300 hover:bg-brand-50 hover:text-brand-600 dark:hover:bg-brand-500/20 dark:hover:text-brand-400 transition-colors">
                    <i class="fa-solid ${job.status === 'running' ? 'fa-stop' : 'fa-play'} text-xs"></i>
                </button>
                <button onclick="openLogsDrawer('${job.id}')" title="Inspect Logs" class="w-8 h-8 rounded-lg bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-300 hover:bg-blue-50 hover:text-blue-600 dark:hover:bg-blue-500/20 dark:hover:text-blue-400 transition-colors">
                    <i class="fa-solid fa-terminal text-xs"></i>
                </button>
            </td>
        `;
        tbody.appendChild(tr);
    });
}

// Update Stats Counters
function updateStats() {
    document.getElementById('statTotal').innerText = jobsData.length;
    document.getElementById('statRunning').innerText = jobsData.filter(j => j.status === 'running').length;
    document.getElementById('statCompleted').innerText = jobsData.filter(j => j.status === 'completed').length;
    document.getElementById('statFailed').innerText = jobsData.filter(j => j.status === 'failed').length;
}

// Filter Jobs
function filterJobs(status) {
    currentFilter = status;
    // Update button styles
    document.querySelectorAll('.filter-btn').forEach(btn => {
        btn.className = "filter-btn px-4 py-2 text-xs font-semibold rounded-xl text-slate-600 dark:text-slate-400 hover:bg-slate-100 dark:hover:bg-slate-800 transition-all";
    });
    event.target.className = "filter-btn px-4 py-2 text-xs font-semibold rounded-xl bg-brand-50 dark:bg-brand-500/10 text-brand-600 dark:text-brand-400 transition-all";
    renderJobs(document.getElementById('searchInput').value);
}

// Sort Jobs
function sortJobs() {
    const val = document.getElementById('sortSelect').value;
    if (val === 'name') {
        jobsData.sort((a,b) => a.name.localeCompare(b.name));
    } else if (val === 'status') {
        jobsData.sort((a,b) => a.status.localeCompare(b.status));
    } else {
        // recent mock sort
        jobsData.reverse();
    }
    renderJobs();
}

// Swagger-registered jobs: each has its own form modal in index.html (generated by register_module.sh)
function openSwaggerJobModal(job) {
    const modal = document.getElementById(job.formModalId);
    if (!modal) {
        showToast(`Form for "${job.name}" not found - restart the server and hard-refresh the page.`);
        return;
    }
    modal.classList.remove('hidden');
    modal.classList.add('flex');
}

function closeSwaggerJobModal(modalId) {
    const modal = document.getElementById(modalId);
    modal.classList.remove('flex');
    modal.classList.add('hidden');
}

// Call the job's endpoint with the form values, using the content type declared in swagger.json
async function callJobEndpoint(job, form) {
    const formData = new FormData(form);
    form.querySelectorAll('input[type=checkbox]').forEach(cb => formData.set(cb.name, cb.checked ? 'true' : 'false'));
    const textEntries = [...formData.entries()].filter(([, value]) => typeof value === 'string');
    const options = { method: job.method };
    let url = job.endpoint;

    if (!job.contentType) {
        url += '?' + new URLSearchParams(textEntries);
    } else if (job.contentType === 'application/json') {
        options.headers = { 'Content-Type': 'application/json' };
        options.body = JSON.stringify(Object.fromEntries(textEntries));
    } else if (job.contentType === 'application/x-www-form-urlencoded') {
        options.body = new URLSearchParams(textEntries);
    } else {
        options.body = formData;
    }
    return fetch(url, options);
}

async function handleSwaggerJobSubmit(e, id) {
    e.preventDefault();
    const job = jobsData.find(j => j.id === id);
    if (!job) return;

    const request = callJobEndpoint(job, e.target);
    job.status = 'running';
    job.progress = 10;
    job.lastRun = 'Just now';
    job.logs.push(`[${new Date().toLocaleTimeString()}] ${job.method} ${job.endpoint} started.`);
    closeSwaggerJobModal(job.formModalId);
    renderJobs();
    updateStats();

    try {
        const res = await request;
        let data = null;
        try { data = await res.json(); } catch (_) { /* non-JSON response */ }
        const succeeded = res.ok && (data?.status ? data.status === 'success' : true);
        const lines = data?.logs ?? [`HTTP ${res.status} ${res.statusText}`];
        job.status = succeeded ? 'completed' : 'failed';
        job.logs.push(...lines.map(line => `[${new Date().toLocaleTimeString()}] ${line}`));
    } catch (err) {
        job.status = 'failed';
        job.logs.push(`[${new Date().toLocaleTimeString()}] Request failed: ${err.message}`);
    }
    job.progress = 100;
    renderJobs();
    updateStats();
    showToast(`Job "${job.name}" ${job.status}.`);
}

// Run Parameters Modal State
let selectedJobForRun = null;

function openRunParamsModal(id) {
    const job = jobsData.find(j => j.id === id);
    if (!job) return;

    // If job is already running, provide option to stop immediately
    if (job.status === 'running') {
        job.status = 'completed';
        job.progress = 100;
        job.logs.push(`[${new Date().toLocaleTimeString()}] Job stopped manually by operator.`);
        showToast(`Job "${job.name}" stopped successfully.`);
        renderJobs();
        updateStats();
        return;
    }

    if (job.formModalId) {
        openSwaggerJobModal(job);
        return;
    }

    selectedJobForRun = job;
    document.getElementById('runModalJobTitle').innerText = `Configure Execution: ${job.name}`;
    document.getElementById('paramTimeout').value = '300';
    document.getElementById('paramArgs').value = '--env=production --verbose=true --retry=3';

    const modal = document.getElementById('runParamsModal');
    const panel = document.getElementById('runModalPanel');
    modal.classList.remove('hidden');
    modal.classList.add('flex');
    setTimeout(() => {
        panel.classList.remove('scale-95', 'opacity-0');
        panel.classList.add('scale-100', 'opacity-100');
    }, 10);
}

function closeRunParamsModal() {
    const modal = document.getElementById('runParamsModal');
    const panel = document.getElementById('runModalPanel');
    panel.classList.remove('scale-100', 'opacity-100');
    panel.classList.add('scale-95', 'opacity-0');
    setTimeout(() => {
        modal.classList.remove('flex');
        modal.classList.add('hidden');
        selectedJobForRun = null;
    }, 300);
}

function handleExecuteJobWithParams(e) {
    e.preventDefault();
    if (!selectedJobForRun) return;

    const timeout = document.getElementById('paramTimeout').value;
    const args = document.getElementById('paramArgs').value;
    const verbosity = document.getElementById('paramVerbosity').value;

    selectedJobForRun.status = 'running';
    selectedJobForRun.progress = 10;
    selectedJobForRun.lastRun = 'Just now';
    selectedJobForRun.logs.push(`[${new Date().toLocaleTimeString()}] Parameterized run initiated. Args: ${args} | Timeout: ${timeout}s | Verbosity: ${verbosity}`);

    renderJobs();
    updateStats();
    closeRunParamsModal();
    showToast(`Job "${selectedJobForRun.name}" started with parameters!`);
}

// Logs Drawer Control
function openLogsDrawer(id) {
    const job = jobsData.find(j => j.id === id);
    if (!job) return;

    document.getElementById('drawerJobTitle').innerText = job.name;
    const statusBadge = document.getElementById('drawerJobStatus');
    statusBadge.innerText = job.status.toUpperCase();

    const logsContainer = document.getElementById('drawerLogsContent');
    logsContainer.innerHTML = job.logs.map(log => `<div>${log}</div>`).join('');

    const drawer = document.getElementById('logsDrawer');
    const panel = document.getElementById('drawerPanel');
    drawer.classList.remove('hidden');
    setTimeout(() => {
        panel.classList.remove('translate-x-full');
    }, 10);
}

function closeLogsDrawer() {
    const drawer = document.getElementById('logsDrawer');
    const panel = document.getElementById('drawerPanel');
    panel.classList.add('translate-x-full');
    setTimeout(() => {
        drawer.classList.add('hidden');
    }, 300);
}

// New Job Modal Control
function openNewJobModal() {
    const modal = document.getElementById('newJobModal');
    const panel = document.getElementById('modalPanel');
    modal.classList.remove('hidden');
    modal.classList.add('flex');
    setTimeout(() => {
        panel.classList.remove('scale-95', 'opacity-0');
        panel.classList.add('scale-100', 'opacity-100');
    }, 10);
}

function closeNewJobModal() {
    const modal = document.getElementById('newJobModal');
    const panel = document.getElementById('modalPanel');
    panel.classList.remove('scale-100', 'opacity-100');
    panel.classList.add('scale-95', 'opacity-0');
    setTimeout(() => {
        modal.classList.remove('flex');
        modal.classList.add('hidden');
    }, 300);
}

function handleCreateJob(e) {
    e.preventDefault();
    const name = document.getElementById('newJobName').value;
    const desc = document.getElementById('newJobDesc').value;
    const env = document.getElementById('newJobEnv').value;
    const trigger = document.getElementById('newJobTrigger').value;

    const newJob = {
        id: 'job-' + Date.now(),
        name: name,
        description: desc,
        status: 'running',
        progress: 5,
        lastRun: 'Just now',
        logs: [
            `[${new Date().toLocaleTimeString()}] Initialized job container on target env: ${env}.`,
            `[${new Date().toLocaleTimeString()}] Trigger configured as: ${trigger}. Executing tasks...`
        ]
    };

    jobsData.unshift(newJob);
    renderJobs();
    updateStats();
    closeNewJobModal();
    document.getElementById('newJobForm').reset();
    showToast(`New job "${name}" created and started!`);
}

// Copy Logs to Clipboard
function copyLogs() {
    const logsContent = document.getElementById('drawerLogsContent').innerText;
    const textarea = document.createElement('textarea');
    textarea.value = logsContent;
    document.body.appendChild(textarea);
    textarea.select();
    document.execCommand('copy');
    document.body.removeChild(textarea);
    showToast('Logs copied to clipboard.');
}

// Refresh Simulation
function refreshJobsTable() {
    showToast('Dashboard stats re-synchronized.');
    renderJobs();
}

// Toast Notification Helper
function showToast(msg) {
    const toast = document.getElementById('toast');
    document.getElementById('toastMsg').innerText = msg;
    toast.classList.remove('translate-y-24', 'opacity-0');
    setTimeout(() => {
        toast.classList.add('translate-y-24', 'opacity-0');
    }, 3000);
}
