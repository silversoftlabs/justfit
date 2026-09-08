# Política de Privacidad de Justfit

**Última actualización:** 8 de septiembre de 2026

Esta política explica qué información trata la aplicación **Justfit** ("la App"),
con qué finalidad y con quién se comparte.

Responsable del tratamiento: **gamusinlab** (el "desarrollador").
Contacto: **gamusinlab@gmail.com**

---

## 1. Resumen

Justfit es un armario digital. Puedes fotografiar tu ropa, organizarla, crear
conjuntos, planificar tus outfits en un calendario y recibir una sugerencia de
outfit según el tiempo que hace en tu ciudad.

- **Tus fotos y tu armario se guardan solo en tu dispositivo.** No se suben a
  ningún servidor del desarrollador ni de terceros.
- **El recorte del fondo de las prendas se hace 100 % en tu dispositivo con
  ONNX Runtime** (modelo U2-Net incluido en la App). La App **no descarga ningún
  componente adicional después de instalarse** para esta función, y tus fotos
  **no se envían a Google ni a ningún otro servicio** para recortarlas.
- Las **sugerencias de outfit ("IA")**, la mejora de imagen y la extracción de
  color también se calculan **íntegramente en tu dispositivo**.
- La App **no tiene cuentas de usuario ni inicio de sesión**.
- La App **no muestra publicidad** ni utiliza servicios de seguimiento
  publicitario.
- La App **no vende ni cede** datos personales.
- La App se conecta a Internet únicamente para: (a) consultar la previsión
  meteorológica y buscar/identificar ciudades y (b) mostrar el mapa para elegir
  la ubicación del tiempo y (c) enviar informes de errores para mejorar la
  estabilidad.
- La App **no accede al GPS ni a la ubicación real de tu dispositivo**. La
  ubicación para el tiempo la eliges tú manualmente: escribiendo el nombre de una
  ciudad o marcando un punto en un mapa.

---

## 2. Información que se trata y dónde se guarda

### 2.1 Datos que permanecen en tu dispositivo (no se transmiten)

| Dato | Para qué | Dónde se guarda |
|---|---|---|
| Fotografías de prendas (cámara o galería) | Mostrar y organizar tu armario | Almacenamiento privado de la App |
| Prendas y sus atributos (categoría, color, estilo, temporada, tipo, favorito, archivado) | Funcionamiento de la App y generación de outfits | Almacenamiento privado de la App |
| Conjuntos favoritos, historial de outfits usados y planificación de outfits del calendario | Funcionamiento de la App | Almacenamiento privado de la App |
| Preferencias del armario: estilo principal, estación activa, categorías personalizadas y reglas de combinación (texto que tú escribes) | Personalizar la organización y las sugerencias | Almacenamiento privado de la App |
| Nombre de perfil | Personalizar la pantalla de perfil | Almacenamiento privado de la App |
| Preferencias generales: idioma, tema claro/oscuro, ciudad y coordenadas elegidas, si has completado el onboarding | Recordar tu configuración | Almacenamiento privado de la App |

**Todo el procesamiento de imágenes ocurre en tu dispositivo:**

- **Recorte del fondo de la prenda:** modelo U2-Net ejecutado con **ONNX Runtime**
  (el modelo viaja dentro de la App, no se descarga nada). Si el recorte no
  encuentra la prenda, se conserva la foto mejorada sin recortar.
- **Mejora de imagen y extracción de color:** cálculo local sobre los píxeles de
  la foto.
- **Sugerencias de outfit:** un motor de reglas local. No se envían tus fotos,
  tu armario ni tus preferencias a ningún servicio de inteligencia artificial.

Las imágenes y tus preferencias **no salen del teléfono**.

La App incluye además un listado local de localidades (nombres y coordenadas)
elaborado a partir de los datos abiertos de **GeoNames.org** (licencia CC BY 4.0),
que se consulta **en el dispositivo** para completar el buscador de ciudades en
municipios pequeños. Consultar ese listado **no genera ninguna petición a
GeoNames**.

Las **reglas de combinación** son un campo de texto libre: te recomendamos no
escribir en ellas datos personales o sensibles, ya que se guardan como el resto
de la configuración de la App.

Si desinstalas la App, todos estos datos se eliminan del dispositivo.

### 2.2 Datos que se envían a terceros

**a) Previsión meteorológica y búsqueda de ciudades — WeatherAPI.com**

Para la función "Outfit del día", el buscador de ubicación y el mapa, la App
envía a **WeatherAPI.com** (weatherapi.com):

- **El nombre de la ciudad que tú escribes** en el buscador, y/o
- **Las coordenadas del punto que tú eliges**: en el buscador son las del centro
  de la localidad; en el mapa son las del punto exacto que marcas arrastrando el
  pin (que no es tu posición real, sino el punto que decides señalar).

Con esas coordenadas la App consulta el tiempo y, en el caso del mapa, pide
también a WeatherAPI.com el nombre de la localidad más cercana para no guardar
una ubicación "sin nombre".

- La App **no accede al GPS ni a la ubicación del dispositivo**.
- Estas peticiones no incluyen tu nombre, identificadores del dispositivo ni
  ningún dato de cuenta tuyo. Las peticiones viajan con una clave de API propia
  del desarrollador (no personal ni asociada a ti) que exige WeatherAPI.com para
  identificar a la App como cliente de su servicio.
- Información de WeatherAPI.com: <https://www.weatherapi.com/terms.aspx> y
  <https://www.weatherapi.com/privacy.aspx>

**b) Teselas del mapa de ubicación — OpenStreetMap**

