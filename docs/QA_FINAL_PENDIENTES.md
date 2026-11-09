
# ShopCart — Pendientes de revisión final

## SweetAlert2

- [ ] Centralizar las confirmaciones del panel de pedidos del Operador usando `src/lib/alerts.ts`.
- [ ] Revisar la confirmación final de compra en `CheckoutPage.tsx`.
- [ ] Incorporar confirmación al cancelar pedidos en `OrderDetailPage.tsx`.
- [ ] Incorporar confirmación al solicitar devoluciones en `ReturnOrderPanel.tsx`.
- [ ] Revisar las acciones de eliminación del carrito.
- [ ] Unificar los mensajes de éxito y error cuando corresponda.
- [ ] Verificar que cancelar una alerta nunca ejecute una operación.
- [ ] Verificar que las alertas no rompan los reintentos idempotentes del checkout y las devoluciones.

## Validación final

- [ ] Compilación y lint de frontend y backend.
- [ ] Pruebas de permisos para Cliente, Operador y Administrador.
- [ ] Pruebas de concurrencia y reintegro de inventario.
- [ ] Pruebas de checkout y devoluciones.
- [ ] README actualizado con el frontend implementado.
- [ ] Instalación reproducible en entorno limpio.


## Pendientes del catálogo de productos

- [ ] Listar productos activos e inactivos en administración.
- [ ] Permitir reactivar productos desactivados.
- [ ] Implementar creación y administración de variantes adicionales.
- [ ] Administrar atributos de variantes (talla, color, etc.).
- [ ] Permitir reemplazar la imagen principal del producto.
- [ ] Eliminar imágenes anteriores únicamente después de confirmar el reemplazo.
- [ ] Verificar limpieza de archivos de imágenes sin referencias.
- [ ] Documentar almacenamiento y respaldo de imágenes.
- [ ] Probar instalación limpia con imágenes de demostración.

## Requisitos críticos pendientes

- [ ] Integrar cupones en el frontend y checkout.
- [x] Completar administración de usuarios.
- [x] Integrar dashboard con gráficas y reportes.
- [ ] Integrar consulta administrativa de bitácora.
- [ ] Ejecutar pruebas de seguridad, concurrencia e idempotencia.
- [ ] Actualizar README con instrucciones de instalación y ejecución.
- [ ] Preparar la demostración y defensa técnica.
```


## Mejoras pendientes del dashboard administrativo

- [x] Integrar reportes de ventas netas por período.
- [x] Integrar ventas por categoría.
- [x] Integrar top 10 de productos.
- [x] Mostrar indicadores comerciales.
- [x] Implementar filtros de fechas y agrupación.
- [x] Proteger acceso exclusivo de Administrador.
- [x] Validar indicadores contra SQL Server.
- [x] Completar 15 pruebas funcionales.

### Mejoras de presentación

- [ ] Mostrar el nombre real de cada categoría
      en lugar de "Categoría #ID".

- [ ] Representar con valor cero los períodos
      sin ventas en la gráfica temporal.

- [ ] Verificar que ambas mejoras conserven
      los totales actuales de SQL Server.

Si alguna tarea ya está completada y probada, puedes marcarla. Lo importante es mantener este documento actualizado.
