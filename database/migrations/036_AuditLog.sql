USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
        WHERE Numero = 35
    )
        THROW 73001,
            'Primero ejecute la migracion 035.',
            1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations
            WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 36
    )
    BEGIN

        IF OBJECT_ID(N'dbo.BitacoraAuditoria', N'U') IS NOT NULL
           OR OBJECT_ID(N'dbo.SP_Auditoria_RegistrarCambio', N'P') IS NOT NULL
           OR OBJECT_ID(N'dbo.SP_Auditoria_Listar', N'P') IS NOT NULL
            THROW 73002,
                'Existen objetos de auditoria sin migracion registrada.',
                1;

        -- ======================================
        -- 1. TABLA DE AUDITORIA
        -- ======================================

        CREATE TABLE dbo.BitacoraAuditoria (
            IDBitacora BIGINT IDENTITY(1,1) NOT NULL,
            IDUsuario INT NOT NULL,

            Modulo VARCHAR(30) NOT NULL,
            Entidad VARCHAR(80) NOT NULL,
            IDEntidad VARCHAR(40) NOT NULL,
            Accion VARCHAR(30) NOT NULL,

            ValoresAnteriores NVARCHAR(MAX) NULL,
            ValoresNuevos NVARCHAR(MAX) NULL,

            FechaRegistro DATETIME2(3) NOT NULL
                CONSTRAINT DF_Bitacora_Fecha
                DEFAULT (SYSUTCDATETIME()),

            CONSTRAINT PK_BitacoraAuditoria
                PRIMARY KEY (IDBitacora),

            CONSTRAINT FK_Bitacora_Usuario
                FOREIGN KEY (IDUsuario)
                REFERENCES dbo.Usuarios(IDUsuario),

            CONSTRAINT CK_Bitacora_Modulo
                CHECK (
                    Modulo IN (
                        'CATALOGO',
                        'INVENTARIO',
                        'CUPONES',
                        'PEDIDOS',
                        'USUARIOS'
                    )
                ),

            CONSTRAINT CK_Bitacora_Accion
                CHECK (
                    Accion IN (
                        'CREAR',
                        'ACTUALIZAR',
                        'DESACTIVAR',
                        'ACTIVAR',
                        'AJUSTAR',
                        'CAMBIAR_ESTADO',
                        'CANCELAR',
                        'DEVOLVER'
                    )
                ),

            CONSTRAINT CK_Bitacora_ValoresAnteriores
                CHECK (
                    ValoresAnteriores IS NULL
                    OR ISJSON(ValoresAnteriores) = 1
                ),

            CONSTRAINT CK_Bitacora_ValoresNuevos
                CHECK (
                    ValoresNuevos IS NULL
                    OR ISJSON(ValoresNuevos) = 1
                )
        );

        CREATE INDEX IX_Bitacora_Modulo_Fecha
        ON dbo.BitacoraAuditoria (
            Modulo,
            FechaRegistro DESC,
            IDBitacora DESC
        );

        CREATE INDEX IX_Bitacora_Usuario_Fecha
        ON dbo.BitacoraAuditoria (
            IDUsuario,
            FechaRegistro DESC
        );

        -- ======================================
        -- 2. PROCEDIMIENTO INTERNO DE REGISTRO
        -- No se concede EXECUTE a shopcart_api.
        -- Lo invocaran los SPs de negocio.
        -- ======================================

        EXEC sys.sp_executesql N'
