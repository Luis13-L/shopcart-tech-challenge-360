USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- MIGRACION 061: corregir validacion de SKU con guiones.
-- Conserva todas las reglas de negocio, auditoria e inicializacion
-- de existencias del procedimiento de la migracion 059.
-- Requiere las migraciones 059 y 060 previamente aplicadas.

BEGIN TRY
    BEGIN TRANSACTION;

    IF NOT EXISTS (
        SELECT 1 FROM dbo.SchemaMigrations WHERE Numero = 60
    )
        THROW 80500, 'Primero ejecute la migracion 060.', 1;

    IF NOT EXISTS (
        SELECT 1 FROM dbo.SchemaMigrations WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 61
    )
    BEGIN
        IF OBJECT_ID(N'dbo.SP_Catalogo_CrearVariante', N'P') IS NULL
            THROW 80501, 'No existe el procedimiento de creacion de variantes.', 1;

        IF DATABASE_PRINCIPAL_ID(N'shopcart_api') IS NULL
            THROW 80502, 'No existe el usuario shopcart_api.', 1;

        -- CREATE OR ALTER debe ejecutarse en su propio batch.
        EXEC sys.sp_executesql N'
CREATE OR ALTER PROCEDURE dbo.SP_Catalogo_CrearVariante
    @IDUsuarioActor INT,
    @IDProducto INT,
    @SKU NVARCHAR(64),
    @PrecioActual DECIMAL(19,2),
    @AtributosJson NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Validaciones de entrada independientes de la API.
    IF @IDProducto IS NULL OR @IDProducto <= 0
        THROW 80310, ''ID de producto invalido.'', 1;

    SET @SKU = UPPER(LTRIM(RTRIM(@SKU)));

    IF @SKU IS NULL OR LEN(@SKU) NOT BETWEEN 3 AND 64
       -- El guion se retira SOLO para validar caracteres.
       -- El SKU original se almacena sin modificaciones.
       OR PATINDEX(
           N''%[^A-Z0-9._]%'',
           REPLACE(@SKU, N''-'', N'''') COLLATE Latin1_General_100_BIN2
       ) > 0
        THROW 80311, ''SKU invalido.'', 1;

    IF @PrecioActual IS NULL OR @PrecioActual <= 0
        THROW 80312, ''Precio invalido.'', 1;

    IF @AtributosJson IS NULL
       OR ISJSON(@AtributosJson) <> 1
        THROW 80313, ''JSON de atributos invalido.'', 1;

    IF LEFT(LTRIM(@AtributosJson), 1) <> N''[''
       OR DATALENGTH(@AtributosJson) > 8000
        THROW 80313, ''Los atributos requieren un arreglo JSON valido.'', 1;

    -- NVARCHAR(4000) evita truncar silenciosamente antes de validar.
    DECLARE @Atributos TABLE (
        Nombre NVARCHAR(4000) NULL,
        Valor NVARCHAR(4000) NULL
    );

    IF EXISTS (
        SELECT 1
        FROM OPENJSON(@AtributosJson)
        WHERE [type] <> 5
    )
        THROW 80313, ''Cada atributo debe ser un objeto.'', 1;

    INSERT INTO @Atributos (Nombre, Valor)
    SELECT
        LTRIM(RTRIM(a.Nombre)),
        LTRIM(RTRIM(a.Valor))
    FROM OPENJSON(@AtributosJson)
    WITH (
        Nombre NVARCHAR(4000) ''$.nombre'',
        Valor NVARCHAR(4000) ''$.valor''
    ) AS a;

    IF (SELECT COUNT(*) FROM @Atributos) NOT BETWEEN 1 AND 8
       OR EXISTS (
           SELECT 1
           FROM @Atributos
           WHERE Nombre IS NULL OR LEN(Nombre) NOT BETWEEN 1 AND 60
              OR Valor IS NULL OR LEN(Valor) NOT BETWEEN 1 AND 100
       )
       OR EXISTS (
           SELECT 1
           FROM @Atributos
           GROUP BY Nombre COLLATE Latin1_General_100_CI_AS
           HAVING COUNT(*) > 1
       )
        THROW 80314,
            ''Atributos invalidos o duplicados (1 a 8 atributos).'', 1;

    DECLARE @IDVariante INT;
    DECLARE @IDVarianteTexto VARCHAR(40);
    DECLARE @NuevoEstado NVARCHAR(MAX);

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Usuarios u
            INNER JOIN dbo.Roles r ON r.IDRol = u.IDRol
            WHERE u.IDUsuario = @IDUsuarioActor
              AND u.Activo = 1
              AND r.Nombre = ''Administrador''
        )
            THROW 80315, ''Administrador no autorizado.'', 1;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Productos p WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.Categorias c WITH (UPDLOCK, HOLDLOCK)
                ON c.IDCategoria = p.IDCategoria
            WHERE p.IDProducto = @IDProducto
              AND p.Activo = 1
              AND c.Activa = 1
        )
            THROW 80316, ''Producto o categoria inactiva/inexistente.'', 1;

        IF EXISTS (
            SELECT 1
            FROM dbo.Variantes WITH (UPDLOCK, HOLDLOCK)
            WHERE SKU = @SKU
        )
            THROW 80317, ''El SKU ya existe.'', 1;

        INSERT INTO dbo.Variantes (
            IDProducto, SKU, PrecioActual, Activa, FechaCreacion
        ) VALUES (
            @IDProducto, @SKU, @PrecioActual, 1, SYSUTCDATETIME()
        );

        SET @IDVariante = CONVERT(INT, SCOPE_IDENTITY());
        SET @IDVarianteTexto = CONVERT(VARCHAR(40), @IDVariante);

        INSERT INTO dbo.AtributosVariante (
            IDVariante, Nombre, Valor
        )
        SELECT @IDVariante, Nombre, Valor
        FROM @Atributos;

        -- El trigger de la migracion 045 crea el registro de stock en cero.
        IF NOT EXISTS (
            SELECT 1 FROM dbo.Existencias
            WHERE IDVariante = @IDVariante AND CantidadFisica = 0
        )
            THROW 80318, ''No se inicializo la existencia en cero.'', 1;

        SELECT @NuevoEstado = (
            SELECT
                v.IDVariante, v.IDProducto, v.SKU,
                v.PrecioActual, v.Activa,
                JSON_QUERY((
                    SELECT av.Nombre AS nombre, av.Valor AS valor
                    FROM dbo.AtributosVariante av
                    WHERE av.IDVariante = v.IDVariante
                    ORDER BY av.Nombre
                    FOR JSON PATH
                )) AS atributos
            FROM dbo.Variantes v
            WHERE v.IDVariante = @IDVariante
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        EXEC dbo.SP_Auditoria_RegistrarCambio
            @IDUsuario = @IDUsuarioActor,
            @Modulo = ''CATALOGO'',
            @Entidad = ''Variantes'',
            @IDEntidad = @IDVarianteTexto,
            @Accion = ''CREAR'',
            @ValoresAnteriores = NULL,
            @ValoresNuevos = @NuevoEstado;

        COMMIT TRANSACTION;

        SELECT
            v.IDVariante,
            v.IDProducto,
            v.SKU,
            CONVERT(VARCHAR(32), v.PrecioActual) AS PrecioActual,
            v.Activa,
            e.CantidadFisica
        FROM dbo.Variantes v
        INNER JOIN dbo.Existencias e ON e.IDVariante = v.IDVariante
        WHERE v.IDVariante = @IDVariante;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;';

        GRANT EXECUTE
        ON OBJECT::dbo.SP_Catalogo_CrearVariante
        TO [shopcart_api];

        INSERT INTO dbo.SchemaMigrations (Numero, Nombre)
        VALUES (61, N'061_FixVariantSkuHyphenValidation');

        PRINT 'OK: Migracion 061 aplicada correctamente.';
    END
    ELSE
    BEGIN
        IF OBJECT_ID(N'dbo.SP_Catalogo_CrearVariante', N'P') IS NULL
            THROW 80503, 'Migracion 061 registrada sin procedimiento.', 1;

        PRINT 'OK: Migracion 061 ya aplicada.';
    END;

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