Si abres el mapa para elegir la ubicación del tiempo, la App descarga las
imágenes del mapa ("teselas") de los servidores estándar de la **OpenStreetMap
Foundation** (`tile.openstreetmap.org`). Sobre esas teselas se aplica un filtro
de color en el dispositivo para adaptarlas al tema oscuro; la App **no utiliza
los mapas base de CARTO / CartoDB** ni ningún otro proveedor de teselas.

En esas peticiones tu dispositivo transmite:

- Tu **dirección IP** (inevitable en cualquier conexión a Internet).
- La **zona del mapa que estás viendo** (las teselas concretas que se solicitan),
  que refleja el área que consultas mientras eliges el punto.
- Un identificador de la App (`User-Agent`: `com.gamusinlab.justfit`), exigido
  por la política de uso de OpenStreetMap. No te identifica a ti.

Estas peticiones **solo se producen mientras el mapa está abierto**. No se envía
tu nombre, tu armario ni ningún dato de cuenta. El tratamiento que hace la
OpenStreetMap Foundation de estos datos se rige por su propia política:
<https://wiki.osmfoundation.org/wiki/Privacy_Policy> y las condiciones de uso de
las teselas <https://operations.osmfoundation.org/policies/tiles/>.

**c) Informes de errores — Firebase Crashlytics (Google)**

La App utiliza Firebase Crashlytics, de Google Ireland Limited / Google LLC, para
detectar y corregir fallos. Cuando la App se cierra de forma inesperada o
registra un error, se envía un informe que puede incluir:

- Tipo de error y traza de la pila (stack trace).
- Modelo del dispositivo, fabricante, versión del sistema operativo, idioma,
  memoria y espacio disponibles, estado de la App en el momento del fallo.
- Versión de la App y fecha/hora del evento.
- Un identificador de instalación generado aleatoriamente (Firebase Installation
  ID), que permite agrupar los fallos de una misma instalación. No identifica tu
  persona y se elimina si desinstalas la App o borras sus datos.

Estos informes **no incluyen tus fotos ni el contenido de tu armario**. Los
informes de errores están activados en la versión publicada de la App.

- Política de privacidad de Firebase/Google:
  <https://firebase.google.com/support/privacy>
- Cómo trata Google los datos de Firebase:
  <https://firebase.google.com/terms/data-processing-terms>

---

## 3. Permisos que solicita la App

| Permiso | Motivo |
|---|---|
| **Cámara** | Hacer fotos de tus prendas. Puedes usar solo la galería si lo prefieres. |
| **Internet** | Consultar el tiempo, mostrar el mapa de ubicación y enviar informes de errores. |

La App **no** solicita permisos de ubicación, micrófono, contactos, ni acceso
al almacenamiento compartido más allá del selector de imágenes del sistema.

---

## 4. Finalidades y base jurídica (RGPD)

| Finalidad | Base jurídica |
|---|---|
| Prestar las funciones de la App (armario, conjuntos, calendario, sugerencias) | Ejecución de la relación contractual / uso de la App solicitado por ti (art. 6.1.b RGPD) |
| Consultar el tiempo y resolver la ciudad con la ubicación que tú indicas | Consentimiento al introducir la ubicación y usar la función (art. 6.1.a RGPD) |
| Mostrar el mapa de OpenStreetMap para elegir la ubicación | Consentimiento al abrir el mapa (art. 6.1.a RGPD) |
| Diagnóstico de fallos y mejora de la estabilidad | Interés legítimo en mantener la App segura y funcional (art. 6.1.f RGPD) |

---

## 5. Conservación de los datos

- **Datos en el dispositivo:** se conservan mientras la App esté instalada o
  hasta que borres sus datos o el contenido concreto.
- **Informes de errores en Firebase Crashlytics:** Google los conserva un máximo
  de **90 días**.
- **Peticiones a WeatherAPI.com y a OpenStreetMap:** las gestiona cada proveedor
  según su propia política; la App no las almacena ni las asocia a una identidad.

---

## 6. Destinatarios

No vendemos ni cedemos datos personales. Solo intervienen como proveedores:

- **Google** (Firebase Crashlytics) — informes de errores.
- **WeatherAPI.com** — previsión meteorológica y geocodificación de ciudades.
- **OpenStreetMap Foundation** (Reino Unido) — imágenes del mapa de ubicación.

Estos proveedores pueden tratar datos fuera del Espacio Económico Europeo (por
ejemplo, en Estados Unidos o el Reino Unido). En esos casos, las transferencias
se amparan en decisiones de adecuación de la Comisión Europea, en las Cláusulas
Contractuales Tipo u otros mecanismos válidos previstos por el RGPD.

---

## 7. Tus derechos

Puedes ejercer los derechos de acceso, rectificación, supresión, limitación,
oposición y portabilidad:

- **Datos en el dispositivo:** puedes consultarlos, editarlos o eliminarlos
  directamente en la App, o borrar todos los datos de la App desde los ajustes
  del sistema operativo.
- **Informes de errores:** escríbenos a **gamusinlab@gmail.com** y solicitaremos
  a Google la eliminación de los datos asociados a tu identificador de
  instalación, en la medida en que sea técnicamente posible.

También tienes derecho a presentar una reclamación ante la autoridad de control
competente (en España, la Agencia Española de Protección de Datos,
<https://www.aepd.es>).

---

## 8. Menores

Justfit no está dirigida a menores de 14 años y no recopila conscientemente datos
de menores de esa edad.

---

## 9. Cambios en esta política

Si modificamos esta política, publicaremos la versión actualizada en esta misma
dirección y cambiaremos la fecha de "Última actualización". Los cambios
significativos se comunicarán, cuando proceda, dentro de la App o en la ficha de
Google Play.

---

## 10. Contacto

**gamusinlab**
Correo: **gamusinlab@gmail.com**
