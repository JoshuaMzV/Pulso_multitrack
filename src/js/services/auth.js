import { state } from '../state/store.js';
import { loadSongsAndSetlists } from './catalog.js';
import { say } from '../ui/show.js';

const authTokenKey = 'pulso_auth_token';
let sessionToken;


export function getAuthToken() {
  if (sessionToken !== undefined) return sessionToken;
  try {
    return localStorage.getItem(authTokenKey) || '';
  } catch (_) {
    return '';
  }
}



export function setAuthToken(token) {
  try {
    if (token) localStorage.setItem(authTokenKey, token);
    else localStorage.removeItem(authTokenKey);
    sessionToken = undefined;
  } catch (_) {
    // Algunos navegadores bloquean el almacenamiento, pero permiten autenticar la pestaña.
    sessionToken = token || '';
  }
}


// Iniciar verificación al cargar

export async function checkAuthStatus() {
  // Limpiar cualquier clave global antigua sin aislamiento de grupo
  try { localStorage.removeItem('pulso_saved_setlists'); } catch (_) {}

  const token = getAuthToken();
  if (!token) {
    window.CURRENT_USER = null;
    applyUserUI(null);
    if (typeof loadSongsAndSetlists === 'function') await loadSongsAndSetlists();
    openAuthModal('login');
    return;
  }

  try {
    const res = await fetch('/api/auth/me', {
      headers: { 'Authorization': `Bearer ${token}` },
      cache: 'no-store'
    });
    if (!res.ok) throw new Error('Sesión inválida');
    const data = await res.json();
    if (data.authenticated && data.user) {
      window.CURRENT_USER = data.user;
      applyUserUI(data.user);
      if (typeof loadSongsAndSetlists === 'function') await loadSongsAndSetlists();
    } else {
      setAuthToken(null);
      window.CURRENT_USER = null;
      applyUserUI(null);
      if (typeof loadSongsAndSetlists === 'function') await loadSongsAndSetlists();
      openAuthModal('login');
    }
  } catch (err) {
    console.warn("No se pudo verificar la sesión:", err);
    setAuthToken(null);
    window.CURRENT_USER = null;
    applyUserUI(null);
    if (typeof loadSongsAndSetlists === 'function') await loadSongsAndSetlists();
    openAuthModal('login');
  }
}



