import { endpoints } from './config.js';
import { state } from '../state/store.js';
import { openAuthModal, getAuthToken } from './auth.js';
import { say, drawHeroWaveform } from '../ui/show.js';
import { saveCurrentSetlist, renderEditionSongList, renderStageSlider, switchSetlist, getSetlistStorageKey } from '../ui/setlists.js';
import { updateStemCountBadge } from '../ui/mixer.js';
import { loadRealStems } from '../audio/stems.js';
import { drawAllMeters } from '../ui/meters.js';



export function openServerUploadWizard() {
  if (!window.CURRENT_USER) {
    openAuthModal('login');
    if (typeof say === 'function') say('INICIA SESIÓN PARA SUBIR CANCIONES A TU GRUPO');
    return;
  }
  state.uploadTarget = 'cloud';
  resetUploadWizard();
  const titleEl = document.getElementById('uploadModalTitle');
  if (titleEl) {
    titleEl.innerHTML = '<span style="display:flex;align-items:center;gap:8px;"><i data-lucide="cloud" style="width:20px;height:20px;color:var(--amber);"></i> Subir Canción a la Nube (Servidor)</span>';
  }
  const finalizeBtn = document.querySelector('#uploadStep3 button.btn-amber');
  if (finalizeBtn) finalizeBtn.innerHTML = '<i data-lucide="cloud-upload" style="width:14px;height:14px;display:inline;vertical-align:middle;margin-right:4px;"></i> SUBIR A LA NUBE';
  state.uploadModal.classList.add('open');
  if (window.lucide) lucide.createIcons();
}


// --- GESTIÓN DE CANCIONES LOCALES Y CACHÉ NUBE -> LOCAL ---

export function normalizeTitle(str) {
  if (!str) return '';
  return str.normalize("NFD").replace(/[\u0300-\u036f]/g, "").trim().toLowerCase();
}



export function normalizeSongKeyClient(val) {
  if (!val) return '';
  return String(val)
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
}



