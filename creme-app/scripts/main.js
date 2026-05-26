/* ══════════════════════════════════════════════════════
   CRÈME DE LA STYLE — Main Script
   OAU Official Hub
══════════════════════════════════════════════════════ */

// ── Supabase Init ────────────────────────────────────
const SUPABASE_URL = 'https://nfoeltjcmemcpwdwewbq.supabase.co';
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5mb2VsdGpjbWVtY3B3ZHdld2JxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk1Nzc5MDgsImV4cCI6MjA5NTE1MzkwOH0.YIp_5dRhsSYCdwpNy51RRqmKtzx4qZY5yHXfbBlnxMk';
let supabase = null;

// ── App State ────────────────────────────────────────
window.currentUser    = null;
window.isLoginMode    = true;
window.votes          = {};
window.expandedCategory = null;

const awardCategories = [
    { id: 'artist',       title: 'Most Fashionable Artist of the Year' },
    { id: 'creator',      title: 'Most Fashionable Content Creator of the Year' },
    { id: 'actor',        title: 'Most Fashionable Actor of the Year' },
    { id: 'dancer',       title: 'Most Fashionable Dancer of the Year' },
    { id: 'entrepreneur', title: 'Most Fashionable Entrepreneur of the Year' },
    { id: 'comedian',     title: 'Most Fashionable Comedian of the Year' },
    { id: 'influencer',   title: 'Most Fashionable Influencer of the Year' },
    { id: 'student',      title: 'Most Fashionable Student Personality of the Year' },
];

const mockNominees = [
    { id: 'n1', name: 'Tunde A.' },
    { id: 'n2', name: 'Bisi O.' },
    { id: 'n3', name: 'Zara Cole' },
];

// ══════════════════════════════════════════════════════
//  BOOT — waits for HTML + CDN to finish loading
// ══════════════════════════════════════════════════════
document.addEventListener('DOMContentLoaded', async () => {
    if (window.supabase) {
        supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);

        supabase.auth.onAuthStateChange((_event, session) => {
            window.currentUser = session?.user ?? null;
            window.updateTopBar();
        });

        try {
            const { data: { session } } = await supabase.auth.getSession();
            window.currentUser = session?.user ?? null;
        } catch(e) { console.warn('Supabase session error:', e); }
    }

    window.updateTopBar();
    window.renderVoteList();

    document.getElementById('auth-overlay').addEventListener('click', function(e) {
        if (e.target === this) window.closeAuthModal();
    });
});

// ══════════════════════════════════════════════════════
//  TOP BAR
// ══════════════════════════════════════════════════════
window.updateTopBar = function() {
    const userInfo = document.getElementById('user-info');
    const enterBtn = document.getElementById('enter-hub-btn');
    const nameEl   = document.getElementById('user-name-display');
    if (window.currentUser) {
        nameEl.textContent     = 'Hi, ' + window.currentUser.email.split('@')[0];
        userInfo.style.display = 'flex';
        enterBtn.style.display = 'none';
    } else {
        userInfo.style.display = 'none';
        enterBtn.style.display = 'inline-flex';
    }
};

// ══════════════════════════════════════════════════════
//  TAB NAVIGATION
// ══════════════════════════════════════════════════════
window.switchTab = function(tab) {
    document.querySelectorAll('.tab-screen').forEach(s => s.classList.remove('active'));
    document.querySelectorAll('.nav-btn').forEach(b => b.classList.remove('active'));
    const screen = document.getElementById('tab-' + tab);
    if (screen) screen.classList.add('active');
    const btn = document.querySelector('.nav-btn[data-tab="' + tab + '"]');
    if (btn) btn.classList.add('active');
};

// ══════════════════════════════════════════════════════
//  AUTH MODAL
// ══════════════════════════════════════════════════════
window.openAuthModal = function() {
    document.getElementById('auth-overlay').classList.remove('hidden');
    document.getElementById('auth-email').value    = '';
    document.getElementById('auth-password').value = '';
    window.hideAuthError();
};

window.closeAuthModal = function() {
    document.getElementById('auth-overlay').classList.add('hidden');
};