export function applyUserUI(user) {
  const avatar = document.querySelector('#roleToggleBtn .account-avatar');
  if (avatar) avatar.textContent = user?.username ? user.username.slice(0, 2).toUpperCase() : '·';
  const roleLabel = document.getElementById('roleLabel');
  const roleBadge = document.getElementById('roleBadge');
  const udUsername = document.getElementById('udUsername');
  const udGroupText = document.getElementById('udGroupText');
  const udRoleBadge = document.getElementById('udRoleBadge');
  const udBtnLogin = document.getElementById('udBtnLogin');
  const udBtnRegister = document.getElementById('udBtnRegister');
  const udBtnInvites = document.getElementById('udBtnInvites');
  const udBtnMemberInvite = document.getElementById('udBtnMemberInvite');
  const udBtnGroup = document.getElementById('udBtnGroup');
  const udBtnLogout = document.getElementById('udBtnLogout');
  const udLogoutDivider = document.getElementById('udLogoutDivider');
  const openUploadBtn = document.getElementById('openUploadBtn');
  const roleCrown = document.getElementById('roleCrown');
  const udCrown = document.getElementById('udCrown');

  if (user) {
    const roleUpper = user.role === 'admin' ? 'ADMIN' : 'USER';
    if (roleLabel) roleLabel.textContent = `@${user.username}`;
    const leadership = user.leadership_level || 'member';
    const crownText = leadership === 'leader' ? '♛' : leadership === 'subleader' ? '♕' : '';
    if (roleCrown) {
      roleCrown.textContent = crownText;
      roleCrown.className = `user-crown ${leadership}`;
      roleCrown.title = leadership === 'leader' ? 'Líder general' : leadership === 'subleader' ? 'Sublíder' : '';
    }
    if (udCrown) {
      udCrown.textContent = crownText;
      udCrown.className = `user-crown ${leadership}`;
    }
    if (roleBadge) {
      roleBadge.textContent = roleUpper;
      roleBadge.className = `role-badge ${user.role.toLowerCase()}`;
    }
    if (udUsername) udUsername.textContent = user.username;
    if (udGroupText) udGroupText.textContent = user.role === 'admin' ? 'Administración global (Ve todo)' : (user.group_name ? `Grupo: ${user.group_name}` : 'Sin grupo');
    if (udRoleBadge) {
      udRoleBadge.textContent = roleUpper;
      udRoleBadge.className = `role-badge ${user.role.toLowerCase()}`;
    }

    if (udBtnLogin) udBtnLogin.style.display = 'none';
    if (udBtnRegister) udBtnRegister.style.display = 'none';
    if (udBtnLogout) udBtnLogout.style.display = 'flex';
    if (udLogoutDivider) udLogoutDivider.style.display = 'block';

    // Mostrar botón de invitaciones solo si es admin
    if (udBtnInvites) {
      udBtnInvites.style.display = (user.role === 'admin') ? 'flex' : 'none';
    }
    if (udBtnMemberInvite) {
      udBtnMemberInvite.style.display = ['leader', 'subleader'].includes(leadership) && user.role !== 'admin' ? 'flex' : 'none';
    }
    if (udBtnGroup) udBtnGroup.style.display = user.role === 'user' ? 'flex' : 'none';

    // Todos los usuarios autenticados pueden subir y controlar multitracks de su grupo.
    if (openUploadBtn) {
      openUploadBtn.style.opacity = '1';
      openUploadBtn.title = 'Subir nueva canción a tu grupo';
      openUploadBtn.onclick = null;
    }
  } else {
    // Modo invitado / No autenticado (Todo vacío)
    if (roleLabel) roleLabel.textContent = 'INVITADO';
    if (roleBadge) {
      roleBadge.textContent = 'LOGIN';
      roleBadge.className = 'role-badge guest';
    }
    if (udUsername) udUsername.textContent = 'Invitado';
    if (udGroupText) udGroupText.textContent = 'Inicia sesión para ver tu grupo';
    if (roleCrown) roleCrown.textContent = '';
    if (udCrown) udCrown.textContent = '';
    if (udRoleBadge) {
      udRoleBadge.textContent = 'SIN SESIÓN';
      udRoleBadge.className = 'role-badge guest';
    }

    if (udBtnLogin) udBtnLogin.style.display = 'flex';
    if (udBtnRegister) udBtnRegister.style.display = 'flex';
    if (udBtnInvites) udBtnInvites.style.display = 'none';
    if (udBtnMemberInvite) udBtnMemberInvite.style.display = 'none';
    if (udBtnGroup) udBtnGroup.style.display = 'none';
    const udBtnGroups = document.getElementById('udBtnGroups');
    if (udBtnGroups) udBtnGroups.style.display = 'none';
    if (udBtnLogout) udBtnLogout.style.display = 'none';
    if (udLogoutDivider) udLogoutDivider.style.display = 'none';

    if (openUploadBtn) {
      openUploadBtn.style.opacity = '0.6';
      openUploadBtn.title = 'Inicia sesión para subir canciones a tu grupo';
      openUploadBtn.onclick = null;
    }
  }

  const udBtnGroups = document.getElementById('udBtnGroups');
  if (udBtnGroups) udBtnGroups.style.display = user && user.role === 'admin' ? 'flex' : 'none';
  if (window.lucide) lucide.createIcons();
}



