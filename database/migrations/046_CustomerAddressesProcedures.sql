USE ShopCartDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

-- ==========================================
-- MIGRACION 046
-- RF-06: DIRECCIONES DEL CLIENTE
-- ==========================================

IF NOT EXISTS (
    SELECT 1
    FROM dbo.SchemaMigrations
    WHERE Numero = 45
)
    THROW 78200,
        'Primero ejecute la migracion 045.', 1;
GO

-- ==========================================
-- 1. CREAR DIRECCION
-- ==========================================

CREATE OR ALTER PROCEDURE dbo.SP_Direcciones_CrearCliente
    @IDUsuario INT,
    @Destinatario NVARCHAR(150),
    @Telefono NVARCHAR(25),
    @Departamento NVARCHAR(100),
    @Municipio NVARCHAR(100),
    @DireccionLinea1 NVARCHAR(250),
    @Referencia NVARCHAR(250) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Destinatario = LTRIM(RTRIM(@Destinatario));
    SET @Telefono = LTRIM(RTRIM(@Telefono));
    SET @Departamento = LTRIM(RTRIM(@Departamento));
    SET @Municipio = LTRIM(RTRIM(@Municipio));
    SET @DireccionLinea1 = LTRIM(RTRIM(@DireccionLinea1));
    SET @Referencia = NULLIF(
        LTRIM(RTRIM(@Referencia)), N''
    );

    IF @IDUsuario IS NULL OR @IDUsuario <= 0
        THROW 78210, 'Usuario invalido.', 1;

    IF @Destinatario IS NULL
       OR LEN(@Destinatario) NOT BETWEEN 3 AND 150
       OR @Telefono IS NULL
       OR LEN(@Telefono) NOT BETWEEN 8 AND 25
       OR @Departamento IS NULL
       OR LEN(@Departamento) NOT BETWEEN 2 AND 100
       OR @Municipio IS NULL
       OR LEN(@Municipio) NOT BETWEEN 2 AND 100
       OR @DireccionLinea1 IS NULL
       OR LEN(@DireccionLinea1) NOT BETWEEN 5 AND 250
        THROW 78211, 'Datos de direccion invalidos.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Usuarios u WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.Roles r
                ON r.IDRol = u.IDRol
            WHERE u.IDUsuario = @IDUsuario
              AND u.Activo = 1
              AND r.Nombre = 'Cliente'
        )
            THROW 78212, 'Cliente no autorizado.', 1;

        INSERT INTO dbo.Direcciones (
            IDUsuario,
            Destinatario,
            Telefono,
            Departamento,
            Municipio,
            DireccionLinea1,
            Referencia
        )
        VALUES (
            @IDUsuario,
            @Destinatario,
            @Telefono,
            @Departamento,
            @Municipio,
            @DireccionLinea1,
            @Referencia
        );

        DECLARE @IDDireccion INT =
            CONVERT(INT, SCOPE_IDENTITY());

        COMMIT TRANSACTION;

        SELECT
            IDDireccion,
            Destinatario,
            Telefono,
            Departamento,
            Municipio,
            DireccionLinea1,
            Referencia,
            Activa,
            FechaCreacion
        FROM dbo.Direcciones
        WHERE IDDireccion = @IDDireccion
          AND IDUsuario = @IDUsuario;

    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
GO

-- ==========================================
-- 2. LISTAR DIRECCIONES PROPIAS
-- ==========================================

CREATE OR ALTER PROCEDURE dbo.SP_Direcciones_ListarCliente
    @IDUsuario INT
AS
BEGIN
    SET NOCOUNT ON;

    IF @IDUsuario IS NULL OR @IDUsuario <= 0
        THROW 78210, 'Usuario invalido.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Usuarios u
        INNER JOIN dbo.Roles r
            ON r.IDRol = u.IDRol
        WHERE u.IDUsuario = @IDUsuario
          AND u.Activo = 1
          AND r.Nombre = 'Cliente'
    )
        THROW 78212, 'Cliente no autorizado.', 1;

    SELECT
        IDDireccion,
        Destinatario,
        Telefono,
        Departamento,
        Municipio,
        DireccionLinea1,
        Referencia,
        Activa,
        FechaCreacion
    FROM dbo.Direcciones
    WHERE IDUsuario = @IDUsuario
      AND Activa = 1
    ORDER BY FechaCreacion DESC, IDDireccion DESC;
END;
GO

-- ==========================================
-- 3. CONSULTAR DIRECCION POR ID
-- ==========================================

CREATE OR ALTER PROCEDURE dbo.SP_Direcciones_ObtenerCliente
    @IDUsuario INT,
    @IDDireccion INT
AS
BEGIN
    SET NOCOUNT ON;

    IF @IDUsuario IS NULL OR @IDUsuario <= 0
        THROW 78210, 'Usuario invalido.', 1;

    IF @IDDireccion IS NULL OR @IDDireccion <= 0
        THROW 78213, 'Direccion invalida.', 1;

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.Usuarios u
        INNER JOIN dbo.Roles r
            ON r.IDRol = u.IDRol
        WHERE u.IDUsuario = @IDUsuario
          AND u.Activo = 1
          AND r.Nombre = 'Cliente'
    )
        THROW 78212, 'Cliente no autorizado.', 1;

    -- No permite consultar direcciones ajenas.
    SELECT
        IDDireccion,
        Destinatario,
        Telefono,
        Departamento,
        Municipio,
        DireccionLinea1,
        Referencia,
        Activa,
        FechaCreacion
    FROM dbo.Direcciones
    WHERE IDDireccion = @IDDireccion
      AND IDUsuario = @IDUsuario
      AND Activa = 1;
END;
GO

-- ==========================================
-- 4. PERMISOS Y REGISTRO
-- ==========================================

BEGIN TRY
    BEGIN TRANSACTION;

    IF DATABASE_PRINCIPAL_ID(N'shopcart_api') IS NULL
        THROW 78214,
            'No existe el usuario shopcart_api.', 1;

    GRANT EXECUTE
    ON OBJECT::dbo.SP_Direcciones_CrearCliente
    TO [shopcart_api];

    GRANT EXECUTE
    ON OBJECT::dbo.SP_Direcciones_ListarCliente
    TO [shopcart_api];

    GRANT EXECUTE
    ON OBJECT::dbo.SP_Direcciones_ObtenerCliente
    TO [shopcart_api];

    IF NOT EXISTS (
        SELECT 1
        FROM dbo.SchemaMigrations WITH (UPDLOCK, HOLDLOCK)
        WHERE Numero = 46
    )
    BEGIN
        INSERT INTO dbo.SchemaMigrations (Numero, Nombre)
        VALUES (46, N'046_CustomerAddressesProcedures');
    END;

    COMMIT TRANSACTION;

    PRINT 'Migracion 046 aplicada correctamente.';

END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO
