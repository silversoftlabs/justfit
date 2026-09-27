# Reglas del Proyecto - Armario Virtual

## Reglas Principales de Búsqueda y Edición
- Antes de buscar con grep o explorar carpetas, consulta el grafo local con: `graphify query "<termino>"`
- Si editas o escribes código nuevo, lee directamente el archivo.

## Principios Generales (Modo Thermos / Anti-Slop)
- **Sé directo y conciso:** Cero texto de relleno, sin saludos ni explicaciones innecesarias.
- **Orientado a la acción:** Ve directo a las modificaciones de código, comandos de terminal o llamadas a herramientas.
- **Cambios mínimos:** Modifica únicamente las líneas necesarias. No reescribas archivos completos a menos que se solicite.
- **Sin explicaciones obvias:** No expliques el código antes de escribirlo ni resumas cambios evidentes.

## Entorno y Comandos
- **Framework:** Flutter (Dart)
- **Nombre del Proyecto:** `armario_virtual`
- **Comandos Clave:**
  - Build/Run: `flutter run`
  - Analizar: `flutter analyze`
  - Tests: `flutter test`
  - Dependencias: `flutter pub get`

## Estilo y Estándares de Código
- Sigue las convenciones estándar de Dart/Flutter (`snake_case` para archivos/carpetas, `PascalCase` para clases, `camelCase` para variables).
- Mantén la inmutabilidad siempre que sea posible (constructores `const`).
- Mantén los widgets pequeños y modulares.
- Garantiza un manejo adecuado de errores y null safety estricto en los servicios.

## Arquitectura y Gestión de Estado
- **Gestión de Estado:** Mantén una arquitectura consistente en todas las funcionalidades.
- **Estructura de Carpetas:** Organiza el código por funciones (feature-first) o por capas bajo `lib/`.
- **Modelos de Datos:** Implementa serialización adecuada (`fromJson`, `toJson`) y gestiona el null safety.

## UI/UX y Guías de Diseño
- **Diseños Responsivos:** Diseña widgets adaptables a diferentes tamaños de pantalla (`LayoutBuilder`, `MediaQuery`, `Expanded`/`Flexible`).
- **Assets e Iconos:** Guarda imágenes e iconos en `assets/` y regístralos en `pubspec.yaml`.
- **Inspección Visual:** Usa Puppeteer MCP cuando se solicite revisar la interfaz en web, validar la alineación de elementos y comprobar contrastes.

## Uso de Herramientas MCP
- **Puppeteer:** Utilízalo para validación de renderizado visual, capturas de pantalla y depuración de UI.
- **Memory:** Consulta y actualiza nodos del grafo de conocimiento al definir decisiones arquitectónicas complejas.

## Seguridad y Restricciones
- **Dependencias:** Consulta antes de agregar nuevos paquetes a `pubspec.yaml`.
- **Cambios Críticos:** Evita refactorizar widgets compartidos principales sin verificar sus usos en la app.
- **Verificación:** Ejecuta `flutter analyze` o los tests correspondientes tras refactorizaciones importantes para asegurar la estabilidad.