export function toggleUserDropdown() {
  const dd = document.getElementById('userDropdown');
  if (!dd) return;
  if (dd.classList.contains('open')) { closeUserDropdown(); return; }
  // Fuera del sidebar: sus recortes y contextos de apilamiento no afectan al menú.
  document.body.appendChild(dd);
  dd.classList.add('account-menu-overlay', 'open');
  positionUserDropdown();
  document.getElementById('roleToggleBtn')?.setAttribute('aria-expanded', 'true');
}

function positionUserDropdown() {
  const dd = document.getElementById('userDropdown');
  const button = document.getElementById('roleToggleBtn');
  if (!dd?.classList.contains('open') || !button) return;
  const rect = button.getBoundingClientRect();
  const viewport = window.visualViewport;
  const left = viewport?.offsetLeft || 0, top = viewport?.offsetTop || 0;
  const width = viewport?.width || window.innerWidth, height = viewport?.height || window.innerHeight;
  const margin = 8;
  dd.style.width = `${Math.min(290, width - margin * 2)}px`;
  dd.style.maxHeight = `${Math.max(80, height - margin * 2)}px`;
  const menuHeight = dd.getBoundingClientRect().height;
  const above = rect.top - menuHeight - margin;
  const desiredTop = button.closest('#sidebarAccountSlot') ? above : rect.bottom + margin;
  dd.style.left = `${Math.max(left + margin, Math.min(rect.left, left + width - dd.offsetWidth - margin))}px`;
  dd.style.top = `${Math.max(top + margin, Math.min(desiredTop, top + height - menuHeight - margin))}px`;
}


export function closeUserDropdown() {
  const dd = document.getElementById('userDropdown');
  if (dd) dd.classList.remove('open');
  document.getElementById('roleToggleBtn')?.setAttribute('aria-expanded', 'false');
}


// ---------- MODAL AUTH (LOGIN & REGISTER) ----------

export function openAuthModal(tab = 'login') {
  document.getElementById('uploadModal')?.classList.remove('open');
  document.getElementById('addSongChoiceModal')?.classList.remove('open');
  document.getElementById('setlistModal')?.classList.remove('open');
  const modal = document.getElementById('authModal');
  if (modal) modal.classList.add('open');
  switchAuthTab(tab);
  hideAuthAlert();
  if (window.lucide) lucide.createIcons();
}



export function closeAuthModal() {
  const modal = document.getElementById('authModal');
  if (modal) modal.classList.remove('open');
  hideAuthAlert();
}



export function switchAuthTab(tab) {
  const tabLogin = document.getElementById('authTabLogin');
  const tabRegister = document.getElementById('authTabRegister');
  const formLogin = document.getElementById('formAuthLogin');
  const formRegister = document.getElementById('formAuthRegister');

  if (tab === 'login') {
    tabLogin.classList.add('active');
    tabRegister.classList.remove('active');
    formLogin.style.display = 'block';
    formRegister.style.display = 'none';
  } else {
    tabLogin.classList.remove('active');
    tabRegister.classList.add('active');
    formLogin.style.display = 'none';
    formRegister.style.display = 'block';
    loadRegistrationGroups();
    const codeEl = document.getElementById('regInviteCode');
    if (codeEl && codeEl.value.trim()) {
      checkInviteCodeStatus(codeEl.value.trim());
    }
  }
  hideAuthAlert();
}



export async function loadRegistrationGroups() {
  const select = document.getElementById('regGroupSelect');
  if (!select) return;
  select.innerHTML = '<option value="">Selecciona un grupo existente</option>';
  try {
    const res = await fetch('/api/groups', { cache: 'no-store' });
    const data = await res.json();
    (data.groups || []).forEach(group => {
      const option = document.createElement('option');
      option.value = group.id;
      option.textContent = group.name;
      select.appendChild(option);
    });
  } catch (_) {}
}



export function onInviteCodeInput(val) {
  clearTimeout(state.inviteCheckTimer);
  const code = (val || '').trim().toUpperCase();
  if (code.length < 4) {
    window.DETECTED_INVITE = null;
    const orgField = document.getElementById('regOrgField');
    if (orgField) orgField.style.display = 'block';
    return;
  }
  state.inviteCheckTimer = setTimeout(() => checkInviteCodeStatus(code), 250);
}