CREATE PROCEDURE dbo.SP_Auditoria_RegistrarCambio
    @IDUsuario INT,
    @Modulo VARCHAR(30),
    @Entidad VARCHAR(80),
    @IDEntidad VARCHAR(40),
    @Accion VARCHAR(30),
    @ValoresAnteriores NVARCHAR(MAX) = NULL,
    @ValoresNuevos NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @IDUsuario IS NULL
       OR NOT EXISTS (
           SELECT 1
           FROM dbo.Usuarios
           WHERE IDUsuario = @IDUsuario
       )
        THROW 73010,
            ''Usuario de auditoria invalido.'',
            1;

    IF @Modulo IS NULL
       OR @Modulo NOT IN (
           ''CATALOGO'',
           ''INVENTARIO'',
           ''CUPONES'',
           ''PEDIDOS'',
           ''USUARIOS''
       )
        THROW 73011,
            ''Modulo de auditoria invalido.'',
            1;

    IF NULLIF(LTRIM(RTRIM(@Entidad)), '''') IS NULL
       OR NULLIF(LTRIM(RTRIM(@IDEntidad)), '''') IS NULL
        THROW 73012,
            ''Entidad de auditoria invalida.'',
            1;

    IF @Accion IS NULL
       OR @Accion NOT IN (
           ''CREAR'',
           ''ACTUALIZAR'',
           ''DESACTIVAR'',
           ''ACTIVAR'',
           ''AJUSTAR'',
           ''CAMBIAR_ESTADO'',
           ''CANCELAR'',
           ''DEVOLVER''
       )
        THROW 73013,
            ''Accion de auditoria invalida.'',
            1;

    IF @ValoresAnteriores IS NOT NULL
       AND ISJSON(@ValoresAnteriores) <> 1
        THROW 73014,
            ''Valores anteriores no son JSON valido.'',
            1;

    IF @ValoresNuevos IS NOT NULL
       AND ISJSON(@ValoresNuevos) <> 1
        THROW 73015,
            ''Valores nuevos no son JSON valido.'',
            1;

    INSERT INTO dbo.BitacoraAuditoria (
        IDUsuario,
        Modulo,
        Entidad,
        IDEntidad,
        Accion,
        ValoresAnteriores,
        ValoresNuevos
    )
    VALUES (
        @IDUsuario,
        @Modulo,
        @Entidad,
        @IDEntidad,
        @Accion,
        @ValoresAnteriores,
        @ValoresNuevos
    );
END;
';

        -- ======================================
        -- 3. CONSULTA ADMINISTRATIVA PAGINADA
        -- ======================================

        EXEC sys.sp_executesql N'
CREATE PROCEDURE dbo.SP_Auditoria_Listar
    @IDUsuario INT,
    @Modulo VARCHAR(30) = NULL,
    @IDUsuarioFiltro INT = NULL,
    @FechaInicio DATE = NULL,
    @FechaFin DATE = NULL,
    @Pagina INT = 1,
    @TamanoPagina INT = 20
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Usuarios u
        INNER JOIN dbo.Roles r
            ON r.IDRol = u.IDRol
        WHERE u.IDUsuario = @IDUsuario
          AND u.Activo = 1
          AND r.Nombre = ''Administrador''
    )
        THROW 73020,
            ''Solo Administrador puede consultar auditoria.'',
            1;

    IF @Pagina IS NULL OR @Pagina < 1
       OR @TamanoPagina IS NULL
       OR @TamanoPagina NOT BETWEEN 1 AND 100
        THROW 73021,
            ''Paginacion invalida.'', 1;

    IF @Modulo IS NOT NULL
       AND @Modulo NOT IN (
           ''CATALOGO'',
           ''INVENTARIO'',
           ''CUPONES'',
           ''PEDIDOS'',
           ''USUARIOS''
       )
        THROW 73022,
            ''Filtro de modulo invalido.'', 1;

    IF @IDUsuarioFiltro IS NOT NULL
       AND @IDUsuarioFiltro <= 0
        THROW 73023,
            ''Filtro de usuario invalido.'', 1;

    IF @FechaInicio IS NOT NULL
       AND @FechaFin IS NOT NULL
       AND @FechaInicio > @FechaFin
        THROW 73024,
            ''Rango de fechas invalido.'', 1;

    IF @FechaFin >= ''99991231''
        THROW 73025,
            ''Fecha final fuera de rango.'', 1;

    DECLARE @Hasta DATETIME2(3) = NULL;

    IF @FechaFin IS NOT NULL
        SET @Hasta = DATEADD(
            DAY, 1,
            CONVERT(DATETIME2(3), @FechaFin)
        );

    DECLARE @Offset BIGINT =
        (CONVERT(BIGINT, @Pagina) - 1)
        * @TamanoPagina;

    CREATE TABLE #Filtrados (
        IDBitacora BIGINT NOT NULL PRIMARY KEY
    );

    INSERT INTO #Filtrados (IDBitacora)
    SELECT b.IDBitacora
    FROM dbo.BitacoraAuditoria b
    WHERE
        (@Modulo IS NULL OR b.Modulo = @Modulo)
        AND (
            @IDUsuarioFiltro IS NULL
            OR b.IDUsuario = @IDUsuarioFiltro
        )
        AND (
            @FechaInicio IS NULL
            OR b.FechaRegistro >= @FechaInicio
        )
        AND (
            @Hasta IS NULL
            OR b.FechaRegistro < @Hasta
        );

    DECLARE @Total BIGINT;

    SELECT @Total = COUNT_BIG(*)
    FROM #Filtrados;

    SELECT
        b.IDBitacora,
        b.IDUsuario,
        b.Modulo,
        b.Entidad,
        b.IDEntidad,
        b.Accion,
        b.ValoresAnteriores,
        b.ValoresNuevos,
        b.FechaRegistro
    FROM #Filtrados f
    INNER JOIN dbo.BitacoraAuditoria b
        ON b.IDBitacora = f.IDBitacora
    ORDER BY
        b.FechaRegistro DESC,
        b.IDBitacora DESC
    OFFSET @Offset ROWS
    FETCH NEXT @TamanoPagina ROWS ONLY;

    SELECT
        @Pagina AS Pagina,
        @TamanoPagina AS TamanoPagina,
        @Total AS TotalRegistros,
        CASE
            WHEN @Total = 0 THEN
                CONVERT(BIGINT, 0)
            ELSE
                (@Total + @TamanoPagina - 1)
                / @TamanoPagina
        END AS TotalPaginas;