export async function registerSongInCurrentGroup(songObj) {
  if (!window.CURRENT_USER || !songObj) return;
  try {
    await fetch('/api/groups/songs', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${getAuthToken()}`
      },
      body: JSON.stringify({
        id: songObj.id || songObj.folderId || null,
        folderId: songObj.folderId || null,
        title: songObj.title || null
      })
    });
  } catch (_) {}
}



export async function refreshLocalStatus() {
  state.LOCAL_DOWNLOADED_TITLES.clear();
  if (!window.CURRENT_USER) {
    state.LOCAL_BACKEND_SONGS = [];
    return;
  }

  // 1. Consultar backend local Flask (/api/songs) con token del usuario/grupo
  try {
    const res = await fetch('/api/songs', {
      headers: { 'Authorization': `Bearer ${getAuthToken()}` },
      cache: 'no-store'
    });
    if (res.ok) {
      state.LOCAL_BACKEND_SONGS = await res.json();
      if (Array.isArray(state.LOCAL_BACKEND_SONGS)) {
        state.LOCAL_BACKEND_SONGS.forEach(s => {
          if (s.title) state.LOCAL_DOWNLOADED_TITLES.add(normalizeTitle(s.title));
          if (s.id) state.LOCAL_DOWNLOADED_TITLES.add(normalizeTitle(s.id));
        });
      }
    }
  } catch (err) {
    console.log("Servidor local no disponible para /api/songs, continuando con IndexedDB:", err);
  }

  // 2. Consultar IndexedDB local
  try {
    const idbTitles = await state.CloudStorageCache.getAllStoredTitles();
    idbTitles.forEach(t => state.LOCAL_DOWNLOADED_TITLES.add(normalizeTitle(t)));
  } catch (err) {
    console.warn("Error leyendo IndexedDB:", err);
  }

  // 3. Consultar setlists en memoria que ya tengan folderId
  if (window.ALL_SETLISTS) {
    state.ALL_SETLISTS.forEach(sl => {
      if (sl && sl.songs) {
        sl.songs.forEach(s => {
          if (s.folderId && s.title) {
            state.LOCAL_DOWNLOADED_TITLES.add(normalizeTitle(s.title));
          }
        });
      }
    });
  }
}



export function isSongInLocal(song) {
  if (!song) return false;
  const nTitle = normalizeTitle(song.title);
  const nId = normalizeTitle(song.id);
  if (nTitle && state.LOCAL_DOWNLOADED_TITLES.has(nTitle)) return true;
  if (nId && state.LOCAL_DOWNLOADED_TITLES.has(nId)) return true;
  
  if (state.LOCAL_BACKEND_SONGS && state.LOCAL_BACKEND_SONGS.length > 0) {
    const found = state.LOCAL_BACKEND_SONGS.some(b => 
      normalizeTitle(b.title) === nTitle || 
      normalizeTitle(b.id) === nTitle || 
      normalizeTitle(b.id) === nId
    );
    if (found) return true;
  }
  return false;
}



export function openAddSongChoiceModal() {
  if (!window.CURRENT_USER) {
    openAuthModal('login');
    say('INICIA SESIÓN PARA GESTIONAR LAS CANCIONES DE TU GRUPO');
    return;
  }
  const modal = document.getElementById('addSongChoiceModal');
  document.getElementById('choiceViewSelector').style.display = 'grid';
  document.getElementById('choiceViewCloud').style.display = 'none';
  const titleEl = document.getElementById('addSongModalTitle');
  const subEl = document.getElementById('addSongModalSubtitle');
  if (titleEl) titleEl.innerText = 'AGREGAR CANCIÓN AL SETLIST';
  if (subEl) {
    subEl.innerText = window.CURRENT_USER.role === 'admin'
      ? 'Administración global: acceso a todas las canciones'
      : `Grupo: ${window.CURRENT_USER.group_name || window.CURRENT_USER.grupo_id}`;
  }
  if (modal) modal.classList.add('open');
  if (window.lucide) lucide.createIcons();
}



export function backToChoiceSelector() {
  document.getElementById('choiceViewSelector').style.display = 'grid';
  document.getElementById('choiceViewCloud').style.display = 'none';
  const titleEl = document.getElementById('addSongModalTitle');
  const subEl = document.getElementById('addSongModalSubtitle');
  if (titleEl) titleEl.innerText = 'AGREGAR CANCIÓN AL SETLIST';
  if (subEl) {
    subEl.innerText = window.CURRENT_USER && window.CURRENT_USER.role !== 'admin'
      ? `Grupo: ${window.CURRENT_USER.group_name || window.CURRENT_USER.grupo_id}`
      : 'Selecciona el origen de tus multitracks';
  }
  if (window.lucide) lucide.createIcons();
}



export async function openCloudCatalogView() {
  document.getElementById('choiceViewSelector').style.display = 'none';
  document.getElementById('choiceViewCloud').style.display = 'block';
  
  const titleEl = document.getElementById('addSongModalTitle');
  const subEl = document.getElementById('addSongModalSubtitle');
  const isAdmin = window.CURRENT_USER && window.CURRENT_USER.role === 'admin';
  if (titleEl) titleEl.innerText = isAdmin ? 'CATÁLOGO GLOBAL (ADMIN)' : 'CATÁLOGO DE TU GRUPO';
  if (subEl) {
    subEl.innerText = isAdmin
      ? 'Viendo todas las canciones de todos los grupos'
      : `Canciones disponibles para ${window.CURRENT_USER?.group_name || 'tu grupo'}`;
  }
  
  const searchInput = document.getElementById('cloudSearchInput');
  const clearBtn = document.getElementById('cloudSearchClearBtn');
  if (searchInput) searchInput.value = '';
  if (clearBtn) clearBtn.style.display = 'none';

  if (window.refreshLocalStatus) {
    await refreshLocalStatus();
  }
  if (window.lucide) lucide.createIcons();
  await fetchAndRenderCloudSongs();
}



export async function refreshCloudCatalog() {
  const btn = document.getElementById('btnRefreshCloudCatalog');
  if (btn) btn.style.transform = 'rotate(180deg)';
  await fetchAndRenderCloudSongs();
  setTimeout(() => { if (btn) btn.style.transform = 'none'; }, 400);
}



export async function fetchAndRenderCloudSongs() {
  const statusEl = document.getElementById('cloudCatalogStatus');
  const statusDot = document.getElementById('cloudServerStatusDot');
  const listEl = document.getElementById('cloudSongsList');
  const summaryEl = document.getElementById('cloudSearchSummary');
  const countBadge = document.getElementById('cloudSearchCountBadge');

  if (!window.CURRENT_USER) {
    state.cachedCloudSongs = [];
    if (listEl) {
      listEl.innerHTML = `
        <div style="text-align:center; padding:32px 16px; border:1px dashed var(--line2); border-radius:10px;">
          <h5 style="margin:0 0 6px; font-size:13px; font-weight:800; color:var(--ink);">Inicia sesión para ver tu catálogo</h5>
          <p style="font-size:11px; color:var(--mut); margin:0 0 14px;">Modo invitado activo. Las canciones se cargan según tu grupo.</p>
          <button type="button" class="btn btn-amber btn-sm" onclick="document.getElementById('addSongChoiceModal')?.classList.remove('open'); openAuthModal('login');">INICIAR SESIÓN</button>
        </div>
      `;
    }
    return;
  }

  if (statusEl) statusEl.innerText = 'Sincronizando...';
  if (statusDot) statusDot.style.background = '#E9A23B';
  if (summaryEl) summaryEl.innerText = 'Consultando canciones de tu grupo...';
  if (countBadge) countBadge.innerText = '';
  
  if (listEl) {
    listEl.innerHTML = `
      <div style="display:flex; flex-direction:column; align-items:center; justify-content:center; padding:36px 15px; color:var(--mut);">
        <i data-lucide="loader-2" style="width:28px; height:28px; color:var(--amber); animation: spin 1s linear infinite; margin-bottom:10px;"></i>
        <span style="font-size:12px; font-weight:700; color:var(--ink2);">Sincronizando biblioteca del grupo...</span>
      </div>
    `;
    if (window.lucide) lucide.createIcons();
  }

  try {
    // 1. Obtener permisos y lista de canciones del grupo desde el backend local
    let allAccess = window.CURRENT_USER.role === 'admin';
    let allowedGroupKeys = new Set();
    try {
      const grpRes = await fetch('/api/groups/songs', {
        headers: { 'Authorization': `Bearer ${getAuthToken()}` },
        cache: 'no-store'
      });
      if (grpRes.ok) {
        const grpData = await grpRes.json();
        allAccess = Boolean(grpData.all_access);
        (grpData.song_keys || []).forEach(k => allowedGroupKeys.add(k));
      }
    } catch (_) {}

    // También añadir canciones presentes en las setlists cargadas del grupo
    if (window.ALL_SETLISTS) {
      state.ALL_SETLISTS.forEach(sl => {
        (sl.songs || []).forEach(s => {
          if (s.title) allowedGroupKeys.add(normalizeSongKeyClient(s.title));
          if (s.id) allowedGroupKeys.add(normalizeSongKeyClient(s.id));
          if (s.folderId) allowedGroupKeys.add(normalizeSongKeyClient(s.folderId));
        });
      });
    }

    // 2. Consultar catálogo en la nube
    let rawCloudSongs = [];
    try {
      const res = await fetch(endpoints.cloud + '/catalog.json?t=' + Date.now(), { cache: 'no-store' });
      if (res.ok) {
        const data = await res.json();
        rawCloudSongs = data.songs || [];
      }
    } catch (cloudErr) {
      console.warn("Catálogo remoto no disponible, usando canciones locales del grupo:", cloudErr);
    }

    if (window.refreshLocalStatus) {
      await refreshLocalStatus();
    }

    // 3. Combinar con canciones locales del grupo que no estén aún en el listado remoto
    const combinedSongs = [...rawCloudSongs];
    const seenTitles = new Set(rawCloudSongs.map(s => normalizeSongKeyClient(s.title)));
    if (Array.isArray(state.LOCAL_BACKEND_SONGS)) {
      state.LOCAL_BACKEND_SONGS.forEach(localS => {
        const normT = normalizeSongKeyClient(localS.title || localS.id);
        if (normT && !seenTitles.has(normT)) {
          seenTitles.add(normT);
          combinedSongs.push({
            id: localS.id,
            folderId: localS.id,
            title: localS.title || localS.id,
            artist: localS.artist || 'Desconocido',
            bpm: localS.bpm || 120,
            key: localS.key || 'C',
            cover: localS.cover || null,
            stems: localS.stems || [],
            group_id: localS.group_id || null,
            group_name: localS.group_name || null,
            group_ids: localS.group_ids || []
          });
        }
      });
    }

    // 4. Catalogo compartido: todas las canciones disponibles para todos los usuarios autenticados
    state.cachedCloudSongs = combinedSongs;

    if (statusEl) statusEl.innerText = 'EN LÍNEA';
    if (statusDot) statusDot.style.background = '#43B97C';

    renderCloudSongs(state.cachedCloudSongs);
  } catch (err) {
    if (statusEl) statusEl.innerText = 'DESCONECTADO';
    if (statusDot) statusDot.style.background = '#E4604E';
    if (summaryEl) summaryEl.innerText = 'Error de conexión';
    if (listEl) {
      listEl.innerHTML = `
        <div style="text-align:center; padding:26px 16px; background:rgba(239,68,68,0.06); border:1px solid rgba(239,68,68,0.25); border-radius:10px;">
          <i data-lucide="cloud-off" style="width:30px;height:30px;color:#E4604E;margin-bottom:8px;"></i>
          <h5 style="margin:0 0 6px; font-size:13px; font-weight:800; color:var(--ink);">No se pudo obtener el catálogo</h5>
          <p style="font-size:11px; color:var(--mut); margin:0 0 14px; line-height:1.4;">${err.message}</p>
          <button type="button" class="btn btn-ghost" onclick="fetchAndRenderCloudSongs()" style="font-size:11px; padding:6px 14px; border:1px solid var(--line2);">
            <i data-lucide="rotate-cw" style="width:12px;height:12px;"></i> Reintentar conexión
          </button>
        </div>
      `;
      if (window.lucide) lucide.createIcons();
    }
  }
}



export function handleCloudSearchInput(val) {
  const clearBtn = document.getElementById('cloudSearchClearBtn');
  if (clearBtn) clearBtn.style.display = val && val.trim().length > 0 ? 'flex' : 'none';
  filterCloudSongs(val);
}



export function clearCloudSearch() {
  const searchInput = document.getElementById('cloudSearchInput');
  const clearBtn = document.getElementById('cloudSearchClearBtn');
  if (searchInput) {
    searchInput.value = '';
    searchInput.focus();
  }
  if (clearBtn) clearBtn.style.display = 'none';
  filterCloudSongs('');
}



export function filterCloudSongs(query) {
  if (!query || !query.trim()) {
    renderCloudSongs(state.cachedCloudSongs);
    return;
  }
  const q = query.trim().toLowerCase();
  const filtered = state.cachedCloudSongs.filter(s => {
    const title = (s.title || '').toLowerCase();
    const artist = (s.artist || '').toLowerCase();
    const key = (s.key || '').toLowerCase();
    const bpm = (s.bpm ? String(s.bpm) : '').toLowerCase();
    return title.includes(q) || artist.includes(q) || key.includes(q) || bpm.includes(q);
  });
  renderCloudSongs(filtered, query.trim());
}



export function renderCloudSongs(songsToRender, currentFilter = '') {
  const listEl = document.getElementById('cloudSongsList');
  const summaryEl = document.getElementById('cloudSearchSummary');
  const badgeEl = document.getElementById('cloudSearchCountBadge');
  if (!listEl) return;

  const isAdmin = window.CURRENT_USER && window.CURRENT_USER.role === 'admin';
  if (summaryEl) {
    if (currentFilter) {
      summaryEl.innerText = `Resultados para "${currentFilter}"`;
    } else {
      summaryEl.innerText = 'Catálogo General (Canciones Disponibles)';
    }
  }
  if (badgeEl) {
    badgeEl.innerText = `${songsToRender.length} de ${state.cachedCloudSongs.length} canciones`;
  }

  // Si no hay canciones en este grupo aún
  if (state.cachedCloudSongs.length === 0) {
    listEl.innerHTML = `
      <div style="text-align:center; padding:36px 18px; border:1px dashed var(--line2); border-radius:12px; background:rgba(255,255,255,0.01);">
        <div style="width:48px;height:48px;border-radius:50%;background:rgba(245,158,11,0.08);display:flex;align-items:center;justify-content:center;margin:0 auto 12px;">
          <i data-lucide="cloud-off" style="width:24px;height:24px;color:var(--amber);"></i>
        </div>
        <h4 style="font-size:13px;font-weight:800;color:var(--ink);margin:0 0 6px;">Este grupo aún no tiene canciones cargadas</h4>
        <p style="font-size:11px;color:var(--mut);margin:0 auto 16px;max-width:320px;line-height:1.4;">
          Usa el botón <strong>+ SUBIR CANCIÓN</strong> en la barra superior para subir el primer multitrack de tu grupo.
        </p>
      </div>
    `;
    if (window.lucide) lucide.createIcons();
    return;
  }

  // Si la búsqueda no dio resultados
  if (songsToRender.length === 0) {
    listEl.innerHTML = `
      <div style="text-align:center; padding:32px 18px; border:1px dashed var(--line2); border-radius:12px;">
        <i data-lucide="search-x" style="width:28px;height:28px;color:var(--dim);margin-bottom:8px;"></i>
        <h5 style="margin:0 0 4px;font-size:12px;font-weight:800;color:var(--ink2);">Sin coincidencias</h5>
        <p style="margin:0 0 12px;font-size:11px;color:var(--mut);">No encontramos ninguna canción que coincida con "${currentFilter}".</p>
        <button type="button" class="btn btn-ghost" style="padding:4px 12px;font-size:10px;border:1px solid var(--line2);" onclick="clearCloudSearch()">
          <i data-lucide="x" style="width:11px;height:11px;"></i> Limpiar búsqueda
        </button>
      </div>
    `;
    if (window.lucide) lucide.createIcons();
    return;
  }

  // Renderizar las tarjetas
  listEl.innerHTML = songsToRender.map((s, idx) => {
    const coverHtml = s.cover 
      ? `<div class="cloud-song-cover" style="background-image:url('${s.cover}');"></div>`
      : `<div class="cloud-song-cover" style="background:linear-gradient(135deg, #1c2233 0%, #1A1714 100%);"><i data-lucide="music-2" style="width:20px;height:20px;color:var(--amber);"></i></div>`;

    const stemCount = s.stems ? s.stems.length : 0;
    const safeSongJson = JSON.stringify(s).replace(/'/g, "&apos;");
    const isLocal = isSongInLocal(s);

    const localPill = isLocal
      ? `<span class="cloud-song-meta-pill" style="border-color:rgba(34,197,94,0.45); background:rgba(34,197,94,0.12); color:#43B97C; font-weight:800; display:inline-flex; align-items:center; gap:4px;"><i data-lucide="check-circle-2" style="width:11px;height:11px;"></i> EN LOCAL</span>`
      : `<span class="cloud-song-meta-pill" style="border-color:rgba(245,158,11,0.3); background:rgba(245,158,11,0.08); color:var(--amber); display:inline-flex; align-items:center; gap:4px;"><i data-lucide="cloud" style="width:11px;height:11px;"></i> NUBE</span>`;

    const checkIconTitle = isLocal
      ? `<span style="display:inline-flex; align-items:center; justify-content:center; width:17px; height:17px; border-radius:50%; background:#43B97C; color:#000; font-size:10px; font-weight:900;" title="Descargado en tu dispositivo"><i data-lucide="check" style="width:11px;height:11px;stroke-width:3;"></i></span>`
      : '';

    const actionButton = isLocal
      ? `<button type="button" class="btn btn-ghost btn-sm" id="btnAddCloud_${s.id || idx}" onclick='triggerAddCloudSong(${safeSongJson}, this)' style="padding:7px 14px; font-weight:800; font-size:11px; display:inline-flex; align-items:center; gap:5px; border-radius:6px; border:1px solid rgba(34,197,94,0.5); color:#43B97C; background:rgba(34,197,94,0.08);">
          <i data-lucide="plus" style="width:13px;height:13px;"></i> AÑADIR
         </button>`
      : `<button type="button" class="btn btn-amber btn-sm" id="btnAddCloud_${s.id || idx}" onclick='triggerAddCloudSong(${safeSongJson}, this)' style="padding:7px 14px; font-weight:800; font-size:11px; display:inline-flex; align-items:center; gap:5px; border-radius:6px;">
          <i data-lucide="cloud-download" style="width:13px;height:13px;"></i> DESCARGAR
         </button>`;

    return `
      <div class="cloud-song-card" style="${isLocal ? 'border-color:rgba(34,197,94,0.25);' : ''}">
        <div style="display:flex; align-items:center; gap:12px; min-width:0; flex:1;">
          ${coverHtml}
          <div style="min-width:0; flex:1;">
            <div style="display:flex; align-items:center; gap:8px;">
              <h5 style="margin:0; font-size:13px; font-weight:800; color:var(--ink); white-space:nowrap; overflow:hidden; text-overflow:ellipsis;" title="${s.title}">${s.title}</h5>
              ${checkIconTitle}
            </div>
            <p style="margin:2px 0 6px; font-size:11px; color:var(--mut); white-space:nowrap; overflow:hidden; text-overflow:ellipsis;">${s.artist || 'Artista Desconocido'}</p>
            <div style="display:flex; align-items:center; gap:6px; flex-wrap:wrap;">
              ${localPill}
              <span class="cloud-song-meta-pill"><i data-lucide="disc" style="width:10px;height:10px;"></i> TONO: ${s.key || 'C'}</span>
              <span class="cloud-song-meta-pill"><i data-lucide="gauge" style="width:10px;height:10px;"></i> ${s.bpm || 120} BPM</span>
              <span class="cloud-song-meta-pill accent"><i data-lucide="layers" style="width:10px;height:10px;"></i> ${stemCount} STEMS</span>
            </div>
          </div>
        </div>
        <div style="flex-shrink:0;">
          ${actionButton}
        </div>
      </div>
    `;
  }).join('');

  if (window.lucide) lucide.createIcons();
}



export async function triggerAddCloudSong(song, btnEl) {
  const isAlreadyLocal = isSongInLocal(song);

  if (isAlreadyLocal) {
    if (btnEl) {
      btnEl.innerHTML = '<i data-lucide="check" style="width:13px;height:13px;"></i> LISTA';
      btnEl.classList.remove('btn-amber');
      btnEl.classList.add('btn-ghost');
      btnEl.style.color = '#43B97C';
      btnEl.style.borderColor = '#43B97C';
      btnEl.style.pointerEvents = 'none';
      if (window.lucide) lucide.createIcons();
    }
    addCloudSongToSetlist(song);
    return;
  }

  // Si no está en local, realizar la descarga y persistencia local (1 sola vez)
  if (btnEl) {
    btnEl.innerHTML = '<i data-lucide="loader-2" style="width:13px;height:13px;animation:spin 1s linear infinite;"></i> DESCARGANDO...';
    btnEl.classList.add('btn-amber');
    btnEl.style.pointerEvents = 'none';
    if (window.lucide) lucide.createIcons();
  }

  try {
    let importedToBackend = false;
    // 1. Intentar descargar y extraer en el backend local (para tenerlo en data/songs/ permanente)
    try {
      const impRes = await fetch('/api/songs/import-from-cloud', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${getAuthToken()}`
        },
        body: JSON.stringify({
          downloadUrl: song.downloadUrl,
          title: song.title,
          artist: song.artist,
          bpm: song.bpm,
          key: song.key
        })
      });

      if (impRes.ok) {
        const impData = await impRes.json();
        if (impData.metadata) {
          song.folderId = impData.metadata.id;
          song.backendStems = impData.metadata.stems;
        }
        importedToBackend = true;
        console.log("Canción guardada con éxito en servidor local de archivos:", impData);
      }
    } catch (beErr) {
      console.warn("Backend local no disponible para import, usando almacenamiento de navegador:", beErr);
    }

    // 2. Si no hubo backend local (modo cliente puro / móvil), guardar en IndexedDB
    if (!importedToBackend && song.downloadUrl) {
      if (btnEl) btnEl.innerHTML = '<i data-lucide="loader-2" style="width:13px;height:13px;animation:spin 1s linear infinite;"></i> GUARDANDO CACHÉ...';
      const dUrl = song.downloadUrl + (song.downloadUrl.includes('?') ? '&' : '?') + 't=' + Date.now();
      const dRes = await fetch(dUrl);
      if (!dRes.ok) throw new Error("Error HTTP " + dRes.status);
      const blob = await dRes.blob();
      await state.CloudStorageCache.saveSongZipBlob(song.title, blob);
    }

    // 3. Actualizar estado local inmediatamente
    await refreshLocalStatus();

    // 4. Actualizar botón a añadido con éxito
    if (btnEl) {
      btnEl.innerHTML = '<i data-lucide="check" style="width:13px;height:13px;"></i> DESCARGADA';
      btnEl.classList.remove('btn-amber');
      btnEl.classList.add('btn-ghost');
      btnEl.style.color = '#43B97C';
      btnEl.style.borderColor = '#43B97C';
      btnEl.style.pointerEvents = 'none';
      if (window.lucide) lucide.createIcons();
    }

    // 5. Re-renderizar lista de canciones de la nube para mostrar el check verde y badge "EN LOCAL"
    renderCloudSongs(state.cachedCloudSongs);

    // 6. Añadir al setlist
    addCloudSongToSetlist(song);

  } catch (err) {
    console.error("Error importando canción desde la nube:", err);
    alert("No se pudo descargar la canción: " + err.message);
    if (btnEl) {
      btnEl.innerHTML = '<i data-lucide="cloud-download" style="width:13px;height:13px;"></i> REINTENTAR';
      btnEl.style.pointerEvents = 'auto';
      if (window.lucide) lucide.createIcons();
    }
  }
}