export async function checkInviteCodeStatus(code) {
  const cleanCode = (code || '').trim().toUpperCase();
  const orgField = document.getElementById('regOrgField');
  const hintEl = document.getElementById('regInviteHint');
  if (!cleanCode) return null;
  try {
    const res = await fetch(`/api/auth/check-invite?code=${encodeURIComponent(cleanCode)}`, { cache: 'no-store' });
    const data = await res.json();
    if (data.valid) {
      window.DETECTED_INVITE = data;
      if (data.role === 'admin') {
        if (orgField) orgField.style.display = 'none';
        if (hintEl) {
          hintEl.style.color = 'var(--green)';
          hintEl.textContent = '✓ Código de Administrador Global verificado (acceso total).';
        }
      } else if (data.group_id) {
        if (orgField) orgField.style.display = 'none';
        if (hintEl) {
          hintEl.style.color = 'var(--green)';
          hintEl.textContent = `✓ Invitación directa al grupo: ${data.group_name || data.group_id}`;
        }
      } else {
        if (orgField) orgField.style.display = 'block';
        if (hintEl) {
          hintEl.style.color = 'var(--amber)';
          hintEl.textContent = '✓ Código válido. Elige si crearás un grupo nuevo o te unirás a uno existente.';
        }
      }
      return data;
    } else {
      window.DETECTED_INVITE = null;
      if (orgField) orgField.style.display = 'block';
      if (hintEl && cleanCode.length >= 8) {
        hintEl.style.color = 'var(--coral)';
        hintEl.textContent = data.error || 'Código no válido.';
      }
      return null;
    }
  } catch (_) {
    return null;
  }
}



export function updateRegistrationGroupMode() {
  const mode = document.querySelector('input[name="regGroupMode"]:checked')?.value;
  const create = document.getElementById('regCreateGroupFields');
  const join = document.getElementById('regJoinGroupFields');
  if (create) create.style.display = mode === 'create' ? 'block' : 'none';
  if (join) {
    join.style.display = mode === 'join' ? 'block' : 'none';
    if (mode === 'join') loadRegistrationGroups();
  }
}



export function showAuthAlert(msg, type = 'error') {
  const el = document.getElementById('authAlert');
  if (el) {
    el.textContent = msg;
    el.className = `auth-alert ${type}`;
    el.style.display = 'block';
  }
}



export function hideAuthAlert() {
  const el = document.getElementById('authAlert');
  if (el) el.style.display = 'none';
}



export async function handleAuthLogin(e) {
  e.preventDefault();
  const u = document.getElementById('loginUsername').value.trim();
  const p = document.getElementById('loginPassword').value.trim();
  const btn = document.getElementById('btnLoginSubmit');

  if (!u || !p) {
    showAuthAlert('Por favor llena todos los campos.');
    return;
  }

  btn.disabled = true;
  btn.innerHTML = '<span>Verificando...</span>';

  try {
    const res = await fetch('/api/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username: u, password: p })
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || 'Credenciales incorrectas');

    setAuthToken(data.token);
    window.CURRENT_USER = data.user;
    applyUserUI(data.user);
    if (typeof loadSongsAndSetlists === 'function') await loadSongsAndSetlists();
    showAuthAlert(data.message || '¡Sesión iniciada con éxito!', 'success');
    say(`BIENVENIDO, @${data.user.username.toUpperCase()}`);
    if (data.user.must_change_password) openPasswordChangeModal();

    setTimeout(() => {
      closeAuthModal();
      btn.disabled = false;
      btn.innerHTML = '<i data-lucide="log-in"></i><span>ENTRAR</span>';
      if (window.lucide) lucide.createIcons();
    }, 600);
  } catch (err) {
    showAuthAlert(err.message, 'error');
    btn.disabled = false;
    btn.innerHTML = '<i data-lucide="log-in"></i><span>ENTRAR</span>';
    if (window.lucide) lucide.createIcons();
  }
}