END;
';

        -- ======================================
        -- 4. BLOQUEAR UPDATE Y DELETE
        -- ======================================

        EXEC sys.sp_executesql N'
CREATE TRIGGER dbo.TR_Bitacora_BloquearCambios
ON dbo.BitacoraAuditoria
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM deleted)
        THROW 73030,
            ''La bitacora no admite cambios ni eliminaciones.'',
            1;
END;
';

        -- ======================================
        -- 5. PERMISOS
        -- ======================================

        -- La API solo puede consultar mediante SP.
        GRANT EXECUTE
        ON OBJECT::dbo.SP_Auditoria_Listar
        TO [shopcart_api];

        -- No conceder EXECUTE sobre RegistrarCambio
        -- ni permisos directos de escritura.
        DENY INSERT, UPDATE, DELETE
        ON OBJECT::dbo.BitacoraAuditoria
        TO [shopcart_api];

        INSERT INTO dbo.SchemaMigrations (
            Numero,
            Nombre
        )
        VALUES (
            36,
            N'036_AuditLog'
        );

        PRINT 'Migracion 036 aplicada correctamente.';
    END
    ELSE
    BEGIN
        IF OBJECT_ID(
            N'dbo.BitacoraAuditoria', N'U'
        ) IS NULL
           OR OBJECT_ID(
            N'dbo.SP_Auditoria_RegistrarCambio', N'P'
        ) IS NULL
           OR OBJECT_ID(
            N'dbo.SP_Auditoria_Listar', N'P'
        ) IS NULL
           OR OBJECT_ID(
            N'dbo.TR_Bitacora_BloquearCambios', N'TR'
        ) IS NULL
            THROW 73003,
                'Migracion registrada con objetos faltantes.',
                1;

        PRINT 'Migracion 036 ya aplicada.';
    END;

    COMMIT TRANSACTION;

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
