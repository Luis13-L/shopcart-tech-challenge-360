# ShopCart — Tech Challenge 360

Plataforma de comercio electrónico desarrollada para el **Tech Challenge 360**. La solución prioriza integridad de datos, seguridad, concurrencia, idempotencia y trazabilidad de las operaciones de compra.

> **Estado del repositorio (Fase 1):** backend Node.js/Express/TypeScript y base de datos SQL Server implementados mediante migraciones `001`–`050`, con pruebas SQL y verificaciones manuales. **Fase 2:** interfaz React/TypeScript e integración visual pendientes. Los detalles y las limitaciones se presentan al final.

## 1. Tecnologías

| Componente | Tecnología |
|---|---|
| Backend | Node.js 24, Express 5, TypeScript |
| Base de datos | SQL Server 2019+ y T-SQL |
| Persistencia | Stored Procedures parametrizados con `mssql`, sin ORM |
| Validaciones | Zod |
| Autenticación | bcrypt, JWT (`jose`) y refresh tokens rotativos |
| Seguridad HTTP | Helmet, CORS, rate limiting y autorización por roles |
| Pruebas | Scripts SQL, SSMS y Postman |
| Frontend planificado | React + TypeScript |
| Imágenes planificadas para la demo | Archivos estáticos WebP y referencias URL en SQL Server |

## 2. Arquitectura

```text
Cliente HTTP / React (Fase 2)
             |
             v
Router → Middleware → Controller → Service → Repository
                                              |
                                              v
                                      Stored Procedure
                                              |
                                              v
                                          SQL Server
```

- **Router:** expone las rutas y aplica los controles de acceso iniciales.
- **Middleware:** valida JWT y rol cuando corresponde.
- **Controller:** valida entrada, transforma solicitudes y asigna códigos HTTP.
- **Service:** representa los casos de uso y coordina la capa de acceso.
- **Repository:** ejecuta Stored Procedures con parámetros tipados.
- **SQL Server:** aplica restricciones de integridad, autorización sensible, transacciones, bloqueos, auditoría e idempotencia.

**Justificación:** esta separación permite probar y mantener cada responsabilidad de forma independiente. No se utiliza un ORM ni consultas SQL de negocio embebidas en los repositorios, de acuerdo con el enfoque requerido por el reto.

## 3. Instalación desde cero

### Requisitos

- Node.js 24 y npm.
- SQL Server 2019 o superior, con autenticación SQL Server habilitada.
- SQL Server Management Studio (SSMS) o herramienta compatible con scripts T-SQL y `GO`.
- Git.
- Cuenta administrativa de SQL Server **únicamente para instalación y migraciones**.

La base de datos se denomina `ShopCartDB`. La API utiliza el puerto `3000` por defecto. El puerto de SQL Server depende de cada instalación (`14333` en el archivo de ejemplo es ilustrativo).

### Paso 1. Clonar repositorio

```powershell
git clone https://github.com/Luis13-L/shopcart-tech-challenge-360.git
cd shopcart-tech-challenge-360
```

### Paso 2. Crear la base de datos

Desde SSMS, con una cuenta administrativa:

```text
database/migrations/001_CreateDatabase.sql
```

### Paso 3. Crear el login de la API

En SSMS: **Security → Logins → New Login**.

- Login: `shopcart_api`.
- Autenticación: **SQL Server Authentication**.
- Contraseña: robusta, local y no incluida en el repositorio.
- Base predeterminada: `ShopCartDB`.
- No conceder `sysadmin`, `db_owner`, `db_datareader` ni `db_datawriter`.

La migración `011_SystemHealthProcedure.sql` vincula este login con un usuario de `ShopCartDB` si es necesario y habilita los permisos iniciales de ejecución.

### Paso 4. Aplicar migraciones

Ejecutar **una a una, en orden numérico**, las migraciones restantes:

```text
database/migrations/002_SecurityTables.sql
...
database/migrations/045_FixVariantInventoryInitialization.sql
database/migrations/046_CustomerAddressesProcedures.sql
database/migrations/047_CustomerOrderHistoryProcedures.sql
database/migrations/048_InventoryApiProcedures.sql
database/migrations/049_DiscountedOrderReturns.sql
database/migrations/050_CategoryScopedCoupons.sql
```

**No omitir números ni ejecutar la migración 050 antes de la 049.** Las migraciones modifican objetos persistentes y deben ejecutarse con la cuenta administrativa; la identidad `shopcart_api` solo debe ejecutar los procedimientos autorizados.

El registro de aplicación se encuentra en `dbo.SchemaMigrations`. Para inspeccionarlo:

```sql
USE ShopCartDB;
SELECT Numero, Nombre, FechaAplicacion
FROM dbo.SchemaMigrations
ORDER BY Numero;
```

**Nota sobre la migración 050:** adapta los procedimientos de checkout y devoluciones existentes para soportar cupones por categoría. Si se obtiene un error, no se deben eliminar ni recrear manualmente procedimientos o tablas. Revisar el error y la versión exacta de los scripts.

### Paso 5. Datos iniciales

Ejecutar:

```text
database/seeds/001_InitialData.sql
```

Crea los roles `Cliente`, `Operador` y `Administrador`, una categoría y un producto de ejemplo. No distribuye contraseñas administrativas predeterminadas.

### Paso 6. Configurar la API

```powershell
cd apps/api
npm ci
Copy-Item .env.example .env
```

Editar `apps/api/.env` con los datos **locales**:

```dotenv
NODE_ENV=development
PORT=3000
CORS_ORIGIN=http://localhost:5173
JWT_SECRET=REEMPLAZAR_CON_SECRETO_ALEATORIO
SQL_SERVER=localhost
SQL_PORT=14333
SQL_DATABASE=ShopCartDB
SQL_USER=shopcart_api
SQL_PASSWORD=REEMPLAZAR_CON_PASSWORD_LOCAL
```

Generar `JWT_SECRET` con:

```powershell
node -e "console.log(require('node:crypto').randomBytes(48).toString('base64url'))"
```

Configurar el puerto real del servidor SQL y reemplazar todas las variables de ejemplo. **No subir `.env` ni credenciales al repositorio.**

```powershell
npm run build
npm run dev
```

### Paso 7. Verificar servicios

```http
GET http://localhost:3000/api/health
GET http://localhost:3000/api/health/db
GET http://localhost:3000/api/catalog/products
GET http://localhost:3000/api/catalog/categories
```

La respuesta de `/api/health/db` debe confirmar la conexión con SQL Server.

## 4. Usuarios de demostración

| Cuenta | Rol |
|---|---|
| `admin.demo@shopcart.test` | Administrador |
| `operador.demo@shopcart.test` | Operador |
| `cliente.demo@shopcart.test` | Cliente |

**Las contraseñas no se publican.** Para crear cuentas en una instalación nueva:

1. Ejecutar `node scripts/generate-demo-hashes.mjs` desde `apps/api` y generar tres hashes bcrypt usando contraseñas diferentes de al menos 12 caracteres. La entrada puede verse en la terminal: realizarlo en un entorno seguro.
2. Copiar `database/seeds/002_DemoUsers.sql` a una ubicación temporal **fuera del repositorio**.
3. Sustituir en esa copia `REEMPLAZAR_HASH_ADMIN`, `REEMPLAZAR_HASH_OPERADOR` y `REEMPLAZAR_HASH_CLIENTE` con los hashes generados.
4. Ejecutar el SQL temporal con una cuenta administrativa y eliminarlo después.

El script evita sobrescribir cuentas existentes y comprueba los roles esperados.

**Inicio de sesión:**

```http
POST http://localhost:3000/api/auth/login
Content-Type: application/json
```

```json
{
  "correo": "admin.demo@shopcart.test",
  "password": "CONTRASENA_LOCAL"
}
```

