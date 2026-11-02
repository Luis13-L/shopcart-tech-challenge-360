USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

-- ==========================================
-- TEST 031 - CRUD DE CATEGORIAS
-- ==========================================

DECLARE @IDAdmin INT;
DECLARE @IDCategoria INT;

DECLARE @NombreOriginal NVARCHAR(120) =
    CONCAT(
        N'TEST_CAT_',
        REPLACE(
            CONVERT(NVARCHAR(36), NEWID()),
            N'-', N''
        )
    );

DECLARE @NombreNuevo NVARCHAR(120) =
    CONCAT(@NombreOriginal, N'_EDITADA');

-- ==========================================
-- 1. PRECONDICIONES
-- ==========================================

IF NOT EXISTS (
    SELECT 1
    FROM dbo.SchemaMigrations
    WHERE Numero = 42
)
    THROW 76101,
        'Primero ejecute la migracion 042.', 1;

SELECT TOP (1)
    @IDAdmin = u.IDUsuario
FROM dbo.Usuarios u
INNER JOIN dbo.Roles r
    ON r.IDRol = u.IDRol
WHERE u.Activo = 1
  AND r.Nombre = 'Administrador'
ORDER BY u.IDUsuario;

IF @IDAdmin IS NULL
    THROW 76102,
        'No existe Administrador activo.', 1;

CREATE TABLE #ListadoCategorias (
    IDCategoria INT,
    Nombre NVARCHAR(120),
    Descripcion NVARCHAR(500),
    Activa BIT,
    FechaCreacion DATETIME2(3)
);