export function addCloudSongToSetlist(cloudSong) {
  const currentSetlist = state.ALL_SETLISTS[state.currentSetlistIdx];
  if (!currentSetlist) return;

  const nSongTitle = normalizeTitle(cloudSong.title);
  let localFolderId = cloudSong.folderId || null;
  let localStems = cloudSong.backendStems || cloudSong.stems || [];

  // Buscar en LOCAL_BACKEND_SONGS si coincide por título normalizado
  if (!localFolderId && state.LOCAL_BACKEND_SONGS && state.LOCAL_BACKEND_SONGS.length > 0) {
    const found = state.LOCAL_BACKEND_SONGS.find(b => 
      normalizeTitle(b.title) === nSongTitle || 
      normalizeTitle(b.id) === nSongTitle
    );
    if (found) {
      localFolderId = found.id;
      if (found.stems && found.stems.length > 0) {
        localStems = found.stems;
      }
    }
  }

  // También buscar en setlists existentes
  if (!localFolderId && window.ALL_SETLISTS) {
    for (const sl of state.ALL_SETLISTS) {
      if (!sl || !sl.songs) continue;
      const match = sl.songs.find(s => s.folderId && s.title && normalizeTitle(s.title) === nSongTitle);
      if (match) {
        localFolderId = match.folderId;
        if (match.backendStems && match.backendStems.length > 0) {
          localStems = match.backendStems;
        }
        break;
      }
    }
  }

  const newSong = {
    id: 'cloud_' + (cloudSong.id || Date.now()),
    title: cloudSong.title,
    artist: cloudSong.artist || 'Desconocido',
    key: cloudSong.key || 'C',
    bpm: cloudSong.bpm || 120,
    cover: cloudSong.cover || null,
    total16ths: 640,
    meta: `TONO: ${cloudSong.key} · ${cloudSong.bpm} BPM · 4/4 · ${localFolderId ? 'LOCAL' : 'NUBE'} (${(cloudSong.stems || []).length} STEMS)`,
    stems: (cloudSong.stems || []).map(st => st.id || st.category || 'other'),
    sections: (cloudSong.sections && Array.isArray(cloudSong.sections)) ? JSON.parse(JSON.stringify(cloudSong.sections)) : [],
    backendStems: localStems,
    folderId: localFolderId,
    downloadUrl: cloudSong.downloadUrl || '',
    isCloud: !localFolderId
  };

  currentSetlist.songs.push(newSong);
  state.SONGS_DATA = currentSetlist.songs;
  state.currentSongIdx = currentSetlist.songs.length - 1;
  state.SONG = newSong;
  state.bpm = state.SONG.bpm;

  registerSongInCurrentGroup(newSong);
  if (window.CURRENT_USER && typeof saveCurrentSetlist === 'function') {
    saveCurrentSetlist();
  }

  renderEditionSongList();
  renderStageSlider();
  updateStemCountBadge();
  say('CANCION AÑADIDA: ' + newSong.title);

  // Iniciar la carga de stems para que esté lista para reproducirse
  if (newSong.folderId || newSong.downloadUrl) {
    loadRealStems(newSong);
  }

  setTimeout(() => {
    const modal = document.getElementById('addSongChoiceModal');
    if (modal) modal.classList.remove('open');
  }, 450);
}