La API responde con token de acceso y datos de la sesión. Los endpoints protegidos utilizan `Authorization: Bearer <accessToken>`.

## 5. Funcionalidades implementadas en Fase 1

| Requisito | Implementación actual |
|---|---|
| **RF-01 — Usuarios y seguridad** | Registro de clientes, login, JWT, refresh tokens con rotación, roles y restricciones de acceso. |
| **RF-02 — Catálogo** | Listado público paginado con búsqueda, filtros, ordenamiento; administración de productos, categorías y precios; historial de precios. |
| **RF-03 — Inventario** | Existencias físicas, movimientos de kardex con motivo y responsable, reservas vigentes y API para operador/administrador. |
| **RF-04 — Carrito** | Crear/consultar carrito de cliente, agregar/actualizar/eliminar variantes y validar cantidades. |
| **RF-05 — Cupones** | Porcentaje o importe fijo, límites y vigencia; cupón general o restringido a una categoría; integración con checkout y reembolsos. |
| **RF-06 — Compra** | Direcciones del cliente, reserva de stock durante 15 minutos, checkout transaccional con clave de idempotencia y pago simulado. |
| **RF-07 — Pedidos** | Cambios de estado, cancelaciones antes de despacho, devoluciones parciales y totales, importes proporcionales, historial del cliente. |
| **RF-08 — Reportes** | Ventas, categorías, productos destacados y consulta administrativa de pedidos. |
| **RF-09 — Auditoría** | Bitácora de eventos sensibles, registro de movimientos, cambios de estado y modificaciones de catálogo, precios y promociones. |

**Alcance:** la existencia de código, pruebas SQL y endpoints no equivale a una certificación completa. Las pruebas de carga, concurrencia integral y reproducción de instalación desde cero siguen pendientes de ejecución independiente.

### Rutas principales

| Método y ruta | Acceso |
|---|---|
| `GET /api/health` y `GET /api/health/db` | Público |
| `GET /api/catalog/products` | Público |
| `POST /api/catalog/products`, `PATCH /api/catalog/products/:id`, `PATCH /api/catalog/products/:id/status` | Administrador |
| `GET /api/catalog/categories` | Público |
| `GET /api/catalog/categories/admin`, `POST /api/catalog/categories`, `PATCH /api/catalog/categories/:id`, `PATCH /api/catalog/categories/:id/status` | Administrador |
| `PATCH /api/catalog/variants/:id/price` | Administrador |
| `POST /api/auth/register`, `POST /api/auth/login`, `POST /api/auth/refresh`, `POST /api/auth/logout` | Según operación |
| `GET /api/auth/me` | Usuario autenticado |
| `POST /api/cart`, `GET /api/cart/:id`, `PUT /api/cart/items`, `DELETE /api/cart/items/:id` | Cliente |
| `POST /api/addresses`, `GET /api/addresses`, `GET /api/addresses/:id` | Cliente propietario |
| `POST /api/checkout/reservations`, `POST /api/checkout/confirm` | Cliente |
| `GET /api/orders/my`, `GET /api/orders/my/:id` | Cliente propietario |
| `GET /api/orders` | Operador / Administrador |
| `PATCH /api/orders/:id/status`, `POST /api/orders/:id/cancel`, `POST /api/orders/:id/returns` | Según rol y propietario; SQL valida permisos |
| `POST /api/inventory/movements`, `GET /api/inventory/variants/:id`, `GET /api/inventory/variants/:id/movements` | Operador / Administrador |
| `GET /api/coupons`, `POST /api/coupons`, `GET /api/coupons/:id`, `PUT /api/coupons/:id` | Administrador |
| `PATCH /api/coupons/:id/status`, `PATCH /api/coupons/:id/category`, `GET /api/coupons/:id/uses` | Administrador |
| `GET /api/reports/sales`, `GET /api/reports/categories`, `GET /api/reports/top-products` | Administrador |
| `GET /api/audit` | Administrador |

