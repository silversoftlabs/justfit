# Política de Privacidad de Justfit

**Última actualización:** 6 de septiembre de 2026

Esta política explica qué información trata la aplicación **Justfit** ("la App"),
con qué finalidad y con quién se comparte.

Responsable del tratamiento: **silversoftlabs** (el "desarrollador").
Contacto: **silversoftlabs@gmail.com**

---

## 1. Resumen

Justfit es un armario digital. Puedes fotografiar tu ropa, organizarla, crear
conjuntos y recibir una sugerencia de outfit según el tiempo que hace en tu
ciudad.

- **Tus fotos y tu armario se guardan solo en tu dispositivo.** No se suben a
  ningún servidor del desarrollador ni de terceros.
- La App **no tiene cuentas de usuario ni inicio de sesión**.
- La App **no muestra publicidad** ni utiliza servicios de seguimiento
  publicitario.
- La App **no vende ni cede** datos personales.
- La App se conecta a Internet únicamente para: (a) consultar la previsión
  meteorológica, (b) enviar informes de errores para mejorar la estabilidad y
  (c) descargar una única vez un componente del sistema de recorte de imágenes.

---

## 2. Información que se trata y dónde se guarda

### 2.1 Datos que permanecen en tu dispositivo (no se transmiten)

| Dato | Para qué | Dónde se guarda |
|---|---|---|
| Fotografías de prendas (cámara o galería) | Mostrar y organizar tu armario | Almacenamiento privado de la App |
| Prendas, conjuntos, favoritos, historial y planificación de outfits | Funcionamiento de la App | Almacenamiento privado de la App |
| Nombre de perfil | Personalizar la pantalla de perfil | Almacenamiento privado de la App |
| Preferencias: idioma, tema claro/oscuro, ciudad indicada en el onboarding, estado del onboarding | Recordar tu configuración | Almacenamiento privado de la App |

El procesamiento de las fotos (mejora de imagen, recorte del fondo de la prenda,
extracción de color) se realiza **íntegramente en tu dispositivo**. Las imágenes
no salen del teléfono.

Si desinstalas la App, todos estos datos se eliminan del dispositivo.

### 2.2 Datos que se envían a terceros

**a) Previsión meteorológica y búsqueda de ciudades — Open-Meteo**

Para la función "Outfit del día" y el buscador de ubicación, la App envía a
Open-Meteo (open-meteo.com) **el nombre de la ciudad que tú escribes** y/o sus
**coordenadas aproximadas** (las de la ciudad, no las de tu posición exacta).

- La App **no accede al GPS ni a la ubicación del dispositivo**. La ubicación la
  eliges manualmente escribiendo el nombre de una ciudad.
- Estas peticiones no incluyen tu nombre, identificadores del dispositivo ni
  ningún dato de cuenta. Open-Meteo no requiere registro ni clave de API.
- Información de Open-Meteo: <https://open-meteo.com/en/terms>

**b) Informes de errores — Firebase Crashlytics (Google)**

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

**c) Componente de recorte de imágenes — Google Play Services (ML Kit)**

La primera vez que recortas una prenda, la App puede descargar de Google Play
Services un modelo de segmentación de imágenes. Es una descarga de software; **tus
fotos no se envían a Google** en este proceso. El recorte se ejecuta después en
tu dispositivo.

---

## 3. Permisos que solicita la App

| Permiso | Motivo |
|---|---|
| **Cámara** | Hacer fotos de tus prendas. Puedes usar solo la galería si lo prefieres. |
| **Internet** | Consultar el tiempo, enviar informes de errores y descargar el componente de recorte. |

La App **no** solicita permisos de ubicación, micrófono, contactos, ni acceso
al almacenamiento compartido más allá del selector de imágenes del sistema.

---

## 4. Finalidades y base jurídica (RGPD)

| Finalidad | Base jurídica |
|---|---|
| Prestar las funciones de la App (armario, conjuntos, tiempo) | Ejecución de la relación contractual / uso de la App solicitado por ti (art. 6.1.b RGPD) |
| Consultar el tiempo con la ciudad que indicas | Consentimiento al introducir la ciudad y usar la función (art. 6.1.a RGPD) |
| Diagnóstico de fallos y mejora de la estabilidad | Interés legítimo en mantener la App segura y funcional (art. 6.1.f RGPD) |

---

## 5. Conservación de los datos

- **Datos en el dispositivo:** se conservan mientras la App esté instalada o
  hasta que borres sus datos o el contenido concreto.
- **Informes de errores en Firebase Crashlytics:** Google los conserva un máximo
  de **90 días**.
- **Peticiones a Open-Meteo:** las gestiona Open-Meteo según su propia política;
  no se asocian a una identidad.

---

## 6. Destinatarios

No vendemos ni cedemos datos personales. Solo intervienen como proveedores:

- **Google** (Firebase Crashlytics, Google Play Services) — informes de errores y
  distribución de componentes.
- **Open-Meteo** — previsión meteorológica y geocodificación de ciudades.

Estos proveedores pueden tratar datos fuera del Espacio Económico Europeo (por
ejemplo, en Estados Unidos). En esos casos, las transferencias se amparan en las
Cláusulas Contractuales Tipo de la Comisión Europea u otros mecanismos válidos
previstos por el RGPD.

---

## 7. Tus derechos

Puedes ejercer los derechos de acceso, rectificación, supresión, limitación,
oposición y portabilidad:

- **Datos en el dispositivo:** puedes consultarlos, editarlos o eliminarlos
  directamente en la App, o borrar todos los datos de la App desde los ajustes
  del sistema operativo.
- **Informes de errores:** escríbenos a **silversoftlabs@gmail.com** y solicitaremos
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

**silversoftlabs**
Correo: **silversoftlabs@gmail.com**
