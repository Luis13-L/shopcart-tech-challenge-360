USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- ==========================================
-- MIGRACION 058: REACTIVAR PRODUCTOS
-- Restaura unicamente variantes previamente
-- activas segun la auditoria (migracion 040).
-- ==========================================

BEGIN TRY
    BEGIN TRANSACTION;

    IF NOT EXISTS (
        SELECT 1 FROM dbo.SchemaMigrations WHERE Numero = 57
    )
        THROW 80200, 'Primero ejecute la migracion 057.', 1;

    IF NOT EXISTS (
        SELECT 1 FROM dbo.SchemaMigrations WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 58
    )
    BEGIN
        IF OBJECT_ID(N'dbo.SP_Catalogo_ReactivarProducto', N'P') IS NOT NULL
            THROW 80201, 'Procedimiento existente sin migracion.', 1;

        EXEC sys.sp_executesql N'
CREATE PROCEDURE dbo.SP_Catalogo_ReactivarProducto
    @IDUsuarioActor INT,
    @IDProducto INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @IDProducto IS NULL OR @IDProducto <= 0
        THROW 80211, ''ID de producto invalido.'', 1;

    DECLARE @IDCategoria INT;
    DECLARE @CategoriaActiva BIT;
    DECLARE @ActivoAnterior BIT;
    DECLARE @Antes NVARCHAR(MAX);
    DECLARE @Despues NVARCHAR(MAX);
    DECLARE @Snapshot NVARCHAR(MAX);
    DECLARE @VariantesReactivadas INT = 0;
    DECLARE @Reutilizado BIT = 0;
    DECLARE @IDTexto VARCHAR(40) = CONVERT(VARCHAR(40), @IDProducto);

    DECLARE @EstadoOriginal TABLE (
        IDVariante INT NOT NULL PRIMARY KEY,
        Activa BIT NOT NULL
    );

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Verificar permisos vigentes en la base de datos.
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Usuarios AS u
            INNER JOIN dbo.Roles AS r ON r.IDRol = u.IDRol
            WHERE u.IDUsuario = @IDUsuarioActor
              AND u.Activo = 1
              AND r.Nombre = ''Administrador''
        )
            THROW 80210, ''Administrador no autorizado.'', 1;

        SELECT @IDCategoria = p.IDCategoria
        FROM dbo.Productos AS p
        WHERE p.IDProducto = @IDProducto;

        IF @IDCategoria IS NULL
            THROW 80212, ''Producto no encontrado.'', 1;

        -- Bloquear primero la categoria; impide que sea desactivada
        -- mientras se reactiva uno de sus productos.
        SELECT @CategoriaActiva = c.Activa
        FROM dbo.Categorias AS c WITH (UPDLOCK, HOLDLOCK)
        WHERE c.IDCategoria = @IDCategoria;

        IF @CategoriaActiva IS NULL OR @CategoriaActiva = 0
            THROW 80213, ''La categoria del producto esta inactiva.'', 1;

        SELECT @ActivoAnterior = p.Activo
        FROM dbo.Productos AS p WITH (UPDLOCK, HOLDLOCK)
        WHERE p.IDProducto = @IDProducto
          AND p.IDCategoria = @IDCategoria;

        IF @ActivoAnterior IS NULL
            THROW 80216, ''El producto cambio durante la operacion.'', 1;

        IF @ActivoAnterior = 1
        BEGIN
            -- Reintento: no modificar variantes ni duplicar auditoria.
            SET @Reutilizado = 1;
        END
        ELSE
        BEGIN
            -- Recuperar la ultima fotografia anterior a la desactivacion.
            -- El SP de desactivacion de la migracion 040 guarda los
            -- estados originales de cada variante en auditoria.
            SELECT TOP (1) @Snapshot = b.ValoresAnteriores
            FROM dbo.BitacoraAuditoria AS b
            WHERE b.Modulo = ''CATALOGO''
              AND b.Entidad = ''Productos''
              AND b.IDEntidad = @IDTexto
              AND b.Accion = ''DESACTIVAR''
              AND JSON_VALUE(b.ValoresAnteriores, ''$.Activo'') = ''true''
            ORDER BY b.IDBitacora DESC;

            IF @Snapshot IS NULL
               OR JSON_QUERY(@Snapshot, ''$.variantes'') IS NULL
                THROW 80214,
                    ''Sin estado historico confiable de variantes; revision manual requerida.'', 1;

            IF EXISTS (
                SELECT 1
                FROM OPENJSON(@Snapshot, ''$.variantes'')
                WITH (
                    IDVariante INT ''$.IDVariante'',
                    Activa NVARCHAR(5) ''$.Activa''
                ) AS s
                WHERE s.IDVariante IS NULL
                   OR s.Activa IS NULL
                   OR s.Activa NOT IN (''true'', ''false'')
            )
                THROW 80216, ''Fotografia de variantes invalida.'', 1;

            INSERT INTO @EstadoOriginal (IDVariante, Activa)
            SELECT
                s.IDVariante,
                CONVERT(BIT, CASE WHEN s.Activa = ''true'' THEN 1 ELSE 0 END)
            FROM OPENJSON(@Snapshot, ''$.variantes'')
            WITH (
                IDVariante INT ''$.IDVariante'',
                Activa NVARCHAR(5) ''$.Activa''
            ) AS s;

            -- No reactivar si faltan variantes historicas, si hay
            -- variantes nuevas no registradas, o si ninguna estaba activa.
            IF EXISTS (
                SELECT 1
                FROM @EstadoOriginal AS o
                LEFT JOIN dbo.Variantes AS v
                    ON v.IDVariante = o.IDVariante
                   AND v.IDProducto = @IDProducto
                WHERE v.IDVariante IS NULL
            ) OR (
                SELECT COUNT(*)
                FROM @EstadoOriginal
            ) <> (
                SELECT COUNT(*)
                FROM dbo.Variantes
                WHERE IDProducto = @IDProducto
            )
                THROW 80216, ''Las variantes cambiaron; revision manual requerida.'', 1;

            IF NOT EXISTS (
                SELECT 1 FROM @EstadoOriginal WHERE Activa = 1
            )
                THROW 80215, ''No existen variantes originalmente activas.'', 1;

            -- La desactivacion oficial pone todas las variantes en 0.
            -- Si alguien cambio una de ellas posteriormente, no
            -- recuperamos el producto de forma automatica.
            IF EXISTS (
                SELECT 1
                FROM dbo.Variantes WITH (UPDLOCK, HOLDLOCK)
                WHERE IDProducto = @IDProducto AND Activa = 1
            )
                THROW 80216, ''Variantes alteradas tras la desactivacion.'', 1;

            SELECT @Antes = (
                SELECT p.IDProducto, p.Nombre, p.Activo,
                    JSON_QUERY((
                        SELECT v.IDVariante, v.Activa
                        FROM dbo.Variantes AS v
                        WHERE v.IDProducto = p.IDProducto
                        ORDER BY v.IDVariante
                        FOR JSON PATH
                    )) AS variantes
                FROM dbo.Productos AS p
                WHERE p.IDProducto = @IDProducto
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            UPDATE dbo.Productos
            SET Activo = 1
            WHERE IDProducto = @IDProducto AND Activo = 0;

            UPDATE v
            SET v.Activa = 1
            FROM dbo.Variantes AS v
            INNER JOIN @EstadoOriginal AS o
                ON o.IDVariante = v.IDVariante
            WHERE v.IDProducto = @IDProducto
              AND o.Activa = 1
              AND v.Activa = 0;

            SET @VariantesReactivadas = @@ROWCOUNT;

            SELECT @Despues = (
                SELECT p.IDProducto, p.Nombre, p.Activo,
                    JSON_QUERY((
                        SELECT v.IDVariante, v.Activa
                        FROM dbo.Variantes AS v
                        WHERE v.IDProducto = p.IDProducto
                        ORDER BY v.IDVariante
                        FOR JSON PATH
                    )) AS variantes
                FROM dbo.Productos AS p
                WHERE p.IDProducto = @IDProducto
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            EXEC dbo.SP_Auditoria_RegistrarCambio
                @IDUsuario = @IDUsuarioActor,
                @Modulo = ''CATALOGO'',
                @Entidad = ''Productos'',
                @IDEntidad = @IDTexto,
                @Accion = ''ACTIVAR'',
                @ValoresAnteriores = @Antes,
                @ValoresNuevos = @Despues;
        END;

        COMMIT TRANSACTION;

        SELECT
            p.IDProducto,
            p.Nombre,
            p.Activo,
            @VariantesReactivadas AS VariantesReactivadas,
            @Reutilizado AS Reutilizado
        FROM dbo.Productos AS p
        WHERE p.IDProducto = @IDProducto;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

        IF DATABASE_PRINCIPAL_ID(N'shopcart_api') IS NULL
            THROW 80202, 'No existe shopcart_api.', 1;

        GRANT EXECUTE
        ON OBJECT::dbo.SP_Catalogo_ReactivarProducto
        TO [shopcart_api];

        INSERT INTO dbo.SchemaMigrations (Numero, Nombre)
        VALUES (58, N'058_AdminProductReactivation');

        PRINT 'OK: Migracion 058 aplicada correctamente.';
    END
    ELSE
    BEGIN
        IF OBJECT_ID(N'dbo.SP_Catalogo_ReactivarProducto', N'P') IS NULL
            THROW 80203, 'Migracion registrada sin procedimiento.', 1;

        PRINT 'OK: Migracion 058 ya aplicada.';
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