Las comprobaciones sensibles también se realizan en los Stored Procedures para evitar depender exclusivamente del rol registrado en el JWT.

## 6. Decisiones de negocio y seguridad

### Inventario, reservas y concurrencia

Los movimientos de entrada, salida, ajustes y devoluciones se reflejan en el kardex. Las operaciones críticas usan transacciones con bloqueos como `UPDLOCK`/`HOLDLOCK`. La disponibilidad se calcula considerando existencias y reservas activas no vencidas; el stock físico se descuenta al confirmar el checkout.

**Justificación:** evitar sobreventas y conservar trazabilidad. **Costo:** mayor contención ante accesos simultáneos sobre la misma variante.

### Idempotencia

Checkout y devoluciones utilizan claves de idempotencia y hashes de solicitud. Un reintento idéntico recupera su resultado previo; una misma clave con datos distintos produce conflicto.

**Justificación:** proteger operaciones que pueden repetirse por latencia, errores de red o reenvíos del usuario.

### Cupones generales y por categoría

Un cupón general se aplica sobre el subtotal del carrito. Si tiene `IDCategoriaAplicable`, solo se usa el subtotal de esa categoría para comprobar elegibilidad, importe mínimo y descuento.

El pedido conserva `IDCategoriaCupon` como dato histórico, de manera que las devoluciones asignen el descuento únicamente a las líneas elegibles. Los reembolsos aplican redondeo acumulado para evitar diferencias de centavos y no exceder el importe realmente pagado. La categoría de un cupón usado no puede cambiarse.

**Justificación:** el importe reembolsado debe corresponder con el descuento realmente aplicado al comprar, aun cuando posteriormente cambie la configuración del catálogo o del cupón.

### Estados de pedido y devoluciones

```text
PAGADO → PREPARANDO → DESPACHADO → ENTREGADO
   |           |
   └─ CANCELADO ┘

ENTREGADO → DEVUELTO_PARCIAL → DEVUELTO_TOTAL
          └──────────────────→ DEVUELTO_TOTAL
```

La cancelación depende del estado permitido por las reglas de negocio. Las devoluciones se procesan por línea y cantidad pendiente, reintegran inventario, generan movimientos de kardex y conservan la trazabilidad del reembolso.

**Importante:** el sistema usa **pagos simulados**. El cambio a `REEMBOLSADO` es un estado interno; no representa la devolución de dinero en una pasarela real.

### Seguridad

- Contraseñas con hash bcrypt, nunca texto plano.
- JWT de acceso de corta duración y refresh tokens con rotación/revocación; almacenamiento de hashes de refresh tokens.
- Helmet, CORS configurado y limitación de intentos en autenticación.
- Roles `Cliente`, `Operador`, `Administrador` y controles de pertenencia del recurso para evitar accesos indebidos.
- Cuenta SQL dedicada `shopcart_api` con `EXECUTE` específico, sin permisos administrativos.
- Auditoría de operaciones sensibles; `BitacoraAuditoria` impide modificaciones directas desde la cuenta de la API.
- Uso de variables de entorno; secretos excluidos del control de versiones.

## 7. Estrategia para imágenes de productos (decisión para Fase 2)

### Situación actual

La migración `003_CatalogTables.sql` ya creó `dbo.ImagenesProducto` con los campos:

| Campo | Propósito |
|---|---|
| `IDImagenProducto` | Identificador de imagen |
| `IDProducto` | Relación con el producto |
| `URLImagen` | Ruta o URL del archivo |
| `TextoAlternativo` | Accesibilidad y descripción |
| `OrdenVisualizacion` | Imagen principal y orden de galería |

**Todavía no está integrada la lectura de imágenes en el endpoint público del catálogo**: `SP_Catalogo_ListarProductos` devuelve productos, precios y existencias, pero no las URL. Tampoco se ha implementado un sistema de subida desde el panel administrativo. Ambas tareas se distinguen del esquema de datos que ya existe.

