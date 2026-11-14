# PULSO — Setlist Multitrack

Reproductor multitrack orientado a Android/iOS, con desarrollo en PC mediante navegador y servidor local. La interfaz usa HTML, CSS y JavaScript; Capacitor empaqueta la web para móvil.

## Arranque rápido en Windows

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
npm ci
npm run dev
```

Abrir http://127.0.0.1:5000/. Requiere Node.js 22+ y Python 3.12. En macOS/Linux usar `.venv/bin/python` para instalar dependencias.

## Organización

| Carpeta | Responsabilidad |
|---|---|
| `src/` | Fuente web y página de Pinegrow |
| `backend/` | API Flask, rutas y servicios Python |
| `data/` | Datos locales privados, excluidos de Git |
| `scripts/` | Desarrollo, build, respaldo y migraciones |
| `tests/` | Regresiones de API y navegador |
| `docs/` | Arquitectura, decisiones y estado del producto |
| `android/`, `ios/` | Proyectos nativos de Capacitor |
| `engine/` | Motor C++ existente; integración profunda pendiente |
| `www/` | Salida generada, nunca editar directamente |

`npm run build` genera la web; `npm run sync` la sincroniza con Capacitor. `npm run android:build` compila el APK Debug. iOS requiere macOS/Xcode y firma para distribución.

## Documentación

- [Desarrollo, Pinegrow y comandos](docs/DEVELOPMENT.md)
- [Arquitectura actual](docs/ARCHITECTURE_PLAN.md)
- [Estado del producto y pads pendientes](docs/PRODUCT_STATE.md)
- [Mapa de migración y recuperación del respaldo](docs/MIGRATION.md)
- [Validación y límites de las pruebas](docs/VALIDATION.md)

La documentación histórica se conserva en `docs/archive/` como referencia y no describe necesariamente el sistema actual. No hay una medición confirmada de latencia nativa inferior a 5 ms.
