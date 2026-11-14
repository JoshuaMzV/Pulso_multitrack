# Estado del producto

Actualizado: 2026-11-03.

## Implementado

- UI JavaScript/HTML/CSS con Show y Edición, temas claro/oscuro y diseño para móvil horizontal.
- Reproducción y mezcla Web Audio, arreglos/secciones, loop y setlists.
- Faders de −60 a +10 dB, retorno a 0 dB con doble clic, ajuste por teclado y sincronización del master entre vistas.
- Onda de Edición basada en picos aproximados del audio cargado, escalada por ganancia y con aviso rojo sobre 0 dBFS. No representa sonoridad LUFS ni normalización automática.
- Perfil al pie de la columna de Edición y acceso compacto para agregar canciones.
- Transposición mediante Signalsmith Stretch conservando tempo; exclusiones de click, guía y batería/percusiones.
- Tonalidad por canción y señalización del tono original; controles de Show y Edición comparten estado.
- Pads continuos actuales sintetizados, selección manual de nota y seguimiento de canción.
- Servidor local con autenticación SQLite, grupos, catálogo, importación ZIP/FLAC y setlists.
- Proyecto Capacitor para Android/iOS. Desarrollo y comprobaciones web en PC.

## Pendiente o propuesta

- Biblioteca de pads profesionales producidos con VST y muestras propias, incorporada localmente a la app. Familias planteadas: Cálido, Aire y Amplio.
- Se discutieron cuatro notas ancla por familia (C, D#, F#, A), con desplazamientos cercanos y posible prerender de las doce tonalidades. Es una propuesta que requiere pruebas auditivas; no existe un límite universal de semitonos sin artefactos.
- La biblioteca grabada no se implementa en esta reorganización. Los pads actuales siguen usando síntesis.
- Integración profunda del motor C++ con las plataformas móviles, medición de latencia y validación de audio en dispositivos físicos.
- Firma/distribución iOS. Un IPA sin firma producido por CI no equivale a una aplicación instalable mediante el flujo normal de Apple.

## Dirección

Priorizar libertad durante la interpretación: loops, cambios de sección, transiciones a pads y espacio para músicos reales. La latencia inferior a 5 ms es una aspiración, no una medición certificada del producto actual.