window.toggleAuthMode = function() {
    window.isLoginMode = !window.isLoginMode;
    document.getElementById('auth-title').textContent       = window.isLoginMode ? 'Sign in' : 'Create account';
    document.querySelector('#auth-overlay .auth-submit-btn').textContent = window.isLoginMode ? 'Sign In' : 'Sign Up';
    document.getElementById('auth-toggle-text').textContent = window.isLoginMode ? 'New here?' : 'Already have an account?';
    document.getElementById('auth-toggle-btn').textContent  = window.isLoginMode ? 'Create an account' : 'Sign in';
    window.hideAuthError();
};

window.showAuthError = function(msg) {
    const el = document.getElementById('auth-error');
    el.textContent   = msg;
    el.style.display = 'block';
};

window.hideAuthError = function() {
    document.getElementById('auth-error').style.display = 'none';
};

window.handleAuth = async function() {
    const email    = document.getElementById('auth-email').value.trim();
    const password = document.getElementById('auth-password').value;
    const btn      = document.querySelector('#auth-overlay .auth-submit-btn');

    if (!email || !password) { window.showAuthError('Please fill in all fields.'); return; }
    if (!supabase)           { window.showAuthError('Auth service unavailable.'); return; }

    btn.textContent = 'Please wait...'; btn.disabled = true; window.hideAuthError();

    const fn = window.isLoginMode
        ? supabase.auth.signInWithPassword({ email, password })
        : supabase.auth.signUp({ email, password });
    const { data, error } = await fn;

    if (error) {
        window.showAuthError((window.isLoginMode ? 'Login' : 'Sign up') + ' failed: ' + error.message);
    } else {
        window.currentUser = data.user;
        window.updateTopBar();
        window.closeAuthModal();
    }
    btn.textContent = window.isLoginMode ? 'Sign In' : 'Sign Up';
    btn.disabled    = false;
};

window.handleGoogleSignIn = async function() {
    if (!supabase) return;
    const { error } = await supabase.auth.signInWithOAuth({
        provider: 'google',
        options: { queryParams: { access_type: 'offline', prompt: 'consent' } },
    });
    if (error) window.showAuthError('Google sign-in failed: ' + error.message);
};

window.handleSignOut = async function() {
    if (supabase) await supabase.auth.signOut();
    window.currentUser = null;
    window.updateTopBar();
};

// ══════════════════════════════════════════════════════
//  VOTE SCREEN
// ══════════════════════════════════════════════════════
window.renderVoteList = function() {
    const container = document.getElementById('vote-list');
    if (!container) return;
    container.innerHTML = '';

    awardCategories.forEach(cat => {
        const hasVoted   = window.votes[cat.id] !== undefined;
        const isExpanded = window.expandedCategory === cat.id;
        const catEl      = document.createElement('div');
        catEl.className  = 'vote-category';

        catEl.innerHTML = `
            <button class="vote-category-header" onclick="window.toggleCategory('${cat.id}')">
                <span class="vote-category-title ${hasVoted ? 'voted' : ''}">${cat.title}</span>
                <span class="vote-toggle">${isExpanded ? '−' : '+'}</span>
            </button>
            <div class="vote-nominees ${isExpanded ? 'open' : ''}">
                ${mockNominees.map(n => {
                    const sel = window.votes[cat.id] === n.id;
                    const dis = hasVoted && !sel;
                    return `<div class="nominee-row">
                        <span class="nominee-name ${sel ? 'voted' : ''}">${n.name}</span>
                        <button class="vote-btn ${sel ? 'voted-btn' : ''}" onclick="window.castVote('${cat.id}','${n.id}')" ${dis ? 'disabled' : ''}>${sel ? '✓ VOTED' : 'VOTE'}</button>
                    </div>`;
                }).join('')}
            </div>`;

        container.appendChild(catEl);
    });
};

window.toggleCategory = function(id) {
    window.expandedCategory = window.expandedCategory === id ? null : id;
    window.renderVoteList();
};

window.castVote = function(categoryId, nomineeId) {
    if (!window.currentUser) { window.openAuthModal(); return; }
    window.votes[categoryId] = nomineeId;
    setTimeout(() => {
        if (window.expandedCategory === categoryId) window.expandedCategory = null;
        window.renderVoteList();
    }, 700);
    window.renderVoteList();
};