export function openLocalUploadFlow() {
  const choiceModal = document.getElementById('addSongChoiceModal');
  if (choiceModal) choiceModal.classList.remove('open');
  if (!window.CURRENT_USER) {
    openAuthModal('login');
    if (typeof say === 'function') say('INICIA SESIÓN PARA CARGAR CANCIONES EN TU GRUPO');
    return;
  }
  state.uploadTarget = 'local';
  resetUploadWizard();
  const titleEl = document.getElementById('uploadModalTitle');
  if (titleEl) {
    titleEl.innerHTML = '<span style="display:flex;align-items:center;gap:8px;"><i data-lucide="hard-drive-upload" style="width:20px;height:20px;color:var(--amber);"></i> Cargar Canción Localmente (Este Dispositivo)</span>';
  }
  const finalizeBtn = document.querySelector('#uploadStep3 button.btn-amber');
  if (finalizeBtn) finalizeBtn.innerHTML = 'FINALIZAR Y ABRIR LOCAL';
  state.uploadModal.classList.add('open');
  if (window.lucide) lucide.createIcons();
}



export function updateStepperUI(step) {
  const s1 = document.getElementById('wsStep1');
  const s2 = document.getElementById('wsStep2');
  const s3 = document.getElementById('wsStep3');
  const l1 = document.getElementById('wsLine1');
  const l2 = document.getElementById('wsLine2');

  const b1 = s1 ? s1.querySelector('.ws-badge') : null;
  const b2 = s2 ? s2.querySelector('.ws-badge') : null;
  const b3 = s3 ? s3.querySelector('.ws-badge') : null;

  if (s1 && b1) {
    if (step >= 1) {
      s1.style.opacity = '1';
      b1.style.background = 'var(--amber)';
      b1.style.color = '#000';
    }
  }
  if (l1) l1.style.background = step >= 2 ? 'var(--amber)' : 'var(--line2)';
  if (s2 && b2) {
    s2.style.opacity = step >= 2 ? '1' : '0.4';
    b2.style.background = step >= 2 ? 'var(--amber)' : '#1c2029';
    b2.style.color = step >= 2 ? '#000' : 'var(--mut)';
  }
  if (l2) l2.style.background = step >= 3 ? 'var(--amber)' : 'var(--line2)';
  if (s3 && b3) {
    s3.style.opacity = step >= 3 ? '1' : '0.4';
    b3.style.background = step >= 3 ? 'var(--amber)' : '#1c2029';
    b3.style.color = step >= 3 ? '#000' : 'var(--mut)';
  }
}



export function handleCoverSelected(e) {
  const file = e.target.files[0];
  if (!file) return;
  if (file.size > 2 * 1024 * 1024) {
    alert("La imagen es muy grande. Máximo 2MB.");
    e.target.value = '';
    return;
  }
  const reader = new FileReader();
  reader.onload = function(evt) {
    const preview = document.getElementById('coverPreviewImg');
    const placeholder = document.getElementById('coverPlaceholder');
    const removeBtn = document.getElementById('btnRemoveCover');
    if (preview) { preview.src = evt.target.result; preview.style.display = 'block'; }
    if (placeholder) placeholder.style.display = 'none';
    if (removeBtn) removeBtn.style.display = 'flex';
    if (window.lucide) lucide.createIcons();
  };
  reader.readAsDataURL(file);
}



export function removeCoverPreview(e) {
  if (e) e.stopPropagation();
  const input = document.getElementById('upCover');
  const preview = document.getElementById('coverPreviewImg');
  const placeholder = document.getElementById('coverPlaceholder');
  const removeBtn = document.getElementById('btnRemoveCover');
  if (input) input.value = '';
  if (preview) { preview.src = ''; preview.style.display = 'none'; }
  if (placeholder) placeholder.style.display = 'block';
  if (removeBtn) removeBtn.style.display = 'none';
}



export function adjustUpBpm(delta) {
  const input = document.getElementById('upBpm');
  if (input) {
    let val = (parseFloat(input.value) || 120) + delta;
    input.value = Math.max(40, Math.min(260, Math.round(val)));
  }
}



export function resetUploadWizard() {
  document.getElementById('uploadStep1').style.display = 'block';
  document.getElementById('uploadStep2').style.display = 'none';
  document.getElementById('uploadStep3').style.display = 'none';
  document.getElementById('upTitle').value = '';
  document.getElementById('upArtist').value = '';
  document.getElementById('upBpm').value = '120';
  document.getElementById('upKey').value = 'C';
  removeCoverPreview();
  document.getElementById('uploadProgressBar').style.width = '0%';
  document.getElementById('uploadProgressBar').style.backgroundColor = 'var(--amber)';
  document.getElementById('uploadProgress').style.display = 'none';
  document.getElementById('uploadStatusText').innerText = 'Selecciona o arrastra tu archivo .ZIP de Stems';
  document.getElementById('btnNextStep3').style.opacity = '0.5';
  document.getElementById('btnNextStep3').style.pointerEvents = 'none';
  document.getElementById('btnBackStep1').style.display = 'inline-block';
  state.currentUploadedZipFile = null;
  state.currentUploadMetadata = null;
  updateStepperUI(1);
}



export function goToUploadStep1() {
  document.getElementById('uploadStep1').style.display = 'block';
  document.getElementById('uploadStep2').style.display = 'none';
  document.getElementById('uploadStep3').style.display = 'none';
  updateStepperUI(1);
}



export function goToUploadStep2() {
  const title = document.getElementById('upTitle').value.trim();
  if (!title) { alert('Debes ingresar un título para la canción.'); return; }
  document.getElementById('uploadStep1').style.display = 'none';
  document.getElementById('uploadStep2').style.display = 'block';
  document.getElementById('uploadStep3').style.display = 'none';
  updateStepperUI(2);
}



export function goToUploadStep3() {
  document.getElementById('uploadStep1').style.display = 'none';
  document.getElementById('uploadStep2').style.display = 'none';
  document.getElementById('uploadStep3').style.display = 'block';
  updateStepperUI(3);
  const badge = document.getElementById('stemsFoundBadge');
  if (badge && state.currentUploadMetadata && state.currentUploadMetadata.stems) {
    badge.innerText = `${state.currentUploadMetadata.stems.length} STEMS`;
  }
  renderMappingList();
}



export function renderMappingList() {
  const listEl = document.getElementById('mappingList');
  listEl.innerHTML = '';
  if (!state.currentUploadMetadata || !state.currentUploadMetadata.stems) return;
  
  state.currentUploadMetadata.stems.forEach((st, idx) => {
    listEl.innerHTML += `
      <div style="background:#221E19; padding:10px; border-radius:6px; border:1px solid var(--line2); display:flex; flex-direction:column; gap:8px;">
        <div style="font-size:10px; color:var(--amber); font-family:var(--mono);">ARCHIVO: ${st.original || st.filename}</div>
        <div style="display:flex; gap:10px; align-items:center;">
          <div style="flex:1;">
            <label style="font-size:10px; color:var(--mut);">ETIQUETA (FADER)</label>
            <input type="text" id="mapLabel_${idx}" value="${st.label}" style="width:100%; padding:6px; background:#0b0c0f; border:1px solid var(--line2); color:white; border-radius:4px; font-size:12px;">
          </div>
          <div style="flex:1;">
            <label style="font-size:10px; color:var(--mut);">CATEGORÍA (COLOR)</label>
            <select id="mapCat_${idx}" style="width:100%; padding:6px; background:#0b0c0f; border:1px solid var(--line2); color:white; border-radius:4px; font-size:12px;">
              <option value="click" ${st.category==='click'?'selected':''}>Click (Gris)</option>
              <option value="guide" ${st.category==='guide'?'selected':''}>Guía (Naranja)</option>
              <option value="drums" ${st.category==='drums'?'selected':''}>Batería (Rojo)</option>
              <option value="bass" ${st.category==='bass'?'selected':''}>Bajo (Verde)</option>
              <option value="keys" ${st.category==='keys'?'selected':''}>Teclados (Azul)</option>
              <option value="pad" ${st.category==='pad'?'selected':''}>Pads (Morado)</option>
              <option value="guitars" ${st.category==='guitars'?'selected':''}>Guitarras (Amarillo)</option>
              <option value="vocals" ${st.category==='vocals'?'selected':''}>Voces (Rosa)</option>
              <option value="other" ${st.category==='other'?'selected':''}>Otro (Gris Claro)</option>
            </select>
          </div>
        </div>
      </div>
    `;
  });
}



