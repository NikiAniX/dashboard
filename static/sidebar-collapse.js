(() => {
    const STORAGE_KEY = 'sidebarCollapsed';
    const button = document.getElementById('sidebarCollapse');
    if (!button) return;

    const read = () => { try { return localStorage.getItem(STORAGE_KEY) === '1'; } catch { return false; } };
    const write = (v) => { try { localStorage.setItem(STORAGE_KEY, v ? '1' : '0'); } catch {} };

    document.body.classList.toggle('sidebar-collapsed', read());
    button.addEventListener('click', () => {
        const collapsed = document.body.classList.toggle('sidebar-collapsed');
        write(collapsed);
        window.dispatchEvent(new Event('resize'));
    });
})();