// ══════════════════════════════════════════════════════
//  NOMINATE
// ══════════════════════════════════════════════════════
window.submitNomination = function() {
    const name = document.getElementById('nom-name').value.trim();
    const cat  = document.getElementById('nom-category').value;
    const err  = document.getElementById('nominate-error');
    const suc  = document.getElementById('nominate-success');
    err.style.display = 'none'; suc.style.display = 'none';

    if (!name) { err.textContent = "Please enter the nominee's name."; err.style.display = 'block'; return; }
    if (!cat)  { err.textContent = 'Please select a category.'; err.style.display = 'block'; return; }
    if (!window.currentUser) { window.openAuthModal(); return; }

    suc.style.display = 'flex';
    ['nom-name','nom-category','nom-handle','nom-reason'].forEach(id => document.getElementById(id).value = '');
};

// ══════════════════════════════════════════════════════
//  REGISTER
// ══════════════════════════════════════════════════════
window.submitRegistration = function() {
    const name  = document.getElementById('reg-name').value.trim();
    const email = document.getElementById('reg-email').value.trim();
    const type  = document.getElementById('reg-type').value;
    const err   = document.getElementById('register-error');
    const suc   = document.getElementById('register-success');
    err.style.display = 'none'; suc.style.display = 'none';

    if (!name)  { err.textContent = 'Please enter your name.';  err.style.display = 'block'; return; }
    if (!email) { err.textContent = 'Please enter your email.'; err.style.display = 'block'; return; }
    if (!type)  { err.textContent = 'Please select a type.';    err.style.display = 'block'; return; }
    if (!window.currentUser) { window.openAuthModal(); return; }

    suc.style.display = 'flex';
    ['reg-name','reg-email','reg-phone','reg-dept','reg-type'].forEach(id => document.getElementById(id).value = '');
};

// ══════════════════════════════════════════════════════
//  CONTACT
// ══════════════════════════════════════════════════════
window.submitContact = function() {
    const name = document.getElementById('contact-name').value.trim();
    const email = document.getElementById('contact-email').value.trim();
    const msg  = document.getElementById('contact-message').value.trim();
    const err  = document.getElementById('contact-error');
    const suc  = document.getElementById('contact-success');
    err.style.display = 'none'; suc.style.display = 'none';

    if (!name || !email || !msg) {
        err.textContent = 'Please fill out all required fields.';
        err.style.display = 'block';
        return;
    }
    suc.style.display = 'flex';
    ['contact-name','contact-email','contact-subject','contact-message'].forEach(id => document.getElementById(id).value = '');
};

// ══════════════════════════════════════════════════════
//  ADMIN PANEL
// ══════════════════════════════════════════════════════
window.openAdminPanel  = function() { document.getElementById('admin-panel').classList.add('open'); };
window.closeAdminPanel = function() { document.getElementById('admin-panel').classList.remove('open'); };

window.switchAdminTab = function(tab, btn) {
    document.querySelectorAll('.admin-tab-pane').forEach(p => p.classList.remove('active'));
    document.querySelectorAll('.admin-tab').forEach(b => b.classList.remove('active'));
    const pane = document.getElementById('adm-tab-' + tab);
    if (pane) pane.classList.add('active');
    if (btn)  btn.classList.add('active');
};

window.postDispatch = function() {
    const headline = document.getElementById('adm-headline').value.trim();
    const message  = document.getElementById('adm-message').value.trim();
    const msgEl    = document.getElementById('adm-dispatch-msg');

    if (!headline || !message) {
        msgEl.textContent   = '⚠️ Please fill in headline and message.';
        msgEl.style.color   = '#E3004F';
        msgEl.style.display = 'block';
        return;
    }

    msgEl.textContent   = '✅ Dispatch posted!';
    msgEl.style.color   = '#16a34a';
    msgEl.style.display = 'block';

    const list = document.getElementById('dispatch-list');
    if (list) {
        const last = list.querySelector('.no-border');
        if (last) last.classList.remove('no-border');
        const div = document.createElement('div');
        div.className = 'dispatch-item no-border';
        div.innerHTML = `<p><strong>${headline}:</strong> ${message}</p><span class="dispatch-time">Just now</span>`;
        list.appendChild(div);
    }

    document.getElementById('adm-headline').value = '';
    document.getElementById('adm-message').value  = '';
    setTimeout(() => { msgEl.style.display = 'none'; }, 3000);
};