export async function finalizeUpload() {
  if (!window.CURRENT_USER) {
    state.uploadModal.classList.remove('open');
    openAuthModal('login');
    say('INICIA SESIÓN PARA SUBIR CANCIONES A TU GRUPO');
    return;
  }
  if (!state.currentUploadMetadata) return;
  
  state.currentUploadMetadata.stems.forEach((st, idx) => {
    st.label = document.getElementById(`mapLabel_${idx}`).value.toUpperCase();
    st.category = document.getElementById(`mapCat_${idx}`).value;
  });

  const title = document.getElementById('upTitle').value.trim() || 'Sin Título';
  const artist = document.getElementById('upArtist').value.trim() || 'Desconocido';
  const bpmVal = parseFloat(document.getElementById('upBpm').value) || 120;
  const keyVal = document.getElementById('upKey').value || 'C';
  const userGroupId = window.CURRENT_USER.grupo_id || '';
  const userGroupName = window.CURRENT_USER.group_name || '';

  if (state.uploadTarget === 'cloud') {
    // Subida al Servidor Debian / Cloudflare
    const statusText = document.getElementById('uploadStatusText');
    const progBar = document.getElementById('uploadProgressBar');
    document.getElementById('uploadStep3').style.display = 'none';
    document.getElementById('uploadStep2').style.display = 'block';

    const fileSize = state.currentUploadedZipFile.size;
    const mbTotal = (fileSize / (1024 * 1024)).toFixed(1);
    const coverFile = document.getElementById('upCover').files[0];

    // Detectar si estamos en la red local con Debian
    let isLocalLanAvailable = false;
    try {
      const ping = await fetch(endpoints.localUpload + '/catalog.json', { method: 'HEAD', mode: 'cors', cache: 'no-store', signal: AbortSignal.timeout(1500) });
      if (ping.ok) isLocalLanAvailable = true;
    } catch (_) {}

    const baseUrl = isLocalLanAvailable 
      ? endpoints.localUpload 
      : endpoints.cloud;

    console.log(`Subiendo a la nube usando base URL: ${baseUrl} (${isLocalLanAvailable ? 'LAN Local' : 'Cloudflare CDN'})`);

    // CASO A: Si estamos en LAN local directa, intentar primero subida directa rápida
    if (isLocalLanAvailable && fileSize < 500 * 1024 * 1024) {
      if (statusText) statusText.innerText = `Subiendo por red local (${mbTotal} MB)...`;
      if (progBar) progBar.style.width = '50%';

      const formData = new FormData();
      formData.append('file', state.currentUploadedZipFile);
      formData.append('title', title);
      formData.append('artist', artist);
      formData.append('bpm', bpmVal);
      formData.append('key', keyVal);
      formData.append('group_id', userGroupId);
      formData.append('group_name', userGroupName);
      formData.append('stems', JSON.stringify(state.currentUploadMetadata.stems));
      if (coverFile) formData.append('cover', coverFile);

      try {
        const res = await fetch(`${baseUrl}/api/upload`, {
          method: 'POST',
          headers: { 'Authorization': `Bearer ${getAuthToken()}` },
          body: formData
        });
        if (!res.ok) {
          const errData = await res.json().catch(() => ({}));
          throw new Error(errData.error || `HTTP ${res.status}`);
        }
        const data = await res.json();
        if (progBar) progBar.style.width = '100%';
        if (statusText) statusText.innerText = '¡Canción guardada con éxito en tu servidor!';
        await registerSongInCurrentGroup({ id: data.song?.id || title, title: title });
        say('CANCION SUBIDA A LA NUBE: ' + title);
        if (data.song) addCloudSongToSetlist(data.song);
        setTimeout(() => state.uploadModal.classList.remove('open'), 1200);
        return;
      } catch (directErr) {
        console.warn("Subida directa falló, procediendo a subida por fragmentos:", directErr);
      }
    }

    // CASO B: Subida por Fragmentos (Chunks de 30 MB)
    const CHUNK_SIZE = 30 * 1024 * 1024; // 30 MB por fragmento (seguro bajo el límite de Cloudflare)
    const totalChunks = Math.ceil(fileSize / CHUNK_SIZE);
    const uploadId = 'up_' + Date.now() + '_' + Math.random().toString(36).substring(2, 8);

    console.log(`Iniciando subida por fragmentos: ${totalChunks} partes para un total de ${mbTotal} MB.`);

    try {
      let finalResultData = null;

      for (let chunkIdx = 0; chunkIdx < totalChunks; chunkIdx++) {
        const start = chunkIdx * CHUNK_SIZE;
        const end = Math.min(start + CHUNK_SIZE, fileSize);
        const chunkBlob = state.currentUploadedZipFile.slice(start, end);

        const pct = Math.round(((chunkIdx) / totalChunks) * 100);
        if (progBar) progBar.style.width = `${pct}%`;
        if (statusText) statusText.innerText = `Subiendo fragmento ${chunkIdx + 1} de ${totalChunks} (${pct}%)...`;

        const chunkFormData = new FormData();
        chunkFormData.append('chunk', chunkBlob, `part_${chunkIdx}`);
        chunkFormData.append('uploadId', uploadId);
        chunkFormData.append('chunkIndex', chunkIdx);
        chunkFormData.append('totalChunks', totalChunks);

        // En el último fragmento, enviar metadatos y carátula para el ensamblado y verificación
        if (chunkIdx === totalChunks - 1) {
          chunkFormData.append('title', title);
          chunkFormData.append('artist', artist);
          chunkFormData.append('bpm', bpmVal);
          chunkFormData.append('key', keyVal);
          chunkFormData.append('group_id', userGroupId);
          chunkFormData.append('group_name', userGroupName);
          chunkFormData.append('stems', JSON.stringify(state.currentUploadMetadata.stems));
          if (coverFile) chunkFormData.append('cover', coverFile);
          if (statusText) statusText.innerText = `Verificando integridad y ensamblando en servidor...`;
        }

        // Enviar fragmento con reintento automático si hubiera fallo transitorio
        let chunkOk = false;
        let chunkErr = null;
        for (let retry = 0; retry < 3; retry++) {
          try {
            const chunkRes = await fetch(`${baseUrl}/api/upload-chunk`, {
              method: 'POST',
              headers: { 'Authorization': `Bearer ${getAuthToken()}` },
              body: chunkFormData
            });
            if (!chunkRes.ok) {
              const errJson = await chunkRes.json().catch(() => ({}));
              throw new Error(errJson.error || `HTTP ${chunkRes.status}`);
            }
            const resData = await chunkRes.json();
            if (chunkIdx === totalChunks - 1) {
              finalResultData = resData;
            }
            chunkOk = true;
            break;
          } catch (rErr) {
            chunkErr = rErr;
            console.warn(`Reintento ${retry + 1} para fragmento ${chunkIdx}:`, rErr);
            await new Promise(r => setTimeout(r, 1000));
          }
        }

        if (!chunkOk) {
          throw new Error(`Fallo al subir el fragmento ${chunkIdx + 1}: ${chunkErr ? chunkErr.message : 'Error de conexión'}`);
        }
      }

      // Subida y ensamblado final completado con éxito
      if (progBar) progBar.style.width = '100%';
      if (statusText) statusText.innerText = '¡Canción ensamblada y verificada con éxito!';
      await registerSongInCurrentGroup({ id: finalResultData?.song?.id || title, title: title });
      say('CANCION SUBIDA A LA NUBE: ' + title);

      if (finalResultData && finalResultData.song) {
        addCloudSongToSetlist(finalResultData.song);
      }

      setTimeout(() => {
        state.uploadModal.classList.remove('open');
      }, 1200);

    } catch (uploadErr) {
      console.error("Error en subida fragmentada:", uploadErr);
      if (progBar) progBar.style.backgroundColor = 'var(--red)';
      if (statusText) statusText.innerText = 'Error de subida: ' + uploadErr.message;
      document.getElementById('uploadStep2').style.display = 'none';
      document.getElementById('uploadStep3').style.display = 'block';
      alert('Error al subir a la nube: ' + uploadErr.message);
    }
  } else {
    // Guardado Local en este dispositivo
    const localSong = {
      id: 'local_' + Date.now(),
      title: title,
      artist: artist,
      key: keyVal,
      bpm: bpmVal,
      cover: null,
      total16ths: 640,
      meta: `TONO: ${keyVal} · ${bpmVal} BPM · 4/4 · LOCAL (${state.currentUploadMetadata.stems.length} STEMS)`,
      stems: state.currentUploadMetadata.stems.map(st => st.id || st.category || 'other'),
      sections: (state.currentUploadMetadata && state.currentUploadMetadata.sections && Array.isArray(state.currentUploadMetadata.sections))
        ? JSON.parse(JSON.stringify(state.currentUploadMetadata.sections))
        : [],
      backendStems: state.currentUploadMetadata.stems
    };

    await registerSongInCurrentGroup(localSong);

    const currentSetlist = state.ALL_SETLISTS[state.currentSetlistIdx];
    if (currentSetlist) {
      currentSetlist.songs.push(localSong);
      state.SONGS_DATA = currentSetlist.songs;
      state.currentSongIdx = currentSetlist.songs.length - 1;
      state.SONG = localSong;
      state.bpm = state.SONG.bpm;
      if (window.CURRENT_USER && typeof saveCurrentSetlist === 'function') {
        saveCurrentSetlist();
      }
      renderEditionSongList();
      renderStageSlider();
      updateStemCountBadge();
    }

    state.uploadModal.classList.remove('open');
    say('CANCION LOCAL GUARDADA: ' + title);
  }
}



