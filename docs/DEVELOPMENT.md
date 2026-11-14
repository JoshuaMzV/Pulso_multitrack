# Desarrollo de PULSO

## Inicio en PC

Requisitos: Node.js 22 o superior, Python 3.12 y Git. Android necesita JDK 21 y Android SDK; iOS requiere macOS y Xcode con las herramientas correspondientes de Capacitor.

Desde la raíz, en PowerShell:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
npm ci
npm run dev
```

En macOS/Linux, instalar Python con `.venv/bin/python -m pip install -r requirements.txt`. El launcher detecta el entorno virtual en ambas plataformas. `PULSO_PYTHON` permite indicar otro intérprete.

Abrir http://127.0.0.1:5000/. La API Flask y los archivos de `src/` comparten origen. Recargar la página después de cambiar JavaScript/CSS; reiniciar el servidor después de cambiar Python. No hay que compilar para editar en PC.

Una instalación vacía conserva el flujo existente de invitación inicial de administrador; el servidor imprime el código de configuración. Los datos personales no se incluyen en Git.

## Comandos

| Comando | Resultado |
|---|---|
| `npm run dev` | Prepara dependencias web locales y arranca Flask en loopback |
| `npm run vendor` | Prepara librerías y fuentes locales para Pinegrow |
| `npm run build` | Regenera exclusivamente `www/` desde `src/` |
| `npm run sync` | Build web y `cap sync` |
| `npm run sync:copy` | Build web y `cap copy`; alias compatible |
| `npm run android:build` | Build web, sincronización Android y APK Debug |
| `npm run android:open` / `npm run ios:open` | Abre el proyecto nativo |
| `npm test` | Validación de módulos y pruebas Python aisladas |
| `npm run test:browser` | Pruebas Chromium; instalar antes con `npx playwright install chromium` |
| `npm run tunnel` | Túnel explícito mediante `cloudflared` instalado en PATH |

El túnel no se inicia con desarrollo normal. Para pruebas LAN se puede configurar `PULSO_HOST`; por defecto solo se escucha en `127.0.0.1`. `PULSO_PORT` cambia el puerto. El servidor es de desarrollo, no un despliegue productivo.

Para compilar Android, configurar `ANDROID_HOME` al SDK instalado o `sdk.dir` en `android/local.properties` (ignorado por Git). El JDK por sí solo no basta. Ver [resultados de validación](VALIDATION.md).

## Pinegrow

Abrir el proyecto con `pinegrow.json`: la página maestra es `src/index.html`. Ejecutar `npm run vendor` tras `npm ci`. Para probar audio, módulos y API, usar la página servida por `npm run dev`; abrir HTML con `file://` no reemplaza al servidor. La edición visual conserva HTML y CSS ordinarios, sin framework ni plantillas compiladas.

## Datos y servicios

`PULSO_DATA_DIR` permite ubicar canciones, SQLite, setlists y temporales fuera del repositorio. Sin configuración usa `data/`. Las rutas HTTP `/songs/...` no cambian aunque los archivos ya no estén en `www/`.

`PULSO_WEB_DIR` selecciona la fuente estática al ejecutar `python -m backend.local_server` directamente; por defecto es `src/`. `npm run dev` siempre selecciona `src/`. Para probar el build, establecer `PULSO_WEB_DIR` a la ruta absoluta de `www/` y ejecutar el servidor Python.

FFmpeg se obtiene del sistema o del paquete `imageio-ffmpeg`; el conversor también admite el encoder `flac` instalado en PATH. La migración manual a FLAC es `node scripts/python.cjs -m scripts.migrate_to_flac` y modifica audios: hacer respaldo antes.

Las direcciones de catálogo y carga remota existentes están centralizadas en `src/js/services/config.js`. Empaquetar dependencias locales elimina CDN de librerías/fuentes, pero no convierte las operaciones de catálogo, autenticación o carga remota en servicios offline. Flask es una herramienta de PC y no se incorpora al APK/IPA.

## Convenciones

- HTML, estilos y módulos web se editan en `src/`; nunca en `www/`.
- Funciones/variables en inglés; documentación y comentarios nuevos en español.
- Cada módulo importa sus dependencias. `state/store.js` contiene una única instancia de estado.
- `main.js` conserva el orden de inicialización; no crear contextos de audio al importar módulos.
- `ui/legacy-actions.js` es el puente temporal de botones HTML. Migrar handlers por componente, sin introducir globals adicionales.
- Conservar licencias de terceros en `vendor/`; dependencias generadas se reconstruyen con npm.
- No cambiar el motor C++ dentro de una tarea de UI u organización.