BEGIN TRY
    BEGIN TRANSACTION;

    -- ======================================
    -- 2. CREAR CATEGORIA
    -- ======================================

    EXEC dbo.SP_Catalogo_CrearCategoria
        @IDUsuarioActor = @IDAdmin,
        @Nombre = @NombreOriginal,
        @Descripcion = N'Categoria temporal de pruebas';

    SELECT @IDCategoria = IDCategoria
    FROM dbo.Categorias
    WHERE Nombre = @NombreOriginal;

    IF @IDCategoria IS NULL
        THROW 76103,
            'No se creo la categoria.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.BitacoraAuditoria
        WHERE Modulo = 'CATALOGO'
          AND Entidad = 'Categorias'
          AND IDEntidad =
              CONVERT(VARCHAR(40), @IDCategoria)
          AND Accion = 'CREAR'
          AND IDUsuario = @IDAdmin
    )
        THROW 76104,
            'Falta auditoria CREAR.', 1;

    PRINT 'OK: categoria creada y auditada.';

    -- ======================================
    -- 3. LISTAR CATEGORIAS ACTIVAS
    -- ======================================

    INSERT INTO #ListadoCategorias
    EXEC dbo.SP_Catalogo_ListarCategorias
        @IDUsuarioActor = NULL,
        @IncluirInactivas = 0;

    IF NOT EXISTS (
        SELECT 1
        FROM #ListadoCategorias
        WHERE IDCategoria = @IDCategoria
          AND Activa = 1
    )
        THROW 76105,
            'La categoria activa no aparece.', 1;

    DELETE FROM #ListadoCategorias;

    PRINT 'OK: consulta publica de categorias.';

    -- ======================================
    -- 4. ACTUALIZAR CATEGORIA
    -- ======================================

    EXEC dbo.SP_Catalogo_ActualizarCategoria
        @IDUsuarioActor = @IDAdmin,
        @IDCategoria = @IDCategoria,
        @Nombre = @NombreNuevo,
        @Descripcion = N'Descripcion actualizada',
        @CambiarDescripcion = 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Categorias
        WHERE IDCategoria = @IDCategoria
          AND Nombre = @NombreNuevo
          AND Descripcion = N'Descripcion actualizada'
    )
        THROW 76106,
            'La actualizacion fallo.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.BitacoraAuditoria
        WHERE Modulo = 'CATALOGO'
          AND Entidad = 'Categorias'
          AND IDEntidad =
              CONVERT(VARCHAR(40), @IDCategoria)
          AND Accion = 'ACTUALIZAR'
          AND JSON_VALUE(
              ValoresAnteriores, '$.Nombre'
          ) = @NombreOriginal
          AND JSON_VALUE(
              ValoresNuevos, '$.Nombre'
          ) = @NombreNuevo
    )
        THROW 76107,
            'Falta auditoria ACTUALIZAR.', 1;

    PRINT 'OK: categoria actualizada y auditada.';

    -- ======================================
    -- 5. DESACTIVAR CATEGORIA
    -- ======================================

    EXEC dbo.SP_Catalogo_CambiarEstadoCategoria
        @IDUsuarioActor = @IDAdmin,
        @IDCategoria = @IDCategoria,
        @Activa = 0;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Categorias
        WHERE IDCategoria = @IDCategoria
          AND Activa = 0
    )
        THROW 76108,
            'No se desactivo la categoria.', 1;

    -- Repetir desactivacion:
    -- no debe duplicar auditoria.
    EXEC dbo.SP_Catalogo_CambiarEstadoCategoria
        @IDUsuarioActor = @IDAdmin,
        @IDCategoria = @IDCategoria,
        @Activa = 0;

    IF (
        SELECT COUNT(*)
        FROM dbo.BitacoraAuditoria
        WHERE Modulo = 'CATALOGO'
          AND Entidad = 'Categorias'
          AND IDEntidad =
              CONVERT(VARCHAR(40), @IDCategoria)
          AND Accion = 'DESACTIVAR'
    ) <> 1
        THROW 76109,
            'Se duplico auditoria DESACTIVAR.', 1;

    PRINT 'OK: desactivacion sin duplicados.';

    -- ======================================
    -- 6. VERIFICAR LISTADO PUBLICO
    -- ======================================

    INSERT INTO #ListadoCategorias
    EXEC dbo.SP_Catalogo_ListarCategorias
        @IDUsuarioActor = NULL,
        @IncluirInactivas = 0;

    IF EXISTS (
        SELECT 1
        FROM #ListadoCategorias
        WHERE IDCategoria = @IDCategoria
    )
        THROW 76110,
            'Categoria inactiva visible al publico.',
            1;

    DELETE FROM #ListadoCategorias;

    -- Administrador si puede verla.
    INSERT INTO #ListadoCategorias
    EXEC dbo.SP_Catalogo_ListarCategorias
        @IDUsuarioActor = @IDAdmin,
        @IncluirInactivas = 1;

    IF NOT EXISTS (
        SELECT 1
        FROM #ListadoCategorias
        WHERE IDCategoria = @IDCategoria
          AND Activa = 0
    )
        THROW 76111,
            'Administrador no puede ver inactivas.',
            1;

    DELETE FROM #ListadoCategorias;

    PRINT 'OK: filtros de categorias correctos.';

    -- ======================================
    -- 7. REACTIVAR CATEGORIA
    -- ======================================

    EXEC dbo.SP_Catalogo_CambiarEstadoCategoria
        @IDUsuarioActor = @IDAdmin,
        @IDCategoria = @IDCategoria,
        @Activa = 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Categorias
        WHERE IDCategoria = @IDCategoria
          AND Activa = 1
    )
        THROW 76112,
            'No se reactivo la categoria.', 1;

    -- ======================================
    -- 8. COMPROBAR LOS CUATRO EVENTOS
    -- ======================================

    IF (
        SELECT COUNT(*)
        FROM dbo.BitacoraAuditoria
        WHERE Modulo = 'CATALOGO'
          AND Entidad = 'Categorias'
          AND IDEntidad =
              CONVERT(VARCHAR(40), @IDCategoria)
    ) <> 4
        THROW 76113,
            'Cantidad de auditorias incorrecta.', 1;

    SELECT
        IDBitacora,
        IDUsuario,
        Modulo,
        Entidad,
        IDEntidad,
        Accion,
        ValoresAnteriores,
        ValoresNuevos
    FROM dbo.BitacoraAuditoria
    WHERE Modulo = 'CATALOGO'
      AND Entidad = 'Categorias'
      AND IDEntidad =
          CONVERT(VARCHAR(40), @IDCategoria)
    ORDER BY IDBitacora;

    PRINT 'OK: cuatro eventos de auditoria.';

    -- ======================================
    -- 9. REVERTIR PRUEBAS
    -- ======================================

    ROLLBACK TRANSACTION;

    IF EXISTS (
        SELECT 1
        FROM dbo.Categorias
        WHERE IDCategoria = @IDCategoria
    )
        THROW 76114,
            'Categoria temporal no revertida.', 1;

    IF EXISTS (
        SELECT 1
        FROM dbo.BitacoraAuditoria
        WHERE Modulo = 'CATALOGO'
          AND Entidad = 'Categorias'
          AND IDEntidad =
              CONVERT(VARCHAR(40), @IDCategoria)
    )
        THROW 76115,
            'Auditoria temporal no revertida.', 1;

    SELECT
        'OK: CRUD de categorias validado'
            AS Resultado,
        'OK: ROLLBACK completado'
            AS Integridad;

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;

DROP TABLE #ListadoCategorias;
GO