export async function handleZipUpload(event) {
  const file = event.target.files[0];
  if (!file) return;
  state.currentUploadedZipFile = file;

  const uploadStatusText = document.getElementById('uploadStatusText');
  const uploadProgress = document.getElementById('uploadProgress');
  const uploadProgressBar = document.getElementById('uploadProgressBar');
  
  uploadStatusText.innerText = `Inspeccionando stems de ${file.name}...`;
  uploadProgress.style.display = 'block';
  uploadProgressBar.style.width = '30%';
  document.getElementById('btnBackStep1').style.display = 'none';

  try {
    // Si JSZip está disponible, leemos el ZIP en el cliente instantáneamente
    if (window.JSZip) {
      const zip = await JSZip.loadAsync(file);
      const audioFiles = [];
      
      zip.forEach((relativePath, zipEntry) => {
        if (!zipEntry.dir) {
          const lower = zipEntry.name.toLowerCase();
          if (lower.endsWith('.mp3') || lower.endsWith('.wav') || lower.endsWith('.flac') || lower.endsWith('.m4a') || lower.endsWith('.ogg')) {
            // Obtener solo nombre de archivo sin carpetas
            const filename = zipEntry.name.split('/').pop();
            if (!filename.startsWith('.') && !filename.startsWith('__MACOSX')) {
              audioFiles.push(filename);
            }
          }
        }
      });

      if (audioFiles.length === 0) {
        throw new Error("No se encontraron archivos de audio (.mp3, .wav, .flac) en el ZIP.");
      }

      uploadProgressBar.style.width = '70%';
      uploadStatusText.innerText = `Se encontraron ${audioFiles.length} pistas de audio. Analizando categorías...`;

      // Mapeo automático inteligente
      const stems = audioFiles.map(fn => {
        const lower = fn.toLowerCase();
        let cat = 'other';
        let label = fn.replace(/\.[^/.]+$/, "").substring(0, 10).toUpperCase();

        if (lower.includes('click') || lower.includes('metr')) { cat = 'click'; label = 'CLICK'; }
        else if (lower.includes('guide') || lower.includes('guia') || lower.includes('cue') || lower.includes('voz dir')) { cat = 'guide'; label = 'GUÍA'; }
        else if (lower.includes('drum') || lower.includes('bater') || lower.includes('kick') || lower.includes('snare')) { cat = 'drums'; label = 'BATERÍA'; }
        else if (lower.includes('bass') || lower.includes('bajo')) { cat = 'bass'; label = 'BAJO'; }
        else if (lower.includes('key') || lower.includes('piano') || lower.includes('synth') || lower.includes('tecl')) { cat = 'keys'; label = 'TECLADOS'; }
        else if (lower.includes('pad') || lower.includes('ambient') || lower.includes('colchon')) { cat = 'pad'; label = 'PADS'; }
        else if (lower.includes('guit') || lower.includes('acoust') || lower.includes('elect')) { cat = 'guitars'; label = 'GUITARRAS'; }
        else if (lower.includes('vox') || lower.includes('vocal') || lower.includes('coros') || lower.includes('lead')) { cat = 'vocals'; label = 'VOCES'; }

        return {
          id: cat + '_' + Math.random().toString(36).substring(2, 6),
          original: fn,
          filename: fn,
          label: label,
          category: cat
        };
      });

      state.currentUploadMetadata = { stems };
      uploadProgressBar.style.width = '100%';
      uploadStatusText.innerText = `¡${stems.length} pistas preparadas con éxito!`;

      const btnNext = document.getElementById('btnNextStep3');
      btnNext.style.opacity = '1';
      btnNext.style.pointerEvents = 'auto';
    } else {
      // Fallback si JSZip no estuviera
      uploadProgressBar.style.width = '100%';
      uploadStatusText.innerText = "Archivo recibido. Pulsa 'Continuar al mapeo'.";
      state.currentUploadMetadata = {
        stems: [
          { id: 'click', original: 'click.mp3', filename: 'click.mp3', label: 'CLICK', category: 'click' },
          { id: 'guide', original: 'guide.mp3', filename: 'guide.mp3', label: 'GUÍA', category: 'guide' },
          { id: 'drums', original: 'drums.mp3', filename: 'drums.mp3', label: 'BATERÍA', category: 'drums' }
        ]
      };
      const btnNext = document.getElementById('btnNextStep3');
      btnNext.style.opacity = '1';
      btnNext.style.pointerEvents = 'auto';
    }
  } catch (err) {
    uploadProgressBar.style.backgroundColor = 'var(--red)';
    uploadStatusText.innerText = `Error: ${err.message}`;
    document.getElementById('btnBackStep1').style.display = 'inline-block';
  }
}



export async function loadSongsAndSetlists() {
  const user = window.CURRENT_USER;

  // 1) SI NO HAY LOGEO (INVITADO): Cargar TODO VACÍO
  if (!user) {
    state.LOCAL_BACKEND_SONGS = [];
    state.LOCAL_DOWNLOADED_TITLES.clear();
    state.cachedCloudSongs = [];
    state.ALL_SETLISTS = [
      {
        id: 'guest-empty',
        name: 'SIN SESIÓN (INVITADO)',
        description: 'Inicia sesión para cargar tu grupo',
        songs: []
      }
    ];
    state.currentSetlistIdx = 0;
    switchSetlist(0);
    return;
  }

  // 2) USUARIO AUTENTICADO (GRUPO O ADMIN): Cargar catálogo de canciones de su grupo (o todas si es Admin)
  try {
    const response = await fetch('/api/songs', {
      headers: { 'Authorization': `Bearer ${getAuthToken()}` },
      cache: 'no-store'
    });
    if (response.ok) {
      const serverSongs = await response.json();
      state.LOCAL_BACKEND_SONGS = serverSongs || [];
      await refreshLocalStatus();
    }
  } catch (err) {
    console.log("Servidor local no disponible para canciones.");
  }

  // 3) Cargar setlists guardadas del grupo (o todas si es Admin) desde el backend
  let loadedSaved = false;
  let serverReachable = false;
  try {
    const slRes = await fetch('/api/setlists', {
      headers: { 'Authorization': `Bearer ${getAuthToken()}` },
      cache: 'no-store'
    });
    if (slRes.ok) {
      serverReachable = true;
      const savedSetlists = await slRes.json();
      if (Array.isArray(savedSetlists) && savedSetlists.length > 0) {
        state.ALL_SETLISTS = savedSetlists;
        loadedSaved = true;
        const storageKey = getSetlistStorageKey();
        if (storageKey) {
          try { localStorage.setItem(storageKey, JSON.stringify(state.ALL_SETLISTS)); } catch (_) {}
        }
        console.log("Setlists cargadas desde servidor:", state.ALL_SETLISTS.length);
      }
    }
  } catch (slErr) {
    console.log("No se pudo cargar setlists del backend, verificando localStorage del grupo...");
  }

  // Solo recurrir al localStorage del grupo si el servidor estuvo offline
  if (!loadedSaved && !serverReachable) {
    const storageKey = getSetlistStorageKey();
    if (storageKey) {
      try {
        const localSaved = localStorage.getItem(storageKey);
        if (localSaved) {
          const parsed = JSON.parse(localSaved);
          if (Array.isArray(parsed) && parsed.length > 0) {
            state.ALL_SETLISTS = parsed;
            loadedSaved = true;
          }
        }
      } catch (_) {}
    }
  }

  // Si el grupo aún no tiene setlists guardadas, inicializar con una setlist completamente vacía para ese grupo
  if (!loadedSaved || !state.ALL_SETLISTS || state.ALL_SETLISTS.length === 0) {
    const groupLabel = user.role === 'admin'
      ? 'ADMIN GLOBAL'
      : (user.group_name ? user.group_name.toUpperCase() : 'DOMINGO');
    state.ALL_SETLISTS = [
      {
        id: 'setlist-' + (user.grupo_id || 'main') + '-domingo',
        name: `SETLIST ${groupLabel}`,
        description: user.group_name ? `Grupo: ${user.group_name}` : 'Servicio Principal',
        group_id: user.role === 'admin' ? null : user.grupo_id,
        group_name: user.group_name || null,
        songs: []
      }
    ];
  }

  // Activar la primera setlist del grupo
  if (state.currentSetlistIdx >= state.ALL_SETLISTS.length) state.currentSetlistIdx = 0;
  switchSetlist(state.currentSetlistIdx);
}

