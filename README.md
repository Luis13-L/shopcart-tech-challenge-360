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

## Estado del proyecto

Fase 1: base de datos y backend en desarrollo avanzado.
Fase 2: frontend React e integración pendiente.