export async function handleAuthRegister(e) {
  e.preventDefault();
  const code = document.getElementById('regInviteCode').value.trim().toUpperCase();
  const u = document.getElementById('regUsername').value.trim();
  const p = document.getElementById('regPassword').value.trim();
  let groupMode = document.querySelector('input[name="regGroupMode"]:checked')?.value || 'none';
  let groupId = document.getElementById('regGroupSelect')?.value || '';
  const groupName = document.getElementById('regGroupName')?.value.trim() || '';
  const btn = document.getElementById('btnRegisterSubmit');

  if (!code || !u || !p) {
    showAuthAlert('Por favor ingresa el código, usuario y contraseña.');
    return;
  }

  const inviteInfo = window.DETECTED_INVITE || await checkInviteCodeStatus(code);
  const isAdminCode = inviteInfo && inviteInfo.role === 'admin';
  const hasPreassignedGroup = inviteInfo && inviteInfo.group_id;

  if (!isAdminCode && !hasPreassignedGroup) {
    if (!groupMode || groupMode === 'none' || (groupMode === 'create' && !groupName) || (groupMode === 'join' && !groupId)) {
      showAuthAlert('Elige si vas a crear un grupo nuevo o unirte a uno existente.');
      return;
    }
  } else if (hasPreassignedGroup) {
    groupMode = 'join';
    groupId = inviteInfo.group_id;
  } else if (isAdminCode) {
    groupMode = 'none';
  }

  btn.disabled = true;
  btn.innerHTML = '<span>Registrando...</span>';

  try {
    const res = await fetch('/api/auth/register', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username: u, password: p, invite_code: code, group_mode: groupMode, group_id: groupId, group_name: groupName })
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || 'Error al canjear el código');

    setAuthToken(data.token);
    window.CURRENT_USER = data.user;
    applyUserUI(data.user);
    if (typeof loadSongsAndSetlists === 'function') await loadSongsAndSetlists();
    showAuthAlert(data.message || '¡Cuenta creada con éxito!', 'success');
    say(`CUENTA CREADA: @${data.user.username.toUpperCase()} (${data.user.role.toUpperCase()})`);
    if (data.user.must_change_password) openPasswordChangeModal();

    setTimeout(() => {
      closeAuthModal();
      btn.disabled = false;
      btn.innerHTML = '<i data-lucide="check-circle-2"></i><span>CREAR CUENTA</span>';
      if (window.lucide) lucide.createIcons();
    }, 800);
  } catch (err) {
    showAuthAlert(err.message, 'error');
    btn.disabled = false;
    btn.innerHTML = '<i data-lucide="check-circle-2"></i><span>CREAR CUENTA</span>';
    if (window.lucide) lucide.createIcons();
  }
}



export async function logoutUser() {
  const token = getAuthToken();
  if (token) {
    try {
      await fetch('/api/auth/logout', {
        method: 'POST',
        headers: { 'Authorization': `Bearer ${token}` }
      });
    } catch (_) {}
  }
  setAuthToken(null);
  window.CURRENT_USER = null;
  applyUserUI(null);
  if (typeof loadSongsAndSetlists === 'function') await loadSongsAndSetlists();
  say('SESIÓN CERRADA — MODO INVITADO');
}



export function openPasswordChangeModal() {
  const modal = document.getElementById('passwordChangeModal');
  if (modal) modal.classList.add('open');
}



export function closePasswordChangeModal() {
  const modal = document.getElementById('passwordChangeModal');
  if (modal && window.CURRENT_USER?.must_change_password) return;
  if (modal) modal.classList.remove('open');
}