export function initializeCatalog() {

state.currentUploadMetadata = null;

state.currentUploadSongId = null;

state.uploadTarget = 'cloud';
 // 'cloud' | 'local'
state.currentUploadedZipFile = null;


state.LOCAL_BACKEND_SONGS = [];

state.LOCAL_DOWNLOADED_TITLES = new Set();


state.CloudStorageCache = {
  dbPromise: null,
  getDb() {
    if (!this.dbPromise) {
      this.dbPromise = new Promise((resolve, reject) => {
        // Versión 2 para asegurar la creación del object store en navegadores existentes
        const req = indexedDB.open('PulsoMultitrackCache', 2);
        req.onupgradeneeded = (e) => {
          const db = e.target.result;
          if (!db.objectStoreNames.contains('song_zips')) {
            db.createObjectStore('song_zips', { keyPath: 'normTitle' });
          }
          if (!db.objectStoreNames.contains('cloud_songs')) {
            db.createObjectStore('cloud_songs', { keyPath: 'id' });
          }
        };
        req.onsuccess = () => resolve(req.result);
        req.onerror = () => reject(req.error);
      });
    }
    return this.dbPromise;
  },
  async saveSongZipBlob(idOrTitle, titleOrBlob, maybeBlob) {
    let key = idOrTitle;
    let blob = titleOrBlob;
    if (maybeBlob !== undefined) {
      key = titleOrBlob || idOrTitle;
      blob = maybeBlob;
    }
    const norm = normalizeTitle(key);
    try {
      const db = await this.getDb();
      const storeName = db.objectStoreNames.contains('song_zips') ? 'song_zips' : (db.objectStoreNames.contains('cloud_songs') ? 'cloud_songs' : null);
      if (!storeName) return false;
      return new Promise((resolve, reject) => {
        const tx = db.transaction(storeName, 'readwrite');
        const store = tx.objectStore(storeName);
        const record = storeName === 'song_zips' 
          ? { normTitle: norm, blob, timestamp: Date.now() }
          : { id: norm, title: key, blob, timestamp: Date.now() };
        store.put(record);
        tx.oncomplete = () => {
          state.LOCAL_DOWNLOADED_TITLES.add(norm);
          resolve(true);
        };
        tx.onerror = () => reject(tx.error);
      });
    } catch (e) {
      console.warn("IndexedDB saveSongZipBlob error:", e);
      return false;
    }
  },
  async getSongZipBlob(idOrTitle, maybeTitle) {
    const key = maybeTitle || idOrTitle;
    const norm = normalizeTitle(key);
    try {
      const db = await this.getDb();
      const storeName = db.objectStoreNames.contains('song_zips') ? 'song_zips' : (db.objectStoreNames.contains('cloud_songs') ? 'cloud_songs' : null);
      if (!storeName) return null;
      return new Promise((resolve) => {
        const tx = db.transaction(storeName, 'readonly');
        const store = tx.objectStore(storeName);
        const req = store.get(norm);
        req.onsuccess = () => resolve(req.result ? req.result.blob : null);
        req.onerror = () => resolve(null);
      });
    } catch (e) {
      return null;
    }
  },
  async getAllStoredTitles() {
    try {
      const db = await this.getDb();
      const storeName = db.objectStoreNames.contains('song_zips') ? 'song_zips' : (db.objectStoreNames.contains('cloud_songs') ? 'cloud_songs' : null);
      if (!storeName) return [];
      return new Promise((resolve) => {
        const tx = db.transaction(storeName, 'readonly');
        const store = tx.objectStore(storeName);
        const req = store.getAllKeys();
        req.onsuccess = () => resolve(req.result || []);
        req.onerror = () => resolve([]);
      });
    } catch (e) {
      return [];
    }
  },
  async clearAll() {
    try {
      const db = await this.getDb();
      for (const sName of ['song_zips', 'cloud_songs']) {
        if (db.objectStoreNames.contains(sName)) {
          const tx = db.transaction(sName, 'readwrite');
          tx.objectStore(sName).clear();
        }
      }
      state.LOCAL_DOWNLOADED_TITLES.clear();
      return true;
    } catch (_) {
      return false;
    }
  }
};

window.CloudStorageCache = state.CloudStorageCache;


window.clearLocalCache = async function() {
  await state.CloudStorageCache.clearAll();
  const sk = typeof getSetlistStorageKey === 'function' ? getSetlistStorageKey() : null;
  if (sk) {
    try { localStorage.removeItem(sk); } catch(_) {}
  }
  try { localStorage.removeItem('pulso_saved_setlists'); } catch(_) {}
  console.log("Caché local de canciones y setlists reiniciada a cero.");
  location.reload();
};

window.refreshLocalStatus = refreshLocalStatus;

window.isSongInLocal = isSongInLocal;


state.cachedCloudSongs = [];


/* ==========================================================================
   SETTINGS: DROPDOWN + TEMA CLARO/OSCURO
   ========================================================================== */
(function initSettings() {
  const themeRow = document.getElementById('themeToggleRow');
  const themeSwitch = document.getElementById('themeSwitch');

  if (!themeRow || !themeSwitch) return;

  // --- Restaurar tema guardado ---
  const savedTheme = localStorage.getItem('pulso-theme') || 'dark';
  if (savedTheme === 'light') {
    document.documentElement.setAttribute('data-theme', 'light');
    themeSwitch.classList.add('on');
  }

  // --- Toggle del tema ---
  themeRow.addEventListener('click', (e) => {
    e.stopPropagation();
    const isLight = document.documentElement.getAttribute('data-theme') === 'light';
    if (isLight) {
      document.documentElement.removeAttribute('data-theme');
      themeSwitch.classList.remove('on');
      localStorage.setItem('pulso-theme', 'dark');
    } else {
      document.documentElement.setAttribute('data-theme', 'light');
      themeSwitch.classList.add('on');
      localStorage.setItem('pulso-theme', 'light');
    }
    if (typeof drawHeroWaveform === 'function') drawHeroWaveform();
    if (typeof drawAllMeters === 'function') drawAllMeters();
  });
})();
}

