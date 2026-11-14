# Reorganización del 25 de octubre de 2026

## Mapa de traslado

| Antes | Ahora |
|---|---|
| `ui_prototype/index.html` | `src/index.html`, `src/js/`, `src/styles/` |
| `ui_prototype/modern_show.css` | `src/styles/show.css` |
| `ui_prototype/assets/`, `vendor/` | `src/assets/`, `src/vendor/` |
| `backend/local_server.py` monolítico | Entrada pequeña, `backend/routes/` y `backend/services/` |
| `backend/auth_db.py` | `backend/services/auth.py` |
| `backend/flac_converter.py` | `backend/services/flac.py` |
| `importer/stem_classifier.py` | `backend/services/stem_classifier.py` |
| `backend/migrate_to_flac.py` | `scripts/migrate_to_flac.py` |
| `www/songs/` | `data/songs/` |
| `backend/database/pulso.db` | `data/database/pulso.db` |
| `backend/setlists.json`, `backend/temp/` | `data/setlists.json`, `data/temp/` |
| `start_mobile_test.py` | `npm run dev` y túnel opcional separado |
| Scripts puntuales `patch_*`, `fix_*` y `.bak` | Respaldo local; retirados del árbol activo |

Los archivos de `android/`, `ios/` y `engine/` se conservan. `www/` deja de ser código versionado; el build lo regenera. El esquema SQL PostgreSQL histórico permanece documentado como referencia, no como base de datos del servidor SQLite.

## Respaldo y recuperación

El respaldo previo está en `.local-backups/20261025T113829Z/`, excluido de Git. Contiene `files/`, `manifest.json` con SHA-256, `git-status.txt` y `pulso-consistent.db` creado con la API de respaldo SQLite. Incluye los cambios sin commit y archivos sin seguimiento. Dependencias regenerables y cachés no forman parte del respaldo.

Para recuperar:

1. Detener el servidor y crear un respaldo del estado actual con `node scripts/python.cjs scripts/backup_workspace.py`.
2. Consultar `manifest.json` y comprobar los hashes de los archivos que se restaurarán.
3. Para recuperar solo datos, copiar canciones y setlists desde sus rutas históricas en `files/` hacia `data/`. Restaurar `pulso-consistent.db` como `data/database/pulso.db` con el servidor detenido.
4. Para volver al árbol anterior completo, trabajar en una copia separada del repositorio y restaurar `files/` conservando sus rutas. No mezclar ambas estructuras ni sobrescribir trabajo posterior sin compararlo.
5. Instalar las dependencias de la versión restaurada antes de arrancar.

El respaldo es local: no se sube a Git ni se publica en artefactos móviles. Conservar una copia adicional en el almacenamiento de respaldo habitual.

## Migración repetible de datos

`node scripts/python.cjs scripts/migrate_data.py` copia los datos de rutas históricas a `data/` (o `PULSO_DATA_DIR`). Primero detecta conflictos; nunca sobrescribe un destino diferente. Compara SHA-256 y comprueba SQLite. Conserva originales y deja un manifiesto de migración. Ejecutarlo con el servidor detenido; después verificar el manifiesto antes de retirar los originales.

La limpieza inicial retiró los originales únicamente después de verificar copia y respaldo. El build rechaza `www/songs/` para evitar eliminar una biblioteca histórica accidentalmente.
