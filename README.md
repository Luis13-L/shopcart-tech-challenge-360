# ShopCart — Tech Challenge 360

Plataforma de comercio electrónico desarrollada para
el Tech Challenge 360.

## Tecnologías

- Backend: Node.js 24, Express y TypeScript
- Base de datos: Microsoft SQL Server 2019+
- Validaciones: Zod
- Autenticación: JWT, bcrypt y refresh tokens
- Seguridad: Helmet, CORS y control de acceso por roles

## Arquitectura

La API sigue una arquitectura por capas:

Router → Controller → Service → Repository → SQL Server

El acceso a datos se realiza mediante procedimientos
almacenados. No se utiliza ORM.

## Requisitos

- Node.js 24
- SQL Server 2019 o superior
- SQL Server Management Studio
- Git
- npm

## Instalación de base de datos

1. Ejecutar database/migrations/001_CreateDatabase.sql.
2. Crear un login y usuario SQL llamado shopcart_api
   con las credenciales locales del entorno.
3. Ejecutar las migraciones 002 a 045 en orden.
4. Ejecutar database/seeds/001_InitialData.sql.
5. Configurar los usuarios administrativos de desarrollo
   antes de probar endpoints protegidos.

No incluir credenciales reales en el repositorio.

## Configuración del backend

Desde la carpeta apps/api:

1. Ejecutar npm ci.
2. Copiar .env.example a .env.
3. Configurar SQL Server y JWT_SECRET.
4. Ejecutar npm run build.
5. Ejecutar npm run dev.

La API se inicia por defecto en:

http://localhost:3000

## Verificación

GET /api/health
GET /api/health/db
GET /api/catalog/products
GET /api/catalog/categories

## Módulos del backend

- Autenticación y autorización
- Catálogo y categorías
- Historial de precios
- Inventario y kardex
- Carrito de compras
- Reservas de inventario
- Checkout y pagos simulados
- Cupones
- Pedidos, cancelaciones y devoluciones
- Reportes de ventas
- Bitácora de auditoría

## Pruebas

Los scripts SQL se encuentran en database/tests.

Incluyen validaciones de restricciones, transacciones,
reservas, inventario, pedidos, devoluciones, cupones,
auditoría y autenticación.

Las pruebas SQL se ejecutan desde SSMS.
La automatización de pruebas de la API está pendiente.

## Seguridad

- Los secretos se configuran mediante .env.
- Las contraseñas se almacenan con bcrypt.
- Los refresh tokens se almacenan como hashes.
- Se utilizan roles Cliente, Operador y Administrador.
- Los importes históricos de pedidos se conservan.
- Las operaciones sensibles generan auditoría.


## Decisiones técnicas y justificación

### Arquitectura por capas

Elegimos Router, Controller, Service y Repository para
separar responsabilidades. Esto facilita las pruebas,
el mantenimiento y la identificación de errores.

### Acceso mediante Stored Procedures

Utilizamos procedimientos almacenados y parámetros
tipados para cumplir el enunciado, centralizar las
reglas de integridad y reducir riesgos de SQL injection.

### Inventario y concurrencia

Utilizamos transacciones y bloqueos UPDLOCK/HOLDLOCK
en operaciones críticas para evitar sobreventas.
Las existencias disponibles consideran las reservas
activas y no vencidas.

### Reservas de 15 minutos

Elegimos reservar temporalmente las unidades durante
el checkout, sin descontar definitivamente el inventario
hasta confirmar el pedido. Las reservas vencidas dejan
de contar como disponibilidad comprometida.

### Idempotencia

El checkout utiliza una clave única por solicitud y
un hash de los datos relevantes. Un reintento idéntico
devuelve el resultado anterior; una clave reutilizada
con otros datos se rechaza.

### Autenticación

Utilizamos bcrypt para contraseñas, JWT de 15 minutos
y refresh tokens con rotación y revocación.
Los refresh tokens se almacenan como hashes SHA-256.

### Precios históricos

Cada detalle de pedido conserva el precio de venta.
Así, una actualización posterior del catálogo no altera
los importes de compras confirmadas.

### Pagos simulados

Elegimos simular la aprobación del pago para probar
atomicidad, idempotencia y cambios de estado sin
depender de una pasarela externa.

Para integrar pagos reales necesitaríamos gestionar
confirmaciones externas, webhooks autenticados y
conciliación con el proveedor.

## Ciclo de vida del pedido

![Diagrama Ciclo de vida del pedido](docs/diagrams/ShopCart_Ciclo_pedido.png)


## Modelo entidad-relación

ShopCart utiliza una base de datos relacional en SQL Server,
organizada en módulos funcionales.

Los diagramas fueron generados a partir del esquema real
de la base de datos.

### Diagrama general

![Modelo ER general](docs/diagrams/ShopCart_ER_General.png)

### Diagramas por módulos

- [Seguridad y usuarios](docs/diagrams/ShopCart_ER_Seguridad.png)
- [Catálogo e inventario](docs/diagrams/ShopCart_ER_CatalogoInventario.png)
- [Carrito y checkout](docs/diagrams/ShopCart_ER_CarritoCheckout.png)
- [Pedidos y promociones](docs/diagrams/ShopCart_ER_PedidosPromociones.png)




## Estado del proyecto

Fase 1: base de datos y backend en desarrollo avanzado.
Fase 2: frontend React e integración pendiente.
