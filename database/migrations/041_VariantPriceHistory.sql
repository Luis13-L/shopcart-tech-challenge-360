USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    -- =========================================
    -- 1. VALIDAR DEPENDENCIA
    -- =========================================

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
        WHERE Numero = 40
    )
        THROW 75010,
            'Primero ejecute la migracion 040.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
            WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 41
    )
    BEGIN

        IF OBJECT_ID(
            N'dbo.HistorialPreciosVariante', N'U'
        ) IS NOT NULL
           OR OBJECT_ID(
            N'dbo.SP_Catalogo_ActualizarPrecioVariante',
            N'P'
        ) IS NOT NULL
            THROW 75011,
                'Existen objetos de precios sin migracion registrada.',
                1;

        -- =====================================
        -- 2. HISTORIAL DE PRECIOS
        -- =====================================

        CREATE TABLE dbo.HistorialPreciosVariante (
            IDHistorialPrecio BIGINT IDENTITY(1,1)
                NOT NULL,

            IDVariante INT NOT NULL,
            IDUsuario INT NOT NULL,

            PrecioAnterior DECIMAL(19,2) NOT NULL,
            PrecioNuevo DECIMAL(19,2) NOT NULL,

            Motivo NVARCHAR(300) NOT NULL,

            FechaCambio DATETIME2(3) NOT NULL
                CONSTRAINT DF_HistorialPrecios_Fecha
                DEFAULT (SYSUTCDATETIME()),

            CONSTRAINT PK_HistorialPreciosVariante
                PRIMARY KEY (IDHistorialPrecio),

            CONSTRAINT FK_HistorialPrecios_Variante
                FOREIGN KEY (IDVariante)
                REFERENCES dbo.Variantes(IDVariante),

            CONSTRAINT FK_HistorialPrecios_Usuario
                FOREIGN KEY (IDUsuario)
                REFERENCES dbo.Usuarios(IDUsuario),

            CONSTRAINT CK_HistorialPrecios_Precios
                CHECK (
                    PrecioAnterior > 0
                    AND PrecioNuevo > 0
                    AND PrecioAnterior <> PrecioNuevo
                ),

            CONSTRAINT CK_HistorialPrecios_Motivo
                CHECK (
                    LEN(LTRIM(RTRIM(Motivo))) > 0
                )
        );

        CREATE INDEX IX_HistorialPrecios_VarianteFecha
        ON dbo.HistorialPreciosVariante (
            IDVariante,
            FechaCambio DESC,
            IDHistorialPrecio DESC
        );

        -- =====================================
        -- 3. PROCEDIMIENTO DE ACTUALIZACION
        -- Se crea en batch dinamico dentro de
        -- la misma transaccion de migracion.
        -- =====================================

        EXEC sys.sp_executesql N'
