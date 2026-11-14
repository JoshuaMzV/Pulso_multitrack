# Arquitectura actual de PULSO

## Flujo de ejecución

La página `src/index.html` carga fuentes y librerías locales, estilos y `js/main.js`. Los módulos ES comparten una única instancia de `state/store.js`. `main.js` inicializa los subsistemas en el orden del prototipo para conservar la creación de controles y las suscripciones.

- `audio/`: contexto y mezcla, stems/Signalsmith, transporte, pads y transpose.
- `ui/`: mixer, timeline, medidores, Show, controles y setlists.
- `services/`: autenticación, catálogo, carga/IndexedDB y configuración de endpoints.
- `state/`: almacén e inicialización de estado.
- `ui/legacy-actions.js`: puente explícito para handlers HTML existentes. No es una segunda instancia de estado.

Los módulos pueden importar funciones entre sí, pero no ejecutan reproducción al importarse. La inicialización explícita evita depender del orden de evaluación de ciclos entre módulos. Las próximas mejoras deben reducir gradualmente estos acoplamientos por componente, sin reescribir el reproductor.

## Estilos

`styles/base.css` importa tokens, shell, temas y componentes en el orden original de la cascada. `styles/show.css` conserva la capa posterior de Show. No se reordenan overrides del tema durante una extracción estructural.

## API y datos

`backend/local_server.py` crea Flask y registra los blueprints de autenticación/grupos, canciones, setlists, sistema y web. Los servicios contienen autenticación SQLite, importación/conversión y clasificación de stems. `backend/config.py` centraliza rutas.

El servidor sirve `src/` en desarrollo y `/songs/...` desde `data/songs/`. La base SQLite, setlists y temporales viven bajo `PULSO_DATA_DIR` o `data/`. Las direcciones y formatos de las APIs previas se mantienen. El esquema PostgreSQL conservado en `backend/database/schema.sql` es histórico y no se ejecuta en este servidor SQLite.

## Empaquetado

El build copia exclusivamente fuentes y dependencias web a `www/`. Capacitor conserva `webDir: www`; canciones y datos personales no se incluyen. Las fuentes, iconos, JSZip y Signalsmith se sirven localmente. El catálogo remoto sigue necesitando conectividad.

Los proyectos Android/iOS permanecen en la raíz. El motor `engine/` no cambia y su integración profunda con Capacitor sigue pendiente. CI genera la web antes de sincronizar. El artefacto iOS sin firma requiere un proceso posterior de firma y distribución.

## Decisiones

1. JavaScript nativo y HTML editable en Pinegrow, sin introducir framework.
2. Estado compartido único y puente temporal de eventos para minimizar regresiones.
3. Separación estricta de datos, fuente y salida generada.
4. Desarrollo local en PC independiente del empaquetado móvil.
5. Sin cambios musicales ni rediseño de pads dentro de esta reorganización.

Ver [desarrollo](DEVELOPMENT.md), [estado del producto](PRODUCT_STATE.md) y [migración](MIGRATION.md). El diseño anterior se conserva en [archivo histórico](archive/ARCHITECTURE_PLAN_LEGACY.md).