export async function handlePasswordChange(event) {
  event.preventDefault();
  const input = document.getElementById('newPasswordInput');
  const feedback = document.getElementById('passwordChangeFeedback');
  const newPassword = input.value.trim();
  try {
    const res = await fetch('/api/auth/change-password', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${getAuthToken()}` },
      body: JSON.stringify({ new_password: newPassword })
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || 'No se pudo cambiar la contraseña.');
    window.CURRENT_USER.must_change_password = false;
    feedback.textContent = data.message;
    feedback.style.display = 'block';
    setTimeout(() => document.getElementById('passwordChangeModal')?.classList.remove('open'), 700);
  } catch (error) {
    feedback.textContent = error.message;
    feedback.style.display = 'block';
    feedback.style.color = 'var(--coral)';
  }
}



export async function createMemberInvite() {
  try {
    const res = await fetch('/api/groups/invite', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${getAuthToken()}` },
      body: '{}'
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || 'No se pudo crear la invitación.');
    prompt('Comparte este código con el miembro:', data.invite.code);
  } catch (error) {
    alert(error.message);
  }
}



export async function openCurrentGroupModal() {
  const modal = document.getElementById('currentGroupModal');
  const container = document.getElementById('currentGroupContent');
  if (modal) modal.classList.add('open');
  if (!container) return;
  container.innerHTML = '<div style="color:var(--mut);">Cargando grupo...</div>';
  try {
    const res = await fetch('/api/groups/current', { headers: { 'Authorization': `Bearer ${getAuthToken()}` } });
    if (!res.ok) throw new Error(`No se pudo cargar el grupo (HTTP ${res.status}). Reinicia el servidor local.`);
    const contentType = res.headers.get('content-type') || '';
    if (!contentType.includes('application/json')) throw new Error('El servidor devolvió una página en lugar de datos del grupo.');
    const data = await res.json();
    if (!data.group) {
      container.innerHTML = '<div style="color:var(--mut);">No perteneces a ningún grupo.</div>';
      return;
    }
    const group = data.group;
    const canAssign = window.CURRENT_USER?.leadership_level === 'leader';
    container.innerHTML = `<div class="group-summary"><strong>${group.name}</strong><small>${group.id}</small></div>${group.members.map(member => {
      const crown = member.leadership_level === 'leader' ? '♛' : member.leadership_level === 'subleader' ? '♕' : '';
      const label = member.leadership_level === 'leader' ? 'LÍDER' : member.leadership_level === 'subleader' ? 'SUBLÍDER' : 'USER';
      const action = canAssign && member.leadership_level !== 'leader' ? `<button class="inv-copy-btn" onclick="setSubleader(${member.id}, '${member.leadership_level === 'subleader' ? 'member' : 'subleader'}')">${member.leadership_level === 'subleader' ? 'Quitar sublíder' : 'Hacer sublíder'}</button>` : '';
      return `<div class="current-member-row"><span class="user-crown ${member.leadership_level}">${crown}</span><strong>${member.username}</strong><span>${label}</span>${action}</div>`;
    }).join('')}`;
  } catch (error) {
    container.innerHTML = `<div style="color:var(--coral);">${error.message}</div>`;
  }
}



export function closeCurrentGroupModal() {
  document.getElementById('currentGroupModal')?.classList.remove('open');
}



