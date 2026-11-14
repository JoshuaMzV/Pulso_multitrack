# Validación de la reorganización

Fecha: 2026-10-25. Entorno: Windows, Python 3.12 y Node.js 24; los workflows usan Node.js 22.

## Comprobado

- Respaldo previo: 222 archivos, 284.191.623 bytes, manifiesto SHA-256 y copia SQLite consistente.
- Datos trasladados: 14 archivos; la comparación final conservó todos sus hashes. `PRAGMA integrity_check` devolvió `ok`.
- 18 módulos JavaScript comprobados sintácticamente, con imports existentes y sin referencias globales accidentales.
- Cuatro pruebas Python: registro/login/logout, persistencia de setlists, importación ZIP y conversión real a FLAC, acceso `/songs/...`, servicio web y rechazo de conflictos de migración.
- Dos pruebas Chromium con audio de prueba: reproducción con Signalsmith, velocidad 1/tempo conservado, exclusiones de batería/click/guía, mute, pause, loop, conservación de tono entre canciones, botones de Edición/Show, marca ORIGINAL, selección y encendido de pad, temas claro/oscuro.
- Capturas revisadas a 932×430; las transiciones se finalizaron antes de capturar. Se preservó la cascada CSS original.
- Build web regenerado con únicamente `assets`, `index.html`, `js`, `styles` y `vendor`. Sin biblioteca, base de datos ni respaldos.
- Sincronización Android y copia iOS de Capacitor completadas.
- El motor C++ permanece sin cambios. No se creó un commit.

## Límites de la comprobación

- Android: Gradle arrancó con Java 21, pero la compilación se detuvo por ausencia de Android SDK configurado. Instalar/configurar el SDK y establecer `ANDROID_HOME` o `sdk.dir` en `android/local.properties` (archivo local ignorado), después ejecutar `npm run android:build`.
- iOS: no se ejecutó Xcode en Windows. El workflow macOS se corrigió para usar el proyecto Xcode existente con Swift Package Manager, en lugar de un workspace inexistente. Falta ejecutar ese workflow y completar firma/distribución.
- Pinegrow: referencias del proyecto actualizadas a `src/index.html`; no se automatizó la aplicación de escritorio Pinegrow.
- Las pruebas de audio verifican el flujo y los nodos del navegador. No sustituyen una escucha de calidad, mediciones de latencia ni pruebas físicas en Android/iPhone/iPad.
- Se mantienen avisos heredados de Python sobre `datetime.utcnow()`; no afectan estas pruebas y no se cambió la semántica de sesiones en una reorganización estructural.

Ejecutar `npm test` y `npm run test:browser` para repetir las regresiones. Los tests utilizan datos temporales o rutas interceptadas; no modifican la biblioteca real.