### Solución elegida para la demostración

1. Guardar imágenes de muestra, con licencia o autorización de uso, en `apps/web/public/images/products/`, preferentemente en **WebP**. Mantener una imagen de respaldo local.
2. Registrar en `ImagenesProducto` una ruta relativa como `/images/products/botella-termica.webp`, su texto alternativo y el orden de visualización.
3. En la Fase 2 ampliar mediante una **nueva migración** el procedimiento de consulta del catálogo para devolver una imagen principal por producto, sin romper la paginación ni la estructura de resultados existente.
4. React resolverá la ruta contra el origen del frontend y mostrará la imagen con `loading="lazy"`, tamaño definido para evitar saltos visuales, texto alternativo y recurso de respaldo si falla la carga.
5. Para un producto con varias imágenes, `OrdenVisualizacion` determinará su galería.

Estructura planificada:

```text
apps/
  web/
    public/
      images/
        products/
          botella-termica.webp
          mouse-inalambrico.webp
          placeholder.webp
```

Ejemplo **ilustrativo** de un registro futuro (la ruta solo será válida si se agrega el archivo):

```text
IDProducto:          3
URLImagen:           /images/products/botella-termica.webp
TextoAlternativo:    Botella térmica reutilizable de 500 ml
OrdenVisualizacion:  0
```

### ¿Por qué no guardar imágenes binarias en SQL Server?

- **Separación de responsabilidades:** SQL Server almacena datos de negocio y metadatos; un servidor estático o CDN sirve los archivos multimedia.
- **Rendimiento:** evita transferir archivos grandes mediante consultas de catálogo o la API transaccional.
- **Mantenibilidad:** permite sustituir imágenes sin alterar el esquema ni el modelo de productos.
- **Portabilidad:** `URLImagen` puede pasar de una ruta local a una URL HTTPS de almacenamiento de objetos/CDN cuando exista despliegue productivo.
- **Simplicidad para evaluación:** las imágenes estáticas versionadas junto con la aplicación React no requieren credenciales de un servicio externo ni una integración de subida durante la demostración.

### Reglas previstas de calidad y seguridad

- Formatos preferidos: WebP; JPEG/PNG solo cuando corresponda.
- Preparar imágenes comprimidas y dimensiones adecuadas; no almacenar base64 en SQL Server.
- Validar y normalizar las URL admitidas; si se habilita administración, restringir dominios HTTPS o rutas locales aprobadas.
- No mostrar imágenes sin permiso de uso ni datos personales incrustados en metadatos.
- Mostrar `alt` descriptivo y `placeholder` ante imágenes no disponibles.
- Una eventual carga dinámica necesitará validación real de tipo y tamaño de archivo, límites de carga, revisión de contenido, nombres seguros y almacenamiento externo; **no se considera implementada en Fase 1**.

**Evolución productiva:** utilizar almacenamiento de objetos y CDN (por ejemplo, S3, Cloudflare R2 o equivalente), conservando URL y metadatos en `ImagenesProducto`. La elección definitiva de proveedor queda fuera del alcance del demo.

## 8. Pruebas y evidencia

Los scripts de `database/tests/` cubren restricciones, inventario, concurrencia, carrito, reservas, checkout, pedidos, cupones, reportes, auditoría, seguridad y migraciones recientes.

Pruebas especialmente relevantes para el cierre de Fase 1:

| Script | Cobertura |
|---|---|
| `035_CustomerAddressesTests.sql` | Direcciones por cliente |
| `036_CustomerOrderHistoryTests.sql` | Historial de pedidos y pertenencia |
| `037_InventoryApiTests.sql` | Stock y movimientos de inventario |
| `038_DiscountedOrderReturnsTests.sql` | Reembolsos proporcionales con descuentos, idempotencia, inventario y `ROLLBACK` |
| `039_CategoryScopedCouponsTests.sql` | Descuento solo en categoría elegible, devolución de líneas elegibles y no elegibles, `ROLLBACK` |

