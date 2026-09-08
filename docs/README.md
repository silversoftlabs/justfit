# `docs/` — Política de privacidad (GitHub Pages)

Esta carpeta se publica como sitio web con **GitHub Pages** para tener una URL
pública de la política de privacidad (obligatoria en Google Play).

| Archivo | Para qué |
|---|---|
| `index.html` | Página publicada. Diseño accesible, tema claro/oscuro automático. Es lo que sirve GitHub Pages en la raíz del sitio. |
| `politica-de-privacidad.md` | Texto fuente en Markdown. Si editas la política, cambia **este** archivo y vuelca los cambios a `index.html`. |
| `.nojekyll` | Archivo vacío. Le dice a GitHub Pages que sirva la carpeta tal cual, sin procesarla con Jekyll. No lo borres. |

Al editar la política: actualiza la fecha de "Última actualización" en **los dos**
archivos y, cuando el cambio sea de fondo, avisa en la ficha de Play.

---

## Cómo activar GitHub Pages (pestaña *Settings* del repositorio)

**Requisito previo:** el repositorio tiene que estar subido a GitHub. Si el
repositorio es **privado**, GitHub Pages solo funciona con un plan de pago
(GitHub Pro / Team); si es gratuito, hazlo **público** o usa un repo aparte solo
para la política.

1. Abre el repositorio en <https://github.com> e inicia sesión.
2. Pulsa **Settings** (engranaje, arriba a la derecha, en la barra del repo).
3. En el menú lateral izquierdo, dentro de la sección *Code and automation*,
   pulsa **Pages**.
4. En **Build and deployment → Source**, elige **Deploy from a branch**.
5. En **Branch**:
   - Rama: **`main`** (o `master`, la que uses).
   - Carpeta: **`/docs`**.
   - Pulsa **Save**.
6. Espera entre 30&nbsp;s y ~2&nbsp;min y **recarga la página de Settings → Pages**.
   Aparecerá un recuadro verde: *"Your site is live at"* con la URL.
7. La política queda publicada en:

   ```
   https://<usuario>.github.io/<repositorio>/
   ```

   (Como `index.html` está en la raíz de `/docs`, la política se ve directamente
   en esa URL, sin añadir nada detrás.)

8. Comprueba la URL en el navegador (móvil y escritorio, tema claro y oscuro).

### Poner la URL en Google Play

- Play Console → tu app → **Contenido de la app → Política de privacidad** →
  pega la URL de arriba → **Guardar**.

### Cada vez que cambies la política

Haz `commit` y `push` a la rama configurada. GitHub Pages reconstruye el sitio
solo en 1–2 min. Si no ves el cambio, prueba con recarga forzada
(Ctrl/Cmd + Shift + R).

### Opcional — dominio propio

Settings → Pages → **Custom domain**: escribe tu dominio (p. ej.
`privacidad.justfit.app`), guarda, y añade en tu proveedor DNS un registro
`CNAME` apuntando a `<usuario>.github.io`. Marca **Enforce HTTPS** cuando se
habilite.
