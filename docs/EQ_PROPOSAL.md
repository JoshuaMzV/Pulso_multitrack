# Propuesta de ecualización — pendiente de implementación

Propuesta inicial: EQ paramétrica de cuatro bandas por stem y en el master.

- Graves: filtro shelf, punto inicial 100 Hz.
- Medios bajos: campana, punto inicial 400 Hz.
- Medios altos: campana, punto inicial 2,5 kHz.
- Agudos: filtro shelf, punto inicial 10 kHz.

Todas las bandas parten de 0 dB. Ganancia propuesta ±12 dB, frecuencia ajustable y Q ajustable en las dos campanas. Añadir bypass, restablecer, curva de respuesta y compensación manual de salida; no activar realces automáticamente. Botón EQ en cada canal que abre un panel común adaptable a móvil, sin ampliar el mezclador permanentemente.

Usar BiquadFilterNode de Web Audio, con parámetros suavizados al cambiar. Esta API ofrece filtros shelf y peaking con frecuencia, ganancia y Q: https://developer.mozilla.org/en-US/docs/Web/API/BiquadFilterNode . Medir el coste y la reproducción junto a Signalsmith en Android/iOS antes de afirmar una latencia determinada.

Integración propuesta: después del transpositor, antes de la ganancia por stem, conservando la compensación temporal de las pistas excluidas. El master tendría su EQ antes del compresor existente. Los nodos de entrada y ganancia deben seguir separados para que las reconexiones del transpositor no omitan el EQ. Revisar los envíos auxiliares.

Click y talkback actualmente van directamente a la salida: tendrían EQ individual, pero no pasarían por el EQ master mientras se conserve ese enrutamiento. Las otras pistas sí pasan por master. La interfaz debe expresar qué controla el master.

Guardar ajustes de stems por canción y los del master por configuración de salida, con versión de esquema y migración neutra. Evitar que una pista herede accidentalmente el EQ de otra canción que comparta identificador.

La onda de Edición representa actualmente picos aproximados del archivo multiplicados por la ganancia. No representa aún la señal después del EQ; mantener esa distinción y usar medidores de salida para mostrar saturación real.

Una EQ de cuatro bandas ya es multibanda. Compresión multibanda sería otra función: primero acordar si hacen falta más bandas de EQ o control dinámico por banda. Se propone dejar EQ dinámica/compresión multibanda para otra fase.

Validación prevista: respuesta neutra inicial, frecuencias y ganancias, bypass, cambio de canción, persistencia, clipping, sincronía con transposición y uso prolongado en dispositivos móviles.