export async function setSubleader(userId, level) {
  const res = await fetch(`/api/groups/members/${userId}/leadership`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${getAuthToken()}` },
    body: JSON.stringify({ leadership_level: level })
  });
  const data = await res.json();
  if (!res.ok) return alert(data.error || 'No se pudo actualizar el sublíder.');
  openCurrentGroupModal();
}



export async function openAdminGroupsModal() {
  const modal = document.getElementById('adminGroupsModal');
  if (modal) modal.classList.add('open');
  const container = document.getElementById('adminGroupsList');
  if (!container) return;
  container.innerHTML = '<div style="color:var(--mut);">Cargando grupos...</div>';
  try {
    const res = await fetch('/api/admin/groups', { headers: { 'Authorization': `Bearer ${getAuthToken()}` } });
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || 'No autorizado.');
    container.innerHTML = (data.groups || []).map((group, index) => `
      <details class="admin-group-row" ${index === 0 ? 'open' : ''}>
        <summary><span><strong>${group.name}</strong><small>${group.id}</small></span><b>${group.members.length} usuarios</b></summary>
        <div class="admin-group-members">${group.members.map(member => `
          <div class="admin-member-row"><span class="user-crown ${member.leadership_level}">${member.leadership_level === 'leader' ? '♛' : member.leadership_level === 'subleader' ? '♕' : ''}</span><strong>${member.username}</strong><span>${member.leadership_level === 'leader' ? 'LÍDER' : member.leadership_level === 'subleader' ? 'SUBLÍDER' : 'USER'}</span><button class="inv-copy-btn" onclick="resetUserPassword(${member.id}, '${member.username}')">Restablecer</button><button class="inv-copy-btn" onclick="deleteUserAccount(${member.id}, '${member.username}')">Eliminar</button></div>
        `).join('')}</div>
      </details>`).join('') || '<div style="color:var(--mut);">Todavía no hay grupos creados.</div>';
  } catch (error) {
    container.innerHTML = `<div style="color:var(--coral);">${error.message}</div>`;
  }
}



export function closeAdminGroupsModal() {
  document.getElementById('adminGroupsModal')?.classList.remove('open');
}



export async function resetUserPassword(userId, username) {
  if (!confirm(`¿Restablecer la contraseña de @${username}?`)) return;
  const res = await fetch(`/api/admin/users/${userId}/reset-password`, { method: 'POST', headers: { 'Authorization': `Bearer ${getAuthToken()}` } });
  const data = await res.json();
  if (!res.ok) return alert(data.error || 'No se pudo restablecer.');
  prompt(`Código temporal para @${username}. Deberá cambiarlo al entrar:`, data.temporary_password);
}



export async function deleteUserAccount(userId, username) {
  if (!confirm(`¿Eliminar permanentemente la cuenta @${username}?`)) return;
  const res = await fetch(`/api/admin/users/${userId}`, { method: 'DELETE', headers: { 'Authorization': `Bearer ${getAuthToken()}` } });
  const data = await res.json();
  if (!res.ok) return alert(data.error || 'No se pudo eliminar.');
  openAdminGroupsModal();
}


// ---------- GESTIÓN DE INVITACIONES (ADMIN) ----------

export function openAdminInvitesModal() {
  const modal = document.getElementById('adminInvitesModal');
  if (modal) modal.classList.add('open');
  loadAdminInvites();
  if (window.lucide) lucide.createIcons();
}



export function closeAdminInvitesModal() {
  const modal = document.getElementById('adminInvitesModal');
  if (modal) modal.classList.remove('open');
}



export async function loadAdminInvites() {
  const token = getAuthToken();
  const tbody = document.getElementById('invitesTableBody');
  if (!tbody) return;

  tbody.innerHTML = '<tr><td colspan="5" style="text-align:center; color:var(--mut);">Cargando invitaciones...</td></tr>';

  try {
    const res = await fetch('/api/admin/invites', {
      headers: { 'Authorization': `Bearer ${token}` }
    });
    if (!res.ok) throw new Error('No autorizado o error al cargar');
    const data = await res.json();
    const list = (data.invites || []).filter(inv => window.inviteFilter === 'used' ? inv.is_used : !inv.is_used);

    if (list.length === 0) {
      tbody.innerHTML = '<tr><td colspan="5" style="text-align:center; color:var(--mut);">No hay invitaciones creadas.</td></tr>';
      return;
    }

    let rows = '';
    list.forEach(inv => {
      const isUsed = inv.is_used;
      const statusBadge = isUsed 
        ? `<span style="color:var(--mut);">Usado (@${inv.used_by})</span>`
        : `<span style="color:var(--green); font-weight:800;">DISPONIBLE</span>`;

      rows += `
        <tr>
          <td><span class="inv-code-pill">${inv.code}</span></td>
          <td><span class="role-badge ${inv.role}">${inv.role.toUpperCase()}</span></td>
          <td>${statusBadge}</td>
          <td style="color:var(--mut);">${inv.created_at ? inv.created_at.substring(0, 10) : '-'}</td>
          <td>
            <button class="inv-copy-btn" onclick="copyInviteCode('${inv.code}', this)" title="Copiar código">
              Copiar
            </button>
          </td>
        </tr>
      `;
    });
    tbody.innerHTML = rows;
  } catch (err) {
    tbody.innerHTML = `<tr><td colspan="5" style="text-align:center; color:var(--coral);">${err.message}</td></tr>`;
  }
}



export function setInviteFilter(filter) {
  window.inviteFilter = filter;
  document.querySelectorAll('.invite-filter-tab').forEach(tab => tab.classList.toggle('active', tab.dataset.filter === filter));
  loadAdminInvites();
}



export async function generateInviteCode() {
  const token = getAuthToken();
  const role = document.getElementById('inviteRoleSelect').value;
  const groupName = document.getElementById('inviteGroupName')?.value.trim() || '';
  const btn = document.getElementById('btnGenInvite');
  const fb = document.getElementById('inviteGenFeedback');

  btn.disabled = true;
  btn.innerHTML = '<span>Generando...</span>';
  if (fb) fb.style.display = 'none';

  try {
    const res = await fetch('/api/admin/invite', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`
      },
      body: JSON.stringify({ role: role, group_name: groupName })
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || 'Error al generar código');

    if (fb) {
      fb.innerHTML = `¡Código generado con éxito: <strong style="color:var(--ink);">${data.invite.code}</strong> (${role.toUpperCase()})!`;
      fb.style.display = 'block';
    }
    loadAdminInvites();
  } catch (err) {
    alert(err.message);
  } finally {
    btn.disabled = false;
    btn.innerHTML = '<i data-lucide="plus-circle"></i><span>GENERAR</span>';
    if (window.lucide) lucide.createIcons();
  }
}