Los tests `038` y `039` se ejecutaron durante el desarrollo con resultado positivo comunicado. **No se afirma que toda la batería haya sido ejecutada en una instalación limpia o en un entorno de CI.** Algunos tests requieren precondiciones específicas o sesiones paralelas.

Para verificar la compilación del backend:

```powershell
cd apps/api
npm run build
```

La ejecución de las pruebas SQL debe realizarse en una **base de desarrollo**, no sobre datos productivos.

## 9. Documentación gráfica

### Ciclo del pedido

![Ciclo de vida del pedido](docs/diagrams/ShopCart_Ciclo_pedido.png)

### Modelo entidad-relación general

![Modelo entidad-relación ShopCart](docs/diagrams/ShopCart_ER_General.png)

[Ver diagrama general](docs/diagrams/ShopCart_ER_General.png)

### Diagramas por módulo

- [Seguridad y usuarios](docs/diagrams/ShopCart_ER_Seguridad.png)
- [Catálogo e inventario](docs/diagrams/ShopCart_ER_CatalogoInventario.png)
- [Carrito y checkout](docs/diagrams/ShopCart_ER_CarritoCheckout.png)
- [Pedidos y promociones](docs/diagrams/ShopCart_ER_PedidosPromociones.png)

**Nota:** los diagramas existentes reflejan la estructura documentada al elaborarlos; las migraciones posteriores `046`–`050` incorporan operaciones y columnas que pueden requerir una nueva exportación del diagrama.

## 10. Limitaciones conocidas

- **Frontend:** todavía no existe una interfaz React integrada en el repositorio; corresponde a la Fase 2.
- **Imágenes:** la tabla está implementada, pero falta exponer URL en la consulta del catálogo, añadir recursos WebP al frontend e implementar su visualización. La subida de imágenes desde un panel administrativo no está disponible.
- **Carrito de invitado:** el esquema admite un token de invitado, pero la API actual del carrito requiere un cliente autenticado.
- **Direcciones:** API actual de creación y consulta; no están expuestos endpoints completos de edición y eliminación de direcciones.
- **Administración de usuarios:** el registro/autenticación están disponibles, pero la gestión administrativa de activación/desactivación requiere completar API y pruebas.
- **Pagos:** son simulados; no hay pasarela ni reembolsos bancarios reales.
- **Pruebas y despliegue:** falta certificar instalación limpia en una segunda instancia, ejecutar pruebas de regresión exhaustivas y establecer una suite automatizada de integración/CI.
- **Cupones por categoría:** se soporta una categoría específica por cupón (o alcance general), no una selección arbitraria de varias categorías por cupón.

## 11. Plan de Fase 2 — React + TypeScript

1. Crear la aplicación web y las rutas por rol (Cliente, Operador y Administrador).
2. Integrar autenticación y manejo seguro de sesiones con la API.
3. Construir catálogo responsive con búsqueda, filtros, imágenes, detalle de producto y estados de carga/error.
4. Integrar carrito, direcciones, reserva y confirmación de compra.
5. Mostrar historial del cliente, estados, cancelaciones y devoluciones.
6. Implementar paneles administrativos para productos, categorías, cupones, inventario, pedidos, reportes y auditoría, conforme a los endpoints disponibles.
7. Añadir pruebas de integración y casos negativos; verificar autorización y manejo de errores.
8. Revisar accesibilidad, diseño adaptable, documentación de ejecución y entrega final.

**Principio de implementación:** la interfaz no modificará directamente SQL Server; consumirá la API existente. Las nuevas necesidades del frontend se incorporarán mediante endpoints y migraciones versionadas, conservando compatibilidad con los contratos actuales.

---

**Propósito:** demostración y evaluación técnica para el Tech Challenge 360. Antes de un uso productivo se requiere completar las limitaciones documentadas, realizar pruebas adicionales y configurar adecuadamente la infraestructura.