CREATE PROCEDURE dbo.SP_Catalogo_ActualizarPrecioVariante
    @IDUsuarioActor INT,
    @IDVariante INT,
    @PrecioNuevo DECIMAL(19,2),
    @Motivo NVARCHAR(300)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @IDVariante IS NULL OR @IDVariante <= 0
        THROW 75000,
            ''ID de variante invalido.'', 1;

    IF @PrecioNuevo IS NULL OR @PrecioNuevo <= 0
        THROW 75001,
            ''El precio debe ser mayor que cero.'', 1;

    SET @Motivo = LTRIM(RTRIM(@Motivo));

    IF NULLIF(@Motivo, N'''') IS NULL
        THROW 75005,
            ''Debe indicar un motivo.'', 1;

    DECLARE @IDProducto INT;
    DECLARE @SKU NVARCHAR(64);
    DECLARE @PrecioAnterior DECIMAL(19,2);
    DECLARE @Actualizado BIT = 0;
    DECLARE @FechaCambio DATETIME2(3) = NULL;

    DECLARE @Antes NVARCHAR(MAX);
    DECLARE @Despues NVARCHAR(MAX);

    DECLARE @IDVarianteTexto VARCHAR(40) =
        CONVERT(VARCHAR(40), @IDVariante);

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Solo Administrador activo.
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Usuarios u
            INNER JOIN dbo.Roles r
                ON r.IDRol = u.IDRol
            WHERE u.IDUsuario = @IDUsuarioActor
              AND u.Activo = 1
              AND r.Nombre = ''Administrador''
        )
            THROW 75002,
                ''Usuario sin permisos administrativos.'',
                1;

        -- Bloqueo para serializar cambios de
        -- precio sobre la misma variante.
        SELECT
            @IDProducto = v.IDProducto,
            @SKU = v.SKU,
            @PrecioAnterior = v.PrecioActual
        FROM dbo.Variantes v WITH (
            UPDLOCK, HOLDLOCK
        )
        INNER JOIN dbo.Productos p
            ON p.IDProducto = v.IDProducto
        WHERE v.IDVariante = @IDVariante
          AND v.Activa = 1
          AND p.Activo = 1;

        IF @PrecioAnterior IS NULL
            THROW 75003,
                ''Variante inexistente o inactiva.'',
                1;

        -- No duplicar cambios sin diferencia.
        IF @PrecioNuevo <> @PrecioAnterior
        BEGIN
            SET @FechaCambio = SYSUTCDATETIME();

            SELECT @Antes = (
                SELECT
                    @IDVariante AS idVariante,
                    @IDProducto AS idProducto,
                    @SKU AS sku,
                    @PrecioAnterior AS precioActual
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            UPDATE dbo.Variantes
            SET PrecioActual = @PrecioNuevo
            WHERE IDVariante = @IDVariante
              AND Activa = 1;

            IF @@ROWCOUNT <> 1
                THROW 75004,
                    ''No se pudo actualizar el precio.'',
                    1;

            INSERT INTO dbo.HistorialPreciosVariante (
                IDVariante,
                IDUsuario,
                PrecioAnterior,
                PrecioNuevo,
                Motivo,
                FechaCambio
            )
            VALUES (
                @IDVariante,
                @IDUsuarioActor,
                @PrecioAnterior,
                @PrecioNuevo,
                @Motivo,
                @FechaCambio
            );

            SELECT @Despues = (
                SELECT
                    @IDVariante AS idVariante,
                    @IDProducto AS idProducto,
                    @SKU AS sku,
                    @PrecioNuevo AS precioActual,
                    @Motivo AS motivo
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            EXEC dbo.SP_Auditoria_RegistrarCambio
                @IDUsuario = @IDUsuarioActor,
                @Modulo = ''CATALOGO'',
                @Entidad = ''Variantes'',
                @IDEntidad = @IDVarianteTexto,
                @Accion = ''ACTUALIZAR'',
                @ValoresAnteriores = @Antes,
                @ValoresNuevos = @Despues;

            SET @Actualizado = 1;
        END;

        COMMIT TRANSACTION;

        -- Respuesta estable para el backend.
        SELECT
            @IDVariante AS IDVariante,
            @IDProducto AS IDProducto,
            @SKU AS SKU,
            @PrecioAnterior AS PrecioAnterior,
            @PrecioNuevo AS PrecioActual,
            @Actualizado AS Actualizado,
            @FechaCambio AS FechaCambio;

    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
';

        -- La API solo puede invocar el SP.
        GRANT EXECUTE
        ON OBJECT::dbo.SP_Catalogo_ActualizarPrecioVariante
        TO [shopcart_api];

        -- =====================================
        -- 4. REGISTRAR MIGRACION
        -- =====================================

        INSERT INTO dbo.SchemaMigrations (
            Numero,
            Nombre
        )
        VALUES (
            41,
            N'041_VariantPriceHistory'
        );

        PRINT 'Migracion 041 aplicada correctamente.';
    END
    ELSE
    BEGIN
        IF OBJECT_ID(
            N'dbo.HistorialPreciosVariante', N'U'
        ) IS NULL
           OR OBJECT_ID(
            N'dbo.SP_Catalogo_ActualizarPrecioVariante',
            N'P'
        ) IS NULL
            THROW 75012,
                'Migracion registrada con objetos faltantes.',
                1;

        PRINT 'Migracion 041 ya aplicada.';
    END;

    COMMIT TRANSACTION;

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