export function copyInviteCode(code, btn) {
  navigator.clipboard.writeText(code).then(() => {
    const originalText = btn.textContent;
    btn.textContent = '¡Copiado!';
    btn.style.color = 'var(--green)';
    btn.style.borderColor = 'var(--green)';
    setTimeout(() => {
      btn.textContent = originalText;
      btn.style.color = '';
      btn.style.borderColor = '';
    }, 1500);
  }).catch(() => {
    prompt("Copia este código de invitación:", code);
  });
}

export function initializeAuth() {

/* ==========================================================================
   LÓGICA CLIENTE: SISTEMA DE AUTENTICACIÓN Y ROLES RBAC (FASE 1)
   ========================================================================== */
window.CURRENT_USER = null;


// Cerrar dropdown al hacer clic fuera
document.addEventListener('click', (e) => {
  const wrapper = document.getElementById('userMenuWrapper');
  if (wrapper && !wrapper.contains(e.target) && !document.getElementById('userDropdown')?.contains(e.target)) {
    closeUserDropdown();
  }
});


// Listener en el botón de rol
window.addEventListener('resize', positionUserDropdown);
window.visualViewport?.addEventListener('resize', positionUserDropdown);
window.visualViewport?.addEventListener('scroll', positionUserDropdown);
document.addEventListener('keydown', e => { if (e.key === 'Escape') closeUserDropdown(); });
document.addEventListener('DOMContentLoaded', () => {
  const btn = document.getElementById('roleToggleBtn');
  if (btn) {
    btn.onclick = (e) => {
      e.stopPropagation();
      toggleUserDropdown();
    };
  }
  checkAuthStatus();
});


window.DETECTED_INVITE = null;

state.inviteCheckTimer = null;
}